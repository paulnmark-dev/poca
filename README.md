# POCA · 폴앤마크 조직문화 진단

폴앤마크(Paul & Mark)의 조직문화 진단 POCA와 Next Culture 워크숍 도구입니다.

## 폴더 구성

| 폴더 | 내용 |
|---|---|
| `site/` | POCA 진단 웹사이트 (Netlify에 올리는 폴더). 로그인 없이 응답, 관리자만 결과 확인 |
| `wfg-site/` | Next Culture · WFG 팀 대화 워크숍 웹사이트 (별도 Netlify 프로젝트) |
| `src/` | 원본. `poca.html`(진단·결과보고서), `wfg.html`(WFG), `lovak-board.html`, `lti-dialogue.html` |
| `tools/` | 원본을 웹사이트로 바꾸는 스크립트 |
| `sql/` | Supabase 설정 SQL (`poca_setup.sql` → `poca_update_202611.sql` → `pulse_one_setup.sql` → `pulse_one_schedule.sql`, WFG는 `wfg_setup.sql`) |
| `samples/` | 예시 결과보고서 PDF (한국어 · 영어, 전체판 · 요약판) |

## 고치는 순서

1. `src/poca.html` 또는 `src/wfg.html`을 고칩니다.
2. 웹사이트 파일을 다시 만듭니다.
   ```
   python3 tools/build_poca.py   # → site/index.html
   python3 tools/build_wfg.py    # → wfg-site/index.html
   ```
3. 커밋하고 올리면 Netlify가 자동으로 새 판을 배포합니다.

## Netlify 설정

- POCA: 저장소 연결, Publish directory `site` (`netlify.toml`에 들어 있음)
- WFG: 같은 저장소로 프로젝트를 하나 더 만들고, Publish directory를 `wfg-site`로 지정

## 보안

- 웹사이트 안의 Supabase 주소와 publishable 키는 공개용입니다. 데이터는 관리자 로그인과 RLS 접근 규칙이 보호합니다.
- Supabase의 secret 키, service_role 키, 데이터베이스 비밀번호, 관리자 비밀번호는 **절대 이 저장소에 넣지 않습니다.**
- 응답자 이름은 받지 않으며, 3명 미만 집단은 결과에 표시하지 않습니다.

## 펄스 ‘바꿔보자! 한 가지만!’

- 매주 **목요일 12:00** 문자로 질문 하나 (나의 행동을 돌아보는 질문, POCA 네 문화 관계·질서·성과·혁신 = 4MAT Why·What·How·If와 연결, ‘가장 바라는 문화’부터)
- **수요일 18:00** 마감 → 인사팀 화면(`#ph/코드/토큰`)에서 확인·**승인** → 다음 문자에 우리 평균과 지난주 대비 변화가 실림
- 평균 **7점 이상**이거나 같은 질문 **3주**면 다음 질문으로
- 응답자 링크 `#p/개인토큰` · 명단(이름·전화번호)과 응답은 연결하지 않음
- 설정: `sql/pulse_one_setup.sql` 실행 → 솔라피 키를 Vault에 저장 → `sql/pulse_one_schedule.sql` 실행
- 발송 통로는 `pulse_outbox` 표에 모였다가 나갑니다. 나중에 사내 메신저·그룹웨어로 바꿀 때는 `pulse_send()`만 바꾸면 됩니다.
