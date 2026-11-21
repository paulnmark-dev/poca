-- POCA 펄스 '한 가지만' · 문자 자동 발송 켜기
-- pulse_one_setup.sql 을 먼저 실행하세요.
--
-- [먼저 할 일 · 한 번만]
-- 1) 솔라피(solapi.com) 가입 → 발신번호 등록 → API Key / API Secret 발급
-- 2) 아래 세 줄의 '여기에...' 부분을 실제 값으로 바꿔 SQL Editor 에서 '그 세 줄만' 실행하세요.
--    (키는 Supabase 금고(Vault)에 암호화되어 저장됩니다. 키를 Claude나 다른 사람에게 보내지 마세요.)
--
--   select vault.create_secret('여기에_API_KEY',    'solapi_api_key');
--   select vault.create_secret('여기에_API_SECRET', 'solapi_api_secret');
--   select vault.create_secret('여기에_발신번호(숫자만)', 'solapi_from');
--
-- 3) 그다음 이 파일 전체를 실행하세요. (여러 번 실행해도 괜찮습니다)

create extension if not exists pg_net;
create extension if not exists pg_cron;

alter table public.pulse_outbox add column if not exists req_id bigint;

-- 대기열(outbox)의 문자를 솔라피로 보냄. 키가 아직 없으면 아무것도 하지 않고 0을 돌려줌.
create or replace function public.pulse_send()
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare k text; s text; f text; d text; salt text; sig text; msgs jsonb; ids bigint[]; rid bigint;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'solapi_api_key';
  select decrypted_secret into s from vault.decrypted_secrets where name = 'solapi_api_secret';
  select decrypted_secret into f from vault.decrypted_secrets where name = 'solapi_from';
  if k is null or s is null or f is null then return 0; end if;
  loop
    select array_agg(id), jsonb_agg(jsonb_build_object('to', phone, 'from', f, 'text', text, 'autoTypeDetect', true))
      into ids, msgs
      from (select id, phone, text from public.pulse_outbox where status = 'pending' order by id limit 100) x;
    exit when ids is null;
    d := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    salt := encode(gen_random_bytes(16), 'hex');
    sig := encode(hmac(d || salt, s, 'sha256'), 'hex');
    select net.http_post(
      url := 'https://api.solapi.com/messages/v4/send-many',
      body := jsonb_build_object('messages', msgs),
      headers := jsonb_build_object('Content-Type', 'application/json',
        'Authorization', 'HMAC-SHA256 apiKey=' || k || ', date=' || d || ', salt=' || salt || ', signature=' || sig)
    ) into rid;
    update public.pulse_outbox set status = 'sent', sent_at = now(), req_id = rid where id = any(ids);
  end loop;
  return (select count(*) from public.pulse_outbox where sent_at > now() - interval '1 minute');
end;
$$;
revoke execute on function public.pulse_send() from public, anon, authenticated;

-- 보낸 요청의 응답 확인: 솔라피가 거절한 묶음은 'failed'로 바꾸고 이유를 남김
create or replace function public.pulse_check_sends()
returns int
language plpgsql security definer set search_path = public, extensions
as $$
declare cnt int;
begin
  update public.pulse_outbox o set status = 'failed', error = left(coalesce(r.content::text, r.error_msg, 'error'), 300)
  from net._http_response r
  where o.req_id = r.id and o.status = 'sent' and (r.status_code is null or r.status_code >= 300);
  get diagnostics cnt = row_count;
  return cnt;
end;
$$;
revoke execute on function public.pulse_check_sends() from public, anon, authenticated;

-- '지금 첫 질문 보내기' 버튼이 바로 문자까지 보내도록
create or replace function public.pulse_start_now(p_code text)
returns int
language plpgsql security definer set search_path = public
as $$
declare made int;
begin
  if not public.poca_is_admin() then raise exception 'not admin'; end if;
  made := public.pulse_open(upper(trim(p_code)));
  perform public.pulse_send();
  return made;
end;
$$;
revoke execute on function public.pulse_start_now(text) from public, anon;
grant execute on function public.pulse_start_now(text) to authenticated;

-- 매주 일정 (한국 시간): 수요일 18:00 마감, 목요일 12:00 새 질문 + 문자 발송, 12:10 발송 결과 확인
select cron.unschedule(jobid) from cron.job where jobname in ('pulse-close','pulse-open','pulse-check');
select cron.schedule('pulse-close', '0 9 * * 3',  $$select public.pulse_close()$$);                    -- 수 18:00 KST
select cron.schedule('pulse-open',  '0 3 * * 4',  $$select public.pulse_open(); select public.pulse_send()$$); -- 목 12:00 KST
select cron.schedule('pulse-check', '10 3 * * 4', $$select public.pulse_check_sends()$$);              -- 목 12:10 KST
