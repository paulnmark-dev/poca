-- POCA 업데이트 (2026-11): 명단 모드(개인 링크) · 인사 담당자 화면 · 익명 기준 선택
-- poca_setup.sql 을 이미 실행한 데이터베이스에서 실행하세요.
-- Supabase > SQL Editor 에 전부 붙여넣고 Run. 여러 번 실행해도 괜찮습니다. 고칠 곳은 없습니다.

-- 1) 명단 표: 이름과 '완료 여부'만 저장합니다. 응답 내용과는 연결하지 않습니다.
--    (응답 표 poca_responses 에는 이 표의 토큰이나 이름이 들어가지 않습니다)
create table if not exists public.poca_invites (
  token     uuid primary key default gen_random_uuid(),
  org_code  text not null references public.poca_orgs(code) on delete cascade,
  name      text not null check (length(name) between 1 and 40),
  dept      text check (dept is null or length(dept) <= 40),
  done      boolean not null default false
  -- 응답 시각과 짝지어 누가 답했는지 추정할 수 없도록, 시간 기록 칸은 두지 않습니다.
);
create index if not exists poca_invites_org on public.poca_invites(org_code);

alter table public.poca_invites enable row level security;
drop policy if exists poca_invites_admin on public.poca_invites;
create policy poca_invites_admin on public.poca_invites
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());
revoke all on public.poca_invites from anon, authenticated;
grant select, insert, update, delete on public.poca_invites to authenticated;

-- 2) 응답자에게 회사 정보를 줄 때 인사 담당자용 비밀값(hr)은 빼고 줍니다.
create or replace function public.poca_get_org(p_code text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select info - 'hr' from public.poca_orgs where code = upper(trim(p_code));
$$;

-- 3) 개인 링크로 들어온 응답자: 회사 정보 + 이름 + 완료 여부
create or replace function public.poca_get_invite(p_token uuid)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object('code', o.code, 'info', o.info - 'hr', 'name', i.name, 'done', i.done)
  from public.poca_invites i join public.poca_orgs o on o.code = i.org_code
  where i.token = p_token;
$$;

-- 4) 개인 링크로 낸 응답: 응답은 기존과 똑같이(토큰 없이) 저장하고, 명단에는 '완료'만 표시합니다.
create or replace function public.poca_submit_invite(p_code text, p_key uuid, p_data jsonb, p_token uuid)
returns boolean
language plpgsql security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.poca_invites where token = p_token and org_code = upper(trim(p_code))) then
    return false;
  end if;
  if not public.poca_submit(p_code, p_key, p_data - 'token' - 'name') then
    return false;
  end if;
  update public.poca_invites set done = true where token = p_token;
  return true;
end;
$$;

-- 5) 인사 담당자 화면: 응답 수, 부서별 응답 수, 명단별 완료 여부 (응답 내용은 주지 않음)
create or replace function public.poca_hr_status(p_code text, p_token text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'name', o.info->>'name',
    'open', coalesce((o.info->>'open')::boolean, true),
    'headcount', o.info->'headcount',
    'minN', coalesce((o.info->>'minN')::int, 3),
    'hrReport', coalesce((o.info->>'hrReport')::boolean, false),
    'total', (select count(*) from public.poca_responses r where r.org_code = o.code),
    'byDept', coalesce((select jsonb_agg(jsonb_build_object('dept', d.dept, 'n', d.n) order by d.dept)
                        from (select r.data->>'dept' as dept, count(*) as n
                              from public.poca_responses r where r.org_code = o.code
                              group by 1) d), '[]'::jsonb),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('token', i.token, 'name', i.name, 'dept', i.dept, 'done', i.done) order by i.name)
                         from public.poca_invites i where i.org_code = o.code), '[]'::jsonb)
  )
  from public.poca_orgs o
  where o.code = upper(trim(p_code)) and (o.info->>'hr') is not null and (o.info->>'hr') = p_token;
$$;

-- 6) 인사 담당자에게 결과 보고서를 공개한 진단만: 응답 묶음을 돌려줌 (응답 시간·시범 의견은 뺌)
create or replace function public.poca_hr_responses(p_code text, p_token text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(r.data - 'dur' - 'o3'), '[]'::jsonb)
  from public.poca_orgs o join public.poca_responses r on r.org_code = o.code
  where o.code = upper(trim(p_code))
    and (o.info->>'hr') is not null and (o.info->>'hr') = p_token
    and coalesce((o.info->>'hrReport')::boolean, false);
$$;

revoke execute on function public.poca_get_invite(uuid), public.poca_submit_invite(text, uuid, jsonb, uuid),
  public.poca_hr_status(text, text), public.poca_hr_responses(text, text) from public;
grant execute on function public.poca_get_org(text), public.poca_get_invite(uuid), public.poca_submit_invite(text, uuid, jsonb, uuid),
  public.poca_hr_status(text, text), public.poca_hr_responses(text, text) to anon, authenticated;
