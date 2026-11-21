-- POCA 펄스 '바꿔보자! 한 가지만!' (매주 한 문항, 문자 발송)
-- poca_setup.sql 을 먼저 실행한 데이터베이스에서 실행하세요. 여러 번 실행해도 괜찮습니다. 고칠 곳은 없습니다.
-- 자동 발송 일정은 pulse_one_schedule.sql 에서 따로 켭니다.
--
-- 흐름
--   수요일 18:00  pulse_close()  : 이번 주 질문 마감, 평균 계산 → 인사팀이 확인하고 승인
--   목요일 12:00  pulse_open()   : 다음 질문을 열고, 승인된 지난주 결과와 함께 문자 대기열(outbox)에 넣음
--   다음 질문 규칙: 지난주 '우리 팀' 평균이 7점 이상이거나, 같은 질문을 3주 했으면 다음 질문으로
-- 익명
--   명단(이름·전화번호)과 응답은 서로 다른 표에 있고, 둘을 잇는 기록·시각을 남기지 않습니다.

create extension if not exists pgcrypto;

create table if not exists public.pulse_programs (
  code        text primary key check (code ~ '^[A-Z0-9]{4,8}$'),
  info        jsonb not null default '{}'::jsonb,  -- name, items[{n,q}], hr, base(링크 주소), open, org_code
  created_at  timestamptz not null default now()
);

create table if not exists public.pulse_members (
  token         uuid primary key default gen_random_uuid(),
  program_code  text not null references public.pulse_programs(code) on delete cascade,
  name          text not null check (length(name) between 1 and 40),
  dept          text check (dept is null or length(dept) <= 40),
  phone         text check (phone is null or phone ~ '^[0-9]{9,12}$'),
  active        boolean not null default true
);
create index if not exists pulse_members_prog on public.pulse_members(program_code);

create table if not exists public.pulse_weeks (
  id            bigserial primary key,
  program_code  text not null references public.pulse_programs(code) on delete cascade,
  week_no       int not null,
  item_idx      int not null,
  item_n        int,
  question      text not null,
  opened_on     date not null default (now() at time zone 'Asia/Seoul')::date,
  closed        boolean not null default false,
  approved      boolean not null default false,
  n             int,
  avg           numeric(4,2),   -- '나' 평균
  team_avg      numeric(4,2),   -- '우리 팀' 평균 (다음 질문으로 넘어가는 기준)
  unique (program_code, week_no)
);
alter table public.pulse_weeks add column if not exists team_avg numeric(4,2);

-- 응답: 누가 냈는지(토큰)도, 언제 냈는지(시각)도 남기지 않습니다.
create table if not exists public.pulse_answers (
  week_id         bigint not null references public.pulse_weeks(id) on delete cascade,
  respondent_key  uuid not null,
  score           int not null check (score between 1 and 10),        -- 나는
  team_score      int check (team_score between 1 and 10),            -- 우리 팀은
  note            text check (note is null or length(note) <= 200),
  primary key (week_id, respondent_key)
);

-- 완료 여부: 이름 쪽에는 '했다/안 했다'만.
alter table public.pulse_answers add column if not exists team_score int check (team_score between 1 and 10);

create table if not exists public.pulse_done (
  week_id  bigint not null references public.pulse_weeks(id) on delete cascade,
  token    uuid not null references public.pulse_members(token) on delete cascade,
  primary key (week_id, token)
);

create table if not exists public.pulse_outbox (
  id            bigserial primary key,
  program_code  text not null references public.pulse_programs(code) on delete cascade,
  phone         text not null,
  text          text not null,
  status        text not null default 'pending' check (status in ('pending','sent','failed')),
  error         text,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);

