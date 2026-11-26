-- 고객사 관리 (고객사 등록 · 수정 · 목록)
-- 실행 순서: poca_setup.sql 이후 한 번 실행. Supabase SQL Editor에 붙여넣고 Run을 누르세요.
-- 새 진단을 만들 때 등록된 고객사 가운데 고를 수 있게 합니다.

-- 1) 고객사 표 -------------------------------------------------------------
create table if not exists public.poca_clients (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(name) between 1 and 60),
  contact_name  text,
  contact_email text,
  contact_phone text,
  memo          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 같은 이름(대소문자 무시)의 고객사는 한 번만 등록
create unique index if not exists poca_clients_name_uq on public.poca_clients (lower(name));

-- 2) 접근 규칙: 관리자만 읽고 쓸 수 있음 -------------------------------------
alter table public.poca_clients enable row level security;

drop policy if exists poca_clients_admin on public.poca_clients;
create policy poca_clients_admin on public.poca_clients
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

revoke all on public.poca_clients from anon, authenticated;
grant select, insert, update, delete on public.poca_clients to authenticated;
