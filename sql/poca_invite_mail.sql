-- 참여 안내 메일 (명단 이메일 · 발송 여부)
-- poca_update_202611.sql 을 실행한 데이터베이스에서 Supabase > SQL Editor에 붙여넣고 Run 하세요.
-- 여러 번 실행해도 괜찮습니다.

-- 명단에 이메일을 저장합니다. 응답 표(poca_responses)와는 연결하지 않습니다.
alter table public.poca_invites add column if not exists email text
  check (email is null or length(email) <= 120);

-- 안내 메일을 보냈는지 여부만 저장합니다 (시각은 남기지 않습니다).
alter table public.poca_invites add column if not exists mail_sent boolean not null default false;