do $$ declare t text; begin
  foreach t in array array['pulse_programs','pulse_members','pulse_weeks','pulse_answers','pulse_done','pulse_outbox'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_admin', t);
    execute format('create policy %I on public.%I for all to authenticated using (public.poca_is_admin()) with check (public.poca_is_admin())', t||'_admin', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
grant usage, select on all sequences in schema public to authenticated;

-- 열려 있는(마감 전) 이번 주
create or replace function public.pulse_current_week(p_code text)
returns public.pulse_weeks
language sql stable security definer set search_path = public
as $$
  select * from public.pulse_weeks where program_code = p_code and not closed order by week_no desc limit 1;
$$;

-- 승인된 가장 최근 결과와 그 앞 주와의 차이
create or replace function public.pulse_last_result(p_code text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  with a as (
    select week_no, question, avg, team_avg, n, row_number() over (order by week_no desc) as rk
    from public.pulse_weeks where program_code = p_code and closed and approved and avg is not null
  )
  select case when x.week_no is null then null else jsonb_build_object(
    'week_no', x.week_no, 'question', x.question, 'avg', x.avg, 'team_avg', x.team_avg, 'n', x.n,
    'delta', (select x.avg - y.avg from a y where y.rk = 2),
    'team_delta', (select x.team_avg - y.team_avg from a y where y.rk = 2)) end
  from (select * from a where rk = 1) x;
$$;

-- 1) 응답자: 개인 링크로 이번 주 질문 보기
create or replace function public.pulse_get(p_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare m public.pulse_members; p public.pulse_programs; w public.pulse_weeks;
begin
  select * into m from public.pulse_members where token = p_token and active;
  if m.token is null then return null; end if;
  select * into p from public.pulse_programs where code = m.program_code;
  w := public.pulse_current_week(p.code);
  return jsonb_build_object(
    'program', p.info->>'name',
    'name', m.name,
    'open', w.id is not null and coalesce((p.info->>'open')::boolean, true),
    'week_no', w.week_no,
    'question', w.question,
    'done', exists (select 1 from public.pulse_done d where d.week_id = w.id and d.token = p_token),
    'last', public.pulse_last_result(p.code));
end;
$$;

-- 2) 응답자: 이번 주 답 내기 (같은 기기에서 다시 내면 덮어씀)
drop function if exists public.pulse_submit(uuid, uuid, int, text);
create or replace function public.pulse_submit(p_token uuid, p_key uuid, p_score int, p_team int, p_note text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare m public.pulse_members; w public.pulse_weeks;
begin
  if p_score is null or p_score < 1 or p_score > 10 then return false; end if;
  if p_team is not null and (p_team < 1 or p_team > 10) then return false; end if;
  select * into m from public.pulse_members where token = p_token and active;
  if m.token is null then return false; end if;
  w := public.pulse_current_week(m.program_code);
  if w.id is null then return false; end if;
  insert into public.pulse_answers (week_id, respondent_key, score, team_score, note)
  values (w.id, p_key, p_score, p_team, nullif(left(trim(coalesce(p_note,'')), 200), ''))
  on conflict (week_id, respondent_key) do update set score = excluded.score, team_score = excluded.team_score, note = excluded.note;
  insert into public.pulse_done (week_id, token) values (w.id, p_token) on conflict do nothing;
  return true;
end;
$$;

-- 3) 인사팀 화면: 주차별 결과(마감된 주는 의견 포함), 이번 주 완료 명단
create or replace function public.pulse_hr(p_code text, p_hr text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare p public.pulse_programs; w public.pulse_weeks;
begin
  select * into p from public.pulse_programs where code = upper(trim(p_code));
  if p.code is null or (p.info->>'hr') is null or (p.info->>'hr') <> p_hr then return null; end if;
  w := public.pulse_current_week(p.code);
  return jsonb_build_object(
    'name', p.info->>'name',
    'members', (select count(*) from public.pulse_members where program_code = p.code and active),
    'weeks', coalesce((select jsonb_agg(jsonb_build_object(
        'id', k.id, 'week_no', k.week_no, 'question', k.question, 'item_n', k.item_n, 'opened_on', k.opened_on,
        'closed', k.closed, 'approved', k.approved,
        'n', coalesce(k.n, (select count(*) from public.pulse_answers a where a.week_id = k.id)),
        'avg', coalesce(k.avg, (select round(avg(score)::numeric, 2) from public.pulse_answers a where a.week_id = k.id)),
        'team_avg', coalesce(k.team_avg, (select round(avg(team_score)::numeric, 2) from public.pulse_answers a where a.week_id = k.id)),
        'notes', case when k.closed then coalesce((select jsonb_agg(a.note order by md5(a.respondent_key::text)) from public.pulse_answers a where a.week_id = k.id and a.note is not null), '[]'::jsonb) else '[]'::jsonb end
      ) order by k.week_no desc) from public.pulse_weeks k where k.program_code = p.code), '[]'::jsonb),
    'current', case when w.id is null then null else jsonb_build_object(
        'week_no', w.week_no,
        'people', coalesce((select jsonb_agg(jsonb_build_object('name', m.name, 'dept', m.dept,
                    'done', exists (select 1 from public.pulse_done d where d.week_id = w.id and d.token = m.token)) order by m.name)
                  from public.pulse_members m where m.program_code = p.code and m.active), '[]'::jsonb)) end);
end;
$$;

-- 4) 인사팀: 마감된 주 결과를 확인하고 승인 → 다음 문자에 평균이 실림
create or replace function public.pulse_hr_approve(p_code text, p_hr text, p_week bigint)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare p public.pulse_programs;
begin
  select * into p from public.pulse_programs where code = upper(trim(p_code));
  if p.code is null or (p.info->>'hr') is null or (p.info->>'hr') <> p_hr then return false; end if;
  update public.pulse_weeks set approved = true where id = p_week and program_code = p.code and closed;
  return found;
end;
$$;

-- 5) 마감 (수요일 18:00): 평균을 확정
create or replace function public.pulse_close(p_code text default null)
returns int
language plpgsql security definer set search_path = public
as $$
declare cnt int;
begin
  update public.pulse_weeks w set closed = true,
    n = (select count(*) from public.pulse_answers a where a.week_id = w.id),
    avg = (select round(avg(score)::numeric, 2) from public.pulse_answers a where a.week_id = w.id),
    team_avg = (select round(avg(team_score)::numeric, 2) from public.pulse_answers a where a.week_id = w.id)
  where not closed and (p_code is null or program_code = p_code);
  get diagnostics cnt = row_count;
  return cnt;
end;
$$;

-- 6) 다음 질문 열기 (목요일 12:00): 규칙대로 질문을 고르고, 문자 대기열에 넣음
create or replace function public.pulse_open(p_code text default null)
returns int
language plpgsql security definer set search_path = public
as $$
declare p public.pulse_programs; last public.pulse_weeks; items jsonb; nitems int; idx int; streak int;
        q text; itn int; res jsonb; line text; made int := 0; m record; base text;
