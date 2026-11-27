-- 안내 메일 발송 시각 기록
-- 실행 순서: poca_admin_pages.sql 이후 한 번 실행. Supabase SQL Editor에 붙여넣고 Run.
alter table public.poca_invites add column if not exists mail_sent_at timestamptz;
