// POCA 관리자 Edge Function
// - invite / update: 매니저 초대, 이름·비밀번호 수정
// - mail_preview: 참여 안내 메일 미리보기 (실제 발송 없음)
// - mail_send: 아직 안 보낸 명단에 참여 안내 메일 발송 (한 번에 최대 40명)
// 호출자는 로그인한 관리자여야 합니다 (poca_is_admin). service_role 키는 이 함수 안에서만 씁니다.
import { createClient } from 'npm:@supabase/supabase-js@2';

const ALLOWED_ORIGINS = [
  'https://poca.paulnmark.com',
  'https://cheery-muffin-5e69ec.netlify.app',
];
const ADMIN_URL = 'https://poca.paulnmark.com/admin';
const PAGE_URL = 'https://poca.paulnmark.com/';
const MAIL_BATCH = 40;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') ?? '';
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));

// 안내 메일 내용. 미리보기와 실제 발송이 같은 함수를 씁니다.
function buildMail(orgName: string, name: string, token: string) {
  const link = `${PAGE_URL}#i/${token}`;
  const subject = `[폴앤마크] ${orgName} 조직문화 진단 참여 안내`;
  const text = [
    `안녕하세요, ${name}님.`,
    `${orgName}에서 조직문화 진단 POCA에 참여를 요청드립니다.`,
    '',
    '· 약 11분, 80문항입니다.',
    '· 이름은 받지 않으며, 결과는 묶어서만 보입니다.',
    '· 참여는 자유이며, 중간에 그만두셔도 불이익이 없습니다.',
    '· 같은 기기에서는 마감 전까지 다시 응답할 수 있습니다.',
    '',
    '아래 링크에서 시작해 주세요. 본인만 쓰는 개인 링크입니다.',
    link,
    '',
    '문의: info@paulnmark.com',
    '폴앤마크 (Paul & Mark)',
  ].join('\n');
  const html = `<div style="font-family:'Apple SD Gothic Neo','Malgun Gothic',sans-serif;font-size:15px;line-height:1.7;color:#111">
  <p>안녕하세요, ${esc(name)}님.</p>
  <p>${esc(orgName)}에서 조직문화 진단 POCA에 참여를 요청드립니다.</p>
  <ul><li>약 11분, 80문항입니다.</li><li>이름은 받지 않으며, 결과는 묶어서만 보입니다.</li><li>참여는 자유이며, 중간에 그만두셔도 불이익이 없습니다.</li><li>같은 기기에서는 마감 전까지 다시 응답할 수 있습니다.</li></ul>
  <p><a href="${link}" style="display:inline-block;padding:12px 20px;background:#c61c2c;color:#fff;text-decoration:none;border-radius:6px;font-weight:700">진단 시작하기</a></p>
  <p style="font-size:13px;color:#6B7280">버튼이 안 열리면 이 주소를 붙여넣으세요: ${link}</p>
  <p style="font-size:13px;color:#6B7280">문의: info@paulnmark.com<br>폴앤마크 (Paul &amp; Mark)</p></div>`;
  return { subject, text, html, link };
}

