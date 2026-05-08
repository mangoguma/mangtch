# mock-kbo — local Naver Sports stand-in

KBO 비시즌이거나 라이브 경기가 없는 시간대에도 위젯을 테스트할 수 있게
`api-gw.sports.naver.com` 의 두 엔드포인트를 흉내내는 로컬 서버.

## How it works

`KBOService.swift` 는 `MANGTCH_KBO_MOCK_BASE` 환경변수가 잡혀 있으면 모든
요청을 그쪽으로 보낸다. 이 폴더의 Python 서버가 시나리오별 픽스처를 그대로
JSON 으로 돌려준다.

지원 엔드포인트:

| Path | Fixture |
|------|---------|
| `GET /schedule/games?fromDate=…&toDate=…` | `fixtures/schedule_<scenario>.json` |
| `GET /schedule/games/{gameId}/relay`      | `fixtures/relay_<scenario>.json` |

`gameDateTime` 의 날짜 부분은 요청의 `fromDate` 로 자동 치환되므로 시나리오를
어느 날 켜도 "오늘 경기" 로 보인다.

## Scenarios

- `live` — 7회초, 한화 4 : 3 롯데 (시간 기반 진행, 아래 참고)
- `scheduled` — 모든 경기 BEFORE
- `finished` — 모든 경기 RESULT (linescore 9이닝 풀 그리드)
- `cancelled` — 우천취소
- `mixed` — 5 경기를 한 화면에 모두 깔아주는 QA 종합 시나리오 (1 live + 2 finished + 1 scheduled + 1 cancelled). live 1게임만 LIVE_SCRIPT 로 진행하고 나머지는 고정 상태 — "모든 상태가 같이 나오는지" 와 "핀/패널 토글이 흐름 끊기지 않는지" 같은 체크리스트용

## Run

```bash
cd mangtch-new/scripts/mock-kbo
./run.sh live          # 기본
./run.sh scheduled
./run.sh finished
./run.sh cancelled
./run.sh mixed         # 5경기 동시 — QA 체크리스트용

# 환경변수
MOCK_PORT=9000 ./run.sh live           # 포트 변경
MOCK_TICK_SECONDS=3 ./run.sh live      # 빠른 진행 (live / mixed 전용)
```

다른 터미널 또는 launchctl 에서 환경변수를 잡고 앱 실행:

```bash
# 터미널에서 직접 실행할 때
export MANGTCH_KBO_MOCK_BASE=http://127.0.0.1:8765
open /Applications/Mangtch-new.app

# Finder/Dock 으로 띄울 때 (Finder 가 띄우는 프로세스에도 보이도록)
launchctl setenv MANGTCH_KBO_MOCK_BASE http://127.0.0.1:8765
pkill -9 -x boringNotch; sleep 0.3; open /Applications/Mangtch-new.app

# 끝나면
launchctl unsetenv MANGTCH_KBO_MOCK_BASE
pkill -f mock-kbo/server.py
```

## Live 시나리오 — 시간 기반 타임라인

`live` 는 정적 픽스처가 아니라 **서버 기동 시점부터 흐르는 한 이닝의 스토리**를
풀어낸다. `MOCK_TICK_SECONDS` (기본 10) 마다 `LIVE_SCRIPT` 의 다음 entry 가
relay 응답에 추가되고, `currentGameState` (count·bases·score) 도 동기화된다.
schedule 응답의 점수도 같이 갱신되므로 wing 압축 row 와 ticker·linescore 가
어긋나지 않는다.

기본 스크립트 (총 13 단계, 약 130초):

```
t= 10s  6구 파울
t= 20s  7구 볼넷                    → 만루
t= 30s  6번타자 박치국
t= 40s  1구 스트라이크
t= 50s  2구 볼
t= 60s  좌중간 깊은 2루타
t= 70s  전준우 홈인 (4:4)           → 동점
t= 80s  유강남 홈인 (5:4)           → 역전
t= 90s  투수 교체 — 한승혁
t=100s  7번타자 안치홍
t=110s  1구 볼
t=120s  2구 스트라이크
t=130s  유격수 정면 땅볼 아웃 (스리아웃)
```