begin
  perform public.pulse_close(p_code);  -- 혹시 열린 주가 남아 있으면 먼저 마감
  for p in select * from public.pulse_programs
           where coalesce((info->>'open')::boolean, true) and (p_code is null or code = p_code) loop
    items := coalesce(p.info->'items', '[]'::jsonb); nitems := jsonb_array_length(items);
    if nitems = 0 then continue; end if;
    select * into last from public.pulse_weeks where program_code = p.code order by week_no desc limit 1;
    if last.id is null then idx := 0;
    else
      select count(*) into streak from (
        select item_idx, row_number() over (order by week_no desc) rn,
               row_number() over (partition by item_idx order by week_no desc) rn2
        from public.pulse_weeks where program_code = p.code) s
      where s.item_idx = last.item_idx and s.rn = s.rn2;
      if (coalesce(last.team_avg, last.avg) is not null and coalesce(last.team_avg, last.avg) >= 7) or streak >= 3 then idx := (last.item_idx + 1) % nitems;
      else idx := last.item_idx; end if;
    end if;
    q := items->idx->>'q'; itn := nullif(coalesce(items->idx->>'c', items->idx->>'n'),'')::int;  -- c = 문화 1~4 (관계·질서·성과·혁신)
    insert into public.pulse_weeks (program_code, week_no, item_idx, item_n, question)
    values (p.code, coalesce(last.week_no, 0) + 1, idx, itn, q);
    made := made + 1;
    res := public.pulse_last_result(p.code);
    line := case when res is null then ''
      else '지난주 평균 나 ' || to_char((res->>'avg')::numeric, 'FM90.0')
           || case when res->>'team_avg' is null then '' else ' · 우리 팀 ' || to_char((res->>'team_avg')::numeric, 'FM90.0') end
           || case when res->>'team_delta' is null then '' else ' (' || case when (res->>'team_delta')::numeric >= 0 then '+' else '' end || to_char((res->>'team_delta')::numeric, 'FM90.0') || ')' end
           || '. ' end;
    base := coalesce(p.info->>'base', '');
    for m in select token, phone from public.pulse_members where program_code = p.code and active and phone is not null loop
      insert into public.pulse_outbox (program_code, phone, text)
      values (p.code, m.phone, '[바꿔보자! 한 가지만] ' || line || '이번 주 질문: ' || q || ' ' || base || '#p/' || m.token);
    end loop;
  end loop;
  return made;
end;
$$;

revoke execute on function public.pulse_current_week(text), public.pulse_last_result(text), public.pulse_close(text), public.pulse_open(text) from public, anon, authenticated;
revoke execute on function public.pulse_get(uuid), public.pulse_submit(uuid, uuid, int, int, text), public.pulse_hr(text, text), public.pulse_hr_approve(text, text, bigint) from public;
grant execute on function public.pulse_get(uuid), public.pulse_submit(uuid, uuid, int, int, text), public.pulse_hr(text, text), public.pulse_hr_approve(text, text, bigint) to anon, authenticated;

-- 관리자가 화면에서 '지금 첫 질문 보내기'를 누를 때
create or replace function public.pulse_start_now(p_code text)
returns int
language plpgsql security definer set search_path = public
as $$
begin
  if not public.poca_is_admin() then raise exception 'not admin'; end if;
  return public.pulse_open(upper(trim(p_code)));
end;
$$;
revoke execute on function public.pulse_start_now(text) from public, anon;
grant execute on function public.pulse_start_now(text) to authenticated;