Deno.serve(async (req) => {
  const headers = { ...corsHeaders(req), 'Content-Type': 'application/json' };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청입니다.' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1) 호출자가 관리자인지 확인 (호출자 토큰으로)
  const caller = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: isAdmin, error: adminErr } = await caller.rpc('poca_is_admin');
  if (adminErr || isAdmin !== true) return json({ error: '관리자만 사용할 수 있습니다.' }, 403);

  // 2) 관리 작업은 service_role로
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const body = await req.json().catch(() => null);
  if (!body || typeof body !== 'object') return json({ error: '잘못된 요청입니다.' }, 400);

  // ---- 메일 발송 ----
  if (body.action === 'mail_preview' || body.action === 'mail_send') {
    const code = String(body.code ?? '').trim().toUpperCase();
    if (!/^[A-Z0-9]{4,8}$/.test(code)) return json({ error: '진단 코드가 올바르지 않습니다.' }, 400);
    const { data: org, error: orgErr } = await admin.from('poca_orgs').select('info').eq('code', code).maybeSingle();
    if (orgErr || !org) return json({ error: '진단을 찾지 못했습니다.' }, 404);
    const orgName = String(org.info?.name ?? code);

    if (body.action === 'mail_preview') {
      const sample = buildMail(orgName, '홍길동', '00000000-0000-0000-0000-000000000000');
      return json({ subject: sample.subject, text: sample.text, html: sample.html });
    }

    const apiKey = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('POCA_MAIL_FROM') ?? 'POCA <info@paulnmark.com>';
    if (!apiKey) return json({ error: '메일 발송 키가 설정되어 있지 않습니다. 관리자에게 문의해 주세요.' }, 500);

    const { data: pending, error: pendErr } = await admin
      .from('poca_invites')
      .select('token,name,email')
      .eq('org_code', code)
      .eq('mail_sent', false)
      .not('email', 'is', null)
      .limit(MAIL_BATCH);
    if (pendErr) return json({ error: '명단을 불러오지 못했습니다.' }, 500);

    let sent = 0;
    const failed: string[] = [];
    for (const row of pending ?? []) {
      const mail = buildMail(orgName, row.name, row.token);
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ from, to: [row.email], subject: mail.subject, text: mail.text, html: mail.html }),
      });
      if (res.ok) {
        const { error: markErr } = await admin.from('poca_invites').update({ mail_sent: true, mail_failed: false }).eq('token', row.token);
        if (markErr) failed.push(row.token); else sent++;
      } else {
        failed.push(row.token);
        await admin.from('poca_invites').update({ mail_failed: true }).eq('token', row.token);
      }
      // Resend 요청 속도 제한을 넘지 않도록 잠깐 쉽니다.
      await new Promise((r) => setTimeout(r, 600));
    }

    const { count } = await admin
      .from('poca_invites')
      .select('token', { count: 'exact', head: true })
      .eq('org_code', code)
      .eq('mail_sent', false)
      .not('email', 'is', null);
    return json({ sent, failed: failed.length, remaining: Math.max(0, (count ?? 0) - sent) });
  }

  // ---- 매니저 관리 ----
  const name = String(body.name ?? '').trim().slice(0, 40);
  const email = String(body.email ?? '').trim().toLowerCase();
  if (!EMAIL_RE.test(email)) return json({ error: '이메일 형식을 확인해 주세요.' }, 400);
  if (!name) return json({ error: '이름을 적어 주세요.' }, 400);

  const dept = String(body.dept ?? '').trim().slice(0, 40) || null;

  if (body.action === 'invite') {
    const { error: inviteErr } = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: ADMIN_URL,
      data: { name },
    });
    if (inviteErr) return json({ error: '초대 메일을 보내지 못했습니다: ' + inviteErr.message }, 400);
    const { error: saveErr } = await admin.from('poca_admins').upsert({ email, name, dept }, { onConflict: 'email' });
    if (saveErr) return json({ error: '관리자 명단에 저장하지 못했습니다.' }, 500);
    return json({ ok: true });
  }

  if (body.action === 'update') {
    const { error: nameErr } = await admin.from('poca_admins').update({ name, dept }).eq('email', email);
    if (nameErr) return json({ error: '이름을 저장하지 못했습니다.' }, 500);

    if (body.password) {
      const password = String(body.password);
      if (password.length < 8) return json({ error: '비밀번호는 8자 이상이어야 합니다.' }, 400);
      const { data: list, error: listErr } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
      if (listErr) return json({ error: '계정을 확인하지 못했습니다.' }, 500);
      const user = list.users.find((u) => (u.email ?? '').toLowerCase() === email);
      if (!user) return json({ error: '아직 가입하지 않은 계정입니다. 초대 메일을 먼저 수락해 주세요.' }, 400);
      const { error: pwErr } = await admin.auth.admin.updateUserById(user.id, { password });
      if (pwErr) return json({ error: '비밀번호를 바꾸지 못했습니다: ' + pwErr.message }, 400);
    }
    return json({ ok: true });
  }

  return json({ error: '알 수 없는 요청입니다.' }, 400);
});
