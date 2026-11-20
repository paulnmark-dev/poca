-- Next Culture · WFG 데이터베이스 설정 (POCA 설정을 먼저 실행한 뒤에 실행하세요)
-- Supabase > SQL Editor 에 전부 붙여넣고 Run 을 누르세요. 여러 번 실행해도 괜찮습니다.
-- 관리자는 POCA와 같은 관리자 명단(poca_admins)을 씁니다.

create table if not exists public.wfg_sessions (
  code        text primary key check (code ~ '^[A-Z0-9]{4,12}$'),
  info        jsonb not null default '{}'::jsonb,   -- 워크숍 이름, 명제, 우리의 문장, 액션 플랜 / 회사 단위 문장
  created_at  timestamptz not null default now()
);

create table if not exists public.wfg_responses (
  id              uuid primary key default gen_random_uuid(),
  session_code    text not null references public.wfg_sessions(code) on delete cascade,
  respondent_key  uuid not null,                     -- 기기에 남긴 무작위 번호 (워크숍 전후 응답을 짝짓는 데만 씀)
  phase           text not null check (phase in ('pre','post')),
  data            jsonb not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (session_code, respondent_key, phase)
);

alter table public.wfg_sessions  enable row level security;
alter table public.wfg_responses enable row level security;

drop policy if exists wfg_sessions_admin on public.wfg_sessions;
create policy wfg_sessions_admin on public.wfg_sessions
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

drop policy if exists wfg_responses_admin on public.wfg_responses;
create policy wfg_responses_admin on public.wfg_responses
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

revoke all on public.wfg_sessions, public.wfg_responses from anon, authenticated;
grant select, insert, update, delete on public.wfg_sessions, public.wfg_responses to authenticated;

-- 참가자용 통로 (로그인 없이)
create or replace function public.wfg_get_session(p_code text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select info from public.wfg_sessions
  where code = upper(trim(p_code)) and coalesce(info ->> 'kind', '') <> 'code';
$$;

create or replace function public.wfg_submit(p_code text, p_key uuid, p_phase text, p_data jsonb)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare v_info jsonb;
begin
  if p_phase not in ('pre','post') then return false; end if;
  select info into v_info from public.wfg_sessions
   where code = upper(trim(p_code)) and coalesce(info ->> 'kind', '') <> 'code';
  if v_info is null then return false; end if;
  if coalesce((v_info ->> 'open')::boolean, true) = false then return false; end if;
  if length(p_data::text) > 20000 then return false; end if;
  insert into public.wfg_responses (session_code, respondent_key, phase, data)
  values (upper(trim(p_code)), p_key, p_phase, p_data)
  on conflict (session_code, respondent_key, phase)
  do update set data = excluded.data, updated_at = now();
  return true;
end;
$$;

revoke execute on function public.wfg_get_session(text), public.wfg_submit(text, uuid, text, jsonb) from public;
grant execute on function public.wfg_get_session(text), public.wfg_submit(text, uuid, text, jsonb) to anon, authenticated;