처음부터 다시 보고 싶으면 서버를 재시작:

```bash
pkill -f mock-kbo/server.py
./run.sh live
```

## Customizing the live script

`server.py` 의 `LIVE_SCRIPT` 상수를 편집하면 시나리오를 통째로 갈 수 있다.
각 entry 는 `(textOption.type, 화면 텍스트, currentGameState 패치)` 튜플:

| 필드 | 의미 |
|------|------|
| `type` | Naver `textOption.type`. `1`=투구, `2`=교체, `8`=타자등장, `13`=타석 결과, `14`=주루, `24`=홈인. ticker 의 importance 분류에 쓰여서 TTS·우선순위가 갈린다. |
| `text` | ticker 와 play log 에 그대로 표시되는 한국어 문장 |
| 패치 dict | `ball`/`strike`/`out`/`base1`/`base2`/`base3`/`awayScore`/`homeScore`/`awayHit`/`awayBallFour`/`pitcher`/`batter` 중 바꿀 키만 string 으로. `None` 이면 상태는 그대로 두고 텍스트만 흘림. |

투수 교체 (`pitcher`) 가 새 pcode 를 도입하면 `apply_live_timeline` 이 자동으로
`homeLineup.pitcher` 에 splice 해서 LiveState pcode 룩업이 깨지지 않게 한다.
새 batter pcode 도 마찬가지로 `awayLineup.batter` 에 등록해야 하므로
`extras` 리스트에 같이 추가해주면 된다.

데모 페이스 빠르게 보고 싶으면 `MOCK_TICK_SECONDS=2 ./run.sh live`. ticker 가
queue 에 너무 빠르게 쌓이는지·우선순위 강등이 잘 먹는지 그런 부하 테스트도
이 노브로 본다.

## QA 체크리스트 — 시나리오 매핑

| 체크 항목 | 시나리오 | 어떻게 |
|-----------|----------|--------|
| Pin a KBO game → close panel → reopen → game still pinned | `mixed` | 5경기 중 임의 핀 → 패널 닫고 다시 열기. live 가 진행돼도 핀 유지되는지 |
| Watch a live game score change — should update within 10s | `live` 또는 `mixed` | 60s 시점에 2루타·홈인 2개 → 점수 4→5 변경 (TICK 짧게 잡고 보면 빠름) |
| BSO dots animate on count change | `live` | 각 tick 마다 ball/strike 변동 (10–60s 사이 풀카운트 흐름) |
| Base diamonds animate on runner movement | `live` | 20s 만루로 진입, 60s 2루타로 1·3루 잔류 |
| Play ticker scrolls once then stops | `live` | seqno 가 한번 들어왔다 정지하는지 — TICK=10 기본이면 10초마다 한 줄 |
| All 5 games show correct finished/live status | `mixed` | 5경기 동시 노출 — 각자 statusCode 가 row 에 정확히 매핑되는지 |
| Light theme: bases and BSO dots visible | `live` | 데이터-무관, 스타일만. 시스템 라이트 테마로 토글 후 wing/expanded 확인 |

## Capturing real responses

진짜 라이브 응답을 픽스처로 박제하고 싶으면:

```bash
# 오늘 경기 목록
curl -A 'Mozilla/5.0' \
  'https://api-gw.sports.naver.com/schedule/games?fields=basic,baseball&upperCategoryId=kbaseball&categoryId=kbo&fromDate=2026-05-09&toDate=2026-05-09' \
  | jq . > fixtures/schedule_live.json

# 해당 경기의 실시간 relay (gameId 는 위 응답에서)
curl -A 'Mozilla/5.0' \
  'https://api-gw.sports.naver.com/schedule/games/<GAMEID>/relay' \
  | jq . > fixtures/relay_live.json
```

캡처한 JSON 은 그대로 동작한다 — 서버가 날짜만 그날 기준으로 다시 쓴다.
단 `live` 의 시간 기반 진행은 fixture 위에 LIVE_SCRIPT 가 덧씌워지는 구조라,
캡처한 베이스라인이 다르면 스크립트의 cgs 패치가 충돌할 수 있다. 정적 캡처만
보고 싶으면 `LIVE_SCRIPT = []` 로 비워두면 된다.
