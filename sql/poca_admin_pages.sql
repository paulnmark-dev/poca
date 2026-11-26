-- 관리자 화면 데이터 (매니저 부서 · Atomic Culture 항목 · 메일 발송 실패 표시)
-- 실행 순서: poca_clients.sql 이후 한 번 실행. Supabase SQL Editor에 붙여넣고 Run.
-- 실행 후 Edge Function admin-manage 를 다시 배포해야 합니다 (발송 실패 기록, 매니저 부서 저장).

-- 1) 매니저 부서 -----------------------------------------------------------
alter table public.poca_admins add column if not exists dept text;

drop function if exists public.poca_admin_list();
create or replace function public.poca_admin_list()
returns table (email text, name text, dept text, last_sign_in_at timestamptz)
language sql stable security definer
set search_path = public, auth
as $$
  select a.email, a.name, a.dept, u.last_sign_in_at
  from public.poca_admins a
  left join auth.users u on lower(u.email) = lower(a.email)
  where public.poca_is_admin()
  order by a.email;
$$;

revoke all on function public.poca_admin_list() from public, anon;
grant execute on function public.poca_admin_list() to authenticated;

-- 2) Atomic Culture 항목 ----------------------------------------------------
create table if not exists public.poca_atomic_items (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  area        text,
  org_code    text references public.poca_orgs(code) on delete set null,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.poca_atomic_items enable row level security;

drop policy if exists poca_atomic_items_admin on public.poca_atomic_items;
create policy poca_atomic_items_admin on public.poca_atomic_items
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

revoke all on public.poca_atomic_items from anon, authenticated;
grant select, insert, update, delete on public.poca_atomic_items to authenticated;

-- 3) 안내 메일 발송 실패 표시 ----------------------------------------------
alter table public.poca_invites add column if not exists mail_failed boolean not null default false;
