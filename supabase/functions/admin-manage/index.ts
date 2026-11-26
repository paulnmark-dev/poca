// POCA 관리자 관리 Edge Function
// - invite: 이메일로 초대 메일 발송 + 관리자 명단(poca_admins)에 이름 저장
// - update: 이름 수정, 비밀번호 변경 (8자 이상)
// 호출자는 로그인한 관리자여야 합니다 (poca_is_admin). service_role 키는 함수 안에서만 씁니다.
import { createClient } from 'npm:@supabase/supabase-js@2';

const ALLOWED_ORIGINS = [
  'https://poca.paulnmark.com',
  'https://cheery-muffin-5e69ec.netlify.app',
];
const SITE_URL = 'https://poca.paulnmark.com/admin';

function corsHeaders(req: Request) {
  const origin = req.headers.get('Origin') ?? '';
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
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

  const email = String(body.email ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: '이메일 형식을 확인해 주세요.' }, 400);
  const name = String(body.name ?? '').trim().slice(0, 40);
  if (!name) return json({ error: '이름을 적어 주세요.' }, 400);

  if (body.action === 'invite') {
    const { error: inviteErr } = await admin.auth.admin.inviteUserByEmail(email, {
      redirectTo: SITE_URL,
      data: { name },
    });
    if (inviteErr) return json({ error: '초대 메일을 보내지 못했습니다: ' + inviteErr.message }, 400);
    const { error: saveErr } = await admin.from('poca_admins').upsert({ email, name }, { onConflict: 'email' });
    if (saveErr) return json({ error: '관리자 명단에 저장하지 못했습니다.' }, 500);
    return json({ ok: true });
  }

  if (body.action === 'update') {
    const { error: nameErr } = await admin.from('poca_admins').update({ name }).eq('email', email);
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
