import re,sys
import os
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src=os.path.join(ROOT,'src','poca.html')
s=open(src,encoding='utf8').read()
def rep(a,b,n=1):
    global s
    c=s.count(a); assert c==n,(a[:90],c); s=s.replace(a,b)

s=s.replace('</style>','a{color:var(--muted)}\n</style>',1)
rep('<title>POCA 조직문화 진단 (테스트)</title>','<title>POCA 조직문화 진단 · Paul &amp; Mark</title>\n<meta name="robots" content="noindex">')
# load supabase before main script: insert before first <script> that holds app code
i=s.find('<script>'); assert i>0
s=s[:i]+'<script src="supabase.js"></script>\n'+s[i:]

# respondent intro: sample buttons only for admin; admin/login button
rep('<button id="smp">조직 리포트 예시 보기</button><button id="psmp">펄스 리포트 예시 보기</button><span id="adm"></span></div></div>`);',
    '${caps.canEdit?\'<button id="smp">조직 리포트 예시 보기</button><button id="psmp">펄스 리포트 예시 보기</button>\':\'\'}<span id="adm"></span></div><p class="small muted" style="margin-top:18px"><a href="#" id="privacy">개인정보 처리 안내</a> · ${caps.canEdit?\'<a href="#" id="logout">로그아웃</a>\':\'<a href="#" id="login">관리자 로그인</a>\'}</p></div>`);')
_i=s.find('function introView');_j=s.find('\nfunction ',_i+10)
_seg=s[_i:_j]
assert _seg.count("el.querySelector('#smp').onclick=()=>{st.R=aggregate(sampleData());")==1
_seg=_seg.replace("el.querySelector('#smp').onclick=()=>{st.R=aggregate(sampleData());","{const sm=el.querySelector('#smp');if(sm)sm.onclick=()=>{st.R=aggregate(sampleData());")
s=s[:_i]+_seg+s[_j:]
rep("el.querySelector('#psmp').onclick=()=>{st.P=samplePulse();st.src='sample';st.screen='pulse';render()};",
    "}{const ps=el.querySelector('#psmp');if(ps)ps.onclick=()=>{st.P=samplePulse();st.src='sample';st.screen='pulse';render()};}\n el.querySelector('#privacy').onclick=e=>{e.preventDefault();st.screen='privacy';render()};\n {const li=el.querySelector('#login');if(li)li.onclick=e=>{e.preventDefault();st.screen='login';render()};const lo=el.querySelector('#logout');if(lo)lo.onclick=async e=>{e.preventDefault();try{await sb.auth.signOut()}catch(_){}caps.canEdit=false;st.screen='intro';render()};}")
s=s.replace("}[st.screen];app.append(v())",",login:loginView,privacy:privacyView}[st.screen];app.append(v())",1)
assert ",login:loginView,privacy:privacyView}[st.screen]" in s
rep("st.orgErr='진단에 연결하지 못했습니다. 이 페이지에 참여 권한이 있는지 확인해 주세요.';","st.orgErr='진단에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.';")

# submit -> rpc
a=s.find("if(caps.db&&caps.user&&st.org){try{const id=await caps.user.id();")
b=s.find("else st.saved=false;",a)+len("else st.saved=false;")
assert a>0 and b>a
s=s[:a]+"if(sb&&st.org){try{const {data,error}=inviteTok?await sb.rpc('poca_submit_invite',{p_code:st.org.code,p_key:deviceKey(st.org.code),p_data:rec,p_token:inviteTok}):await sb.rpc('poca_submit',{p_code:st.org.code,p_key:deviceKey(st.org.code),p_data:rec});if(error||data!==true)throw error||new Error('closed');st.saved=true;if(st.invite)st.invite.done=true}catch(e){st.saved=false}}else st.saved=false;"+s[b:]
rep("'이 화면에서는 응답이 저장되지 않았습니다. 결과는 아래에서 확인할 수 있습니다. (저장하려면 이 페이지에 참여자 이상 권한이 필요합니다)'",
    "'응답을 저장하지 못했습니다. 인터넷 연결을 확인한 뒤 같은 기기에서 다시 제출해 주세요. 진단이 마감된 경우에도 저장되지 않습니다.'")

