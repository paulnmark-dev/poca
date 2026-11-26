-- 관리자 관리 (매니저 초대 · 정보 수정 · 최근 접속일)
-- 실행 순서: poca_setup.sql 이후 한 번 실행. Supabase SQL Editor에서 실행합니다.

-- 1) 관리자 이름 칼럼
alter table public.poca_admins add column if not exists name text;

-- 2) 관리자 목록 (이메일, 이름, 최근 접속일). 관리자만 호출할 수 있음
create or replace function public.poca_admin_list()
returns table (email text, name text, last_sign_in_at timestamptz)
language sql stable security definer
set search_path = public, auth
as $$
  select a.email, a.name, u.last_sign_in_at
  from public.poca_admins a
  left join auth.users u on lower(u.email) = lower(a.email)
  where public.poca_is_admin()
  order by a.email;
$$;

revoke all on function public.poca_admin_list() from public, anon;
grant execute on function public.poca_admin_list() to authenticated;
