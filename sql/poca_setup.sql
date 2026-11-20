-- POCA 웹사이트 데이터베이스 설정
-- Supabase > SQL Editor 에 전부 붙여넣고 Run 을 누르세요. 한 번만 실행하면 됩니다.
-- 맨 아래 '관리자 이메일' 줄의 이메일만 바꿔 주세요.

create extension if not exists pgcrypto;

-- 1) 표 만들기 -------------------------------------------------------------
create table if not exists public.poca_orgs (
  code        text primary key check (code ~ '^[A-Z0-9]{4,8}$'),
  info        jsonb not null default '{}'::jsonb,   -- 회사 이름, 부서 목록, 대상 인원, 마감 여부, 펄스/시범 설정
  created_at  timestamptz not null default now()
);

create table if not exists public.poca_responses (
  id              uuid primary key default gen_random_uuid(),
  org_code        text not null references public.poca_orgs(code) on delete cascade,
  respondent_key  uuid not null,                      -- 기기에 남긴 무작위 번호 (사람과 연결되지 않음)
  data            jsonb not null,                     -- 응답 내용 (이름 없음)
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (org_code, respondent_key)
);

create table if not exists public.poca_admins (
  email text primary key
);

alter table public.poca_orgs      enable row level security;
alter table public.poca_responses enable row level security;
alter table public.poca_admins    enable row level security;

-- 2) 관리자 확인 ----------------------------------------------------------
create or replace function public.poca_is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.poca_admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- 3) 접근 규칙: 표는 관리자만 직접 읽고 쓸 수 있음 ---------------------------
drop policy if exists poca_orgs_admin on public.poca_orgs;
create policy poca_orgs_admin on public.poca_orgs
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

drop policy if exists poca_responses_admin on public.poca_responses;
create policy poca_responses_admin on public.poca_responses
  for all to authenticated
  using (public.poca_is_admin()) with check (public.poca_is_admin());

revoke all on public.poca_orgs, public.poca_responses, public.poca_admins from anon, authenticated;
grant select, insert, update, delete on public.poca_orgs, public.poca_responses to authenticated;

-- 4) 응답자용 통로 (로그인 없이) --------------------------------------------
-- 진단 코드로 회사 정보 하나만 가져오기 (목록은 볼 수 없음)
create or replace function public.poca_get_org(p_code text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select info from public.poca_orgs where code = upper(trim(p_code));
$$;

-- 응답 저장 (같은 기기에서 다시 내면 덮어씀, 마감된 진단은 받지 않음)
create or replace function public.poca_submit(p_code text, p_key uuid, p_data jsonb)
returns boolean
language plpgsql security definer
set search_path = public
as $$
declare v_info jsonb;
begin
  select info into v_info from public.poca_orgs where code = upper(trim(p_code));
  if v_info is null then return false; end if;
  if coalesce((v_info ->> 'open')::boolean, true) = false then return false; end if;
  if length(p_data::text) > 30000 then return false; end if;
  insert into public.poca_responses (org_code, respondent_key, data)
  values (upper(trim(p_code)), p_key, p_data)
  on conflict (org_code, respondent_key)
  do update set data = excluded.data, updated_at = now();
  return true;
end;
$$;

revoke execute on function public.poca_get_org(text), public.poca_submit(text, uuid, jsonb), public.poca_is_admin() from public;
grant execute on function public.poca_get_org(text), public.poca_submit(text, uuid, jsonb), public.poca_is_admin() to anon, authenticated;

-- 5) 관리자 이메일 (아래 이메일을 바꾸고, 여러 명이면 줄을 추가하세요) ----------
insert into public.poca_admins (email) values
  ('관리자이메일@paulnmark.com')
on conflict do nothing;