# code entry: Enter key + loading message
rep("const en=el.querySelector('#enter'); if(en)en.onclick=()=>{const c=el.querySelector('#code').value.trim().toUpperCase();if(c)loadOrg(c,true)};",
    "const en=el.querySelector('#enter'); if(en){const sub=()=>{const c0=el.querySelector('#code').value.replace(/\\s/g,'');const c2=koToEn(c0).toUpperCase();const c=c2;const ce=el.querySelector('#cerr');if(!c){ce.textContent='진단 코드를 적어 주세요.';return}ce.textContent='확인하는 중…';en.disabled=true;loadOrg(c,true).finally(()=>{en.disabled=false})};en.onclick=sub;el.querySelector('#code').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();sub()}}};")

# admin list: share link
rep('<p class="small muted" style="margin:2px 0 0">응답 ${o.n}명',
    '<p class="small" style="margin:2px 0 0">링크: <code>${esc(location.origin+location.pathname+\'#\'+o.code)}</code></p><p class="small muted" style="margin:2px 0 0">응답 ${o.n}명')

# boot replacement
a=s.find("(async()=>{\n if(!window.claude||!window.claude.use)return;")
b=s.find("})();",a)+len("})();")
assert a>0 and b>a
boot=r"""
const SB_URL='https://ummnwptnjgxhcwmfunqu.supabase.co';
const SB_KEY='sb_publishable_EhRvKl9x1_6leAHFxDJOlA_ocJ17o75';
let sb=null;
function deviceKey(code){const k='poca_key_'+code;try{let v=localStorage.getItem(k);if(!v){v=crypto.randomUUID();localStorage.setItem(k,v)}return v}catch(e){return crypto.randomUUID()}}
function makeDb(){return {
 doc(path){const [col,id]=path.split('/');return {
  async get(){if(col!=='poca_orgs')throw new Error('unsupported');
   if(caps.canEdit){const {data,error}=await sb.from('poca_orgs').select('info').eq('code',id).maybeSingle();if(error)throw error;return {data:()=>data?data.info:null}}
   const {data,error}=await sb.rpc('poca_get_org',{p_code:id});if(error)throw error;return {data:()=>data||null}},
  async set(obj){const {error}=await sb.from('poca_orgs').upsert({code:id,info:obj});if(error)throw error},
  async update(patch){const {data,error}=await sb.from('poca_orgs').select('info').eq('code',id).single();if(error)throw error;const {error:e2}=await sb.from('poca_orgs').update({info:{...data.info,...patch}}).eq('code',id);if(e2)throw e2}
 }},
 collection(col){const q={limit(){return q},async get(){
  if(col==='poca_orgs'){const {data,error}=await sb.from('poca_orgs').select('code,info').limit(1000);if(error)throw error;return {docs:data.map(r=>({id:r.code,data:()=>r.info}))}}
  if(col==='poca_resp'){let all=[],from=0;for(;;){const {data,error}=await sb.from('poca_responses').select('org_code,data').range(from,from+999);if(error)throw error;all=all.concat(data);if(data.length<1000)break;from+=1000}return {docs:all.map(r=>({data:()=>({[r.org_code]:r.data})}))}}
  throw new Error('unsupported')}};return q}
}}
caps.downloads={save:async({filename,data})=>{const b=new Blob([data],{type:filename.endsWith('.csv')?'text/csv;charset=utf-8':'text/html;charset=utf-8'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=filename;document.body.append(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},1500)}};
async function checkAdmin(){try{const {data:{session}}=await sb.auth.getSession();if(!session){caps.canEdit=false;return false}const {data,error}=await sb.rpc('poca_is_admin');caps.canEdit=!error&&data===true;return caps.canEdit}catch(e){caps.canEdit=false;return false}}
function loginView(){
 const el=$(`<div class="panel" style="max-width:460px;margin:40px auto"><p class="label">폴앤마크 관리자</p><h2>로그인</h2>
  <label class="small" for="em">이메일</label><input type="email" id="em" autocomplete="username" style="font:inherit;width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:4px;background:var(--surface);color:var(--ink)">
  <div style="height:10px"></div><label class="small" for="pw">비밀번호</label><input type="password" id="pw" autocomplete="current-password" style="font:inherit;width:100%;padding:10px 12px;border:1px solid var(--line);border-radius:4px;background:var(--surface);color:var(--ink)">
  <p class="err" id="lerr"></p><div class="row"><button class="primary" id="li">로그인</button><button id="back">처음으로</button></div></div>`);
 const go=async()=>{const em=el.querySelector('#em').value.trim(),pw=el.querySelector('#pw').value;const er=el.querySelector('#lerr');if(!em||!pw){er.textContent='이메일과 비밀번호를 적어 주세요.';return}
  er.textContent='확인하는 중…';const {error}=await sb.auth.signInWithPassword({email:em,password:pw});if(error){er.textContent='로그인하지 못했습니다. 이메일과 비밀번호를 확인해 주세요.';return}
  if(await checkAdmin()){openAdmin()}else{await sb.auth.signOut();er.textContent='관리자로 등록된 이메일이 아닙니다.'}};
 el.querySelector('#li').onclick=go;el.querySelector('#pw').onkeydown=e=>{if(e.key==='Enter')go()};
 el.querySelector('#back').onclick=()=>{st.screen='intro';render()};
 return el;
}
function privacyView(){
 const el=$(`<div class="panel" style="max-width:760px;margin:24px auto"><p class="label">개인정보 처리 안내</p><h2>POCA 조직문화 진단은 이렇게 응답을 다룹니다</h2>
  <p><b>받는 것</b> · 부서 · 직급 · 근속 구간, 문항 응답, 열린 질문의 답. 시범 운영일 때는 응답에 걸린 시간과 문항 의견도 받습니다. 이름 · 이메일 · 사번 · 연락처는 응답과 함께 받지 않습니다.</p>
  <p><b>개인 링크로 진행할 때</b> · 회사가 개인 링크 방식을 고른 경우, 회사가 준 이름(과 부서)을 명단에 보관하고 ‘완료 여부’만 표시합니다. 명단과 응답은 서로 다른 곳에 저장되고 둘을 잇는 기록을 남기지 않습니다. 그래서 누가 무엇이라고 답했는지는 회사도 폴앤마크도 알 수 없습니다.</p>
  <p><b>쓰는 곳</b> · 회사 단위의 조직문화 진단 리포트를 만드는 데만 씁니다. 개인별 응답은 회사에 넘기지 않습니다.</p>
  <p><b>보이는 방식</b> · 결과는 묶어서만 보입니다. 응답이 ${MIN_N}명 미만인 부서 · 직급 · 근속 그룹은 리포트에 나오지 않습니다. 열린 질문의 답은 누가 썼는지 알 수 없게 다룹니다.</p>
  <p><b>참여</b> · 참여는 자유입니다. 참여하지 않거나 중간에 그만두어도 불이익이 없습니다.</p>
  <p><b>다시 고치기</b> · 같은 기기에서는 진단이 마감되기 전까지 자기 응답을 다시 낼 수 있습니다. 이를 위해 기기에 무작위 번호를 남기며, 이 번호는 사람과 연결되지 않습니다.</p>
  <p><b>보관과 파기</b> · 응답과 명단은 폴앤마크가 이용하는 클라우드 데이터베이스(Supabase)에 저장되며, 진단을 의뢰한 회사와 정한 기간이 지나면 지웁니다.</p>
  <p><b>문의</b> · 폴앤마크 (Paul &amp; Mark Co., Ltd.)</p>
  <div class="row"><button id="back">처음으로</button></div></div>`);
 el.querySelector('#back').onclick=()=>{st.screen='intro';render()};return el;
}
(async()=>{
 try{if(!window.supabase)throw new Error('no sdk');sb=window.supabase.createClient(SB_URL,SB_KEY,{auth:{persistSession:true,autoRefreshToken:true}});caps.db=makeDb();caps.user={};}catch(e){sb=null;caps.db=null}
 if(sb){await checkAdmin();caps.ext={
  async getInvite(tok){const {data,error}=await sb.rpc('poca_get_invite',{p_token:tok});if(error)throw error;return data||null},
  async hrStatus(code,tok){const {data,error}=await sb.rpc('poca_hr_status',{p_code:code,p_token:tok});if(error)throw error;return data||null},
  async hrResponses(code,tok){const {data,error}=await sb.rpc('poca_hr_responses',{p_code:code,p_token:tok});if(error)throw error;return data||[]},
  async addInvites(code,rows){const {error}=await sb.from('poca_invites').insert(rows.map(r=>({org_code:code,name:r.name,dept:r.dept||null})));if(error)throw error},
  async listInvites(code){const {data,error}=await sb.from('poca_invites').select('token,name,dept,done').eq('org_code',code).order('name');if(error)throw error;return data||[]},
  async pulseGet(tok){const {data,error}=await sb.rpc('pulse_get',{p_token:tok});if(error)throw error;return data||null},
  async pulseSubmit(tok,score,team,note){const {data,error}=await sb.rpc('pulse_submit',{p_token:tok,p_key:deviceKey('one_'+tok),p_score:score,p_team:team,p_note:note||null});if(error)throw error;return data===true},
  async pulseHr(code,tok){const {data,error}=await sb.rpc('pulse_hr',{p_code:code,p_hr:tok});if(error)throw error;return data||null},
  async pulseApprove(code,tok,week){const {data,error}=await sb.rpc('pulse_hr_approve',{p_code:code,p_hr:tok,p_week:week});if(error)throw error;return data===true},
  async listPrograms(){const {data,error}=await sb.from('pulse_programs').select('code,info,created_at').order('created_at',{ascending:false});if(error)throw error;
   const [{data:mm},{data:ww}]=await Promise.all([sb.from('pulse_members').select('program_code').eq('active',true),sb.from('pulse_weeks').select('program_code')]);
   return data.map(p=>({...p,members:(mm||[]).filter(x=>x.program_code===p.code).length,weeks:(ww||[]).filter(x=>x.program_code===p.code).length}))},
  async createProgram(code,info){const {error}=await sb.from('pulse_programs').insert({code,info});if(error)throw error},
  async setProgram(code,info){const {error}=await sb.from('pulse_programs').update({info}).eq('code',code);if(error)throw error},
  async addMembers(code,rows){const {error}=await sb.from('pulse_members').insert(rows.map(r=>({program_code:code,name:r.name,dept:r.dept||null,phone:r.phone||null})));if(error)throw error},
  async startNow(code){const {data,error}=await sb.rpc('pulse_start_now',{p_code:code});if(error)throw error;return data}
 }}
 await route();
 if(st.screen==='intro')render();
 window.addEventListener('hashchange',()=>{route()});
})();"""
s=s[:a]+boot+s[b:]
assert s.count("st.orgErr='이 코드의 진단을 찾지 못했습니다.'")==1
s=s.replace("st.orgErr='이 코드의 진단을 찾지 못했습니다.'","st.orgErr='‘'+code+'’ 코드의 진단을 찾지 못했습니다. 코드를 다시 확인해 주세요.'")
KO=r'''function koToEn(s){const M={'ㄱ':'r','ㄲ':'R','ㄴ':'s','ㄷ':'e','ㄸ':'E','ㄹ':'f','ㅁ':'a','ㅂ':'q','ㅃ':'Q','ㅅ':'t','ㅆ':'T','ㅇ':'d','ㅈ':'w','ㅉ':'W','ㅊ':'c','ㅋ':'z','ㅌ':'x','ㅍ':'v','ㅎ':'g','ㅏ':'k','ㅐ':'o','ㅑ':'i','ㅒ':'O','ㅓ':'j','ㅔ':'p','ㅕ':'u','ㅖ':'P','ㅗ':'h','ㅘ':'hk','ㅙ':'ho','ㅚ':'hl','ㅛ':'y','ㅜ':'n','ㅝ':'nj','ㅞ':'np','ㅟ':'nl','ㅠ':'b','ㅡ':'m','ㅢ':'ml','ㅣ':'l','ㄳ':'rt','ㄵ':'sw','ㄶ':'sg','ㄺ':'fr','ㄻ':'fa','ㄼ':'fq','ㄽ':'ft','ㄾ':'fx','ㄿ':'fv','ㅀ':'fg','ㅄ':'qt'};const L='ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ',V='ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ',T=['','ㄱ','ㄲ','ㄳ','ㄴ','ㄵ','ㄶ','ㄷ','ㄹ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅁ','ㅂ','ㅄ','ㅅ','ㅆ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];let o='';for(const ch of s){const c=ch.charCodeAt(0);if(c>=0xAC00&&c<=0xD7A3){const i=c-0xAC00;o+=M[L[Math.floor(i/588)]]+M[V[Math.floor(i%588/28)]]+(i%28?M[T[i%28]]:'')}else o+=M[ch]||ch}return o}'''
assert s.count('<script src="supabase.js"></script>')==1
s=s.replace('<script src="supabase.js"></script>','<script src="supabase.js"></script>\n<script>'+KO+'</script>',1)
open(os.path.join(ROOT,'site','index.html'),'w',encoding='utf8').write(s)
print('ok',len(s))
