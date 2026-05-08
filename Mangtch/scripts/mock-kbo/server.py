#!/usr/bin/env python3
"""Local mock of api-gw.sports.naver.com for KBO testing.

Run via run.sh — picks a scenario fixture and serves it on PORT.
Mangtch's KBOService picks this up via MANGTCH_KBO_MOCK_BASE.

Endpoints mirrored:
  GET /schedule/games?fromDate=YYYY-MM-DD&toDate=...   → schedule_<scenario>.json
  GET /schedule/games/{id}/relay                       → relay_<scenario>.json

Date rewrite: the schedule fixture's gameDateTime is patched to fromDate
so the in-app "today" filter (Asia/Seoul) keeps matching regardless of
when you run the mock.

Live timeline: the `live` scenario unfolds a scripted half-inning over
time. Every MOCK_TICK_SECONDS (default 10) a new play is appended to
the relay's textOptions and currentGameState (count/bases/score) is
patched accordingly. Both schedule and relay endpoints stay in sync so
the wing widget, expanded panel, and ticker all see the same live game.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

FIXTURES = Path(__file__).resolve().parent / "fixtures"
SCENARIO = os.environ.get("MOCK_SCENARIO", "live")
PORT = int(os.environ.get("MOCK_PORT", "8765"))
LIVE_TICK = int(os.environ.get("MOCK_TICK_SECONDS", "10"))
LIVE_START = time.monotonic()

# Scripted continuation of the live fixture. Starts from 7회초 1·2루 풀카운트
# 2아웃 4:3. Each entry runs LIVE_TICK seconds after the previous one.
# Tuple: (textOption.type per Naver taxonomy, text, currentGameState patch).
LIVE_SCRIPT: list[tuple[int, str, dict[str, str] | None]] = [
    (1,  "6구 파울 (1루측)",                              None),
    (1,  "7구 볼넷",                                     {"ball": "0", "strike": "0", "base1": "1", "base2": "1", "base3": "1", "awayBallFour": "3"}),
    (8,  "6번타자 박치국",                               {"batter": "B_LT_06"}),
    (1,  "1구 스트라이크",                               {"strike": "1"}),
    (1,  "2구 볼",                                       {"ball": "1"}),
    (13, "박치국 : 좌중간 깊은 2루타",                    {"base1": "0", "base2": "1", "base3": "1", "awayHit": "8"}),
    (24, "전준우 홈인 (4:4)",                            {"awayScore": "4"}),
    (24, "유강남 홈인 (5:4)",                            {"awayScore": "5"}),
    (2,  "투수 교체 — 한승혁 등판",                      {"pitcher": "P_HH_02"}),
    (8,  "7번타자 안치홍",                               {"ball": "0", "strike": "0", "batter": "B_LT_07"}),
    (1,  "1구 볼",                                       {"ball": "1"}),
    (1,  "2구 스트라이크",                               {"strike": "1"}),
    (13, "안치홍 : 유격수 정면 땅볼 아웃 (스리아웃)",      {"out": "3", "base1": "0", "base2": "0", "base3": "0"}),
]


def load_fixture(name: str) -> dict:
    path = FIXTURES / f"{name}_{SCENARIO}.json"
    if not path.exists():
        raise FileNotFoundError(f"missing fixture {path.name}")
    return json.loads(path.read_text())


def patch_date(payload: dict, date_str: str) -> dict:
    for game in payload.get("result", {}).get("games", []):
        original = game.get("gameDateTime", "")
        # gameDateTime is "YYYY-MM-DDTHH:MM:SS"; replace the date half only
        if "T" in original:
            game["gameDateTime"] = f"{date_str}T{original.split('T', 1)[1]}"
        else:
            game["gameDateTime"] = f"{date_str}T18:30:00"
    return payload


def live_progress() -> tuple[dict[str, str], list[dict]]:
    """How far the scripted timeline has advanced since startup.
    Returns (cgs_overlay, plays_to_inject).
    """
    elapsed = time.monotonic() - LIVE_START
    steps = max(0, min(int(elapsed // LIVE_TICK), len(LIVE_SCRIPT)))
    overlay: dict[str, str] = {}
    plays: list[dict] = []
    for i in range(steps):
        type_, text, patch = LIVE_SCRIPT[i]
        # Seqnos start above the fixture's max (714) and stride by 10 so
        # new entries are unambiguously ordered after the baseline plays.
        plays.append({"seqno": 800 + i * 10, "type": type_, "text": text})
        if patch:
            overlay.update(patch)
    return overlay, plays


def apply_live_timeline(payload: dict) -> dict:
    if SCENARIO != "live":
        return payload
    overlay, plays = live_progress()
    trd = payload.setdefault("result", {}).setdefault("textRelayData", {})
    cgs = trd.setdefault("currentGameState", {})
    cgs.update(overlay)

    relays = trd.setdefault("textRelays", [])
    block = next(
        (r for r in relays if r.get("inn") == 7 and r.get("homeOrAway") == "0"),
        None,
    )
    if block is None:
        block = {"inn": 7, "homeOrAway": "0", "textOptions": []}
        relays.append(block)
    options = block.setdefault("textOptions", [])
    existing_seqnos = {opt.get("seqno") for opt in options}
    for p in plays:
        if p["seqno"] not in existing_seqnos:
            options.append(p)

    # When the relief pitcher takes the mound, splice them into the home
    # lineup so the LiveState pcode lookup resolves their name instead of
    # going nil mid-inning.
    if cgs.get("pitcher") == "P_HH_02":
        home_pitchers = (
            trd.setdefault("homeLineup", {}).setdefault("pitcher", [])
        )
        if not any(p.get("pcode") == "P_HH_02" for p in home_pitchers):
            home_pitchers.append({"pcode": "P_HH_02", "name": "한승혁"})

    # Likewise the away lineup needs the new batters as the script
    # cycles through 6번/7번 타자 introductions.
    away_batters = trd.setdefault("awayLineup", {}).setdefault("batter", [])
    extras = [
        ("B_LT_06", "박치국", 6),
        ("B_LT_07", "안치홍", 7),
    ]
    for pcode, name, order in extras:
        if not any(b.get("pcode") == pcode for b in away_batters):
            away_batters.append({"pcode": pcode, "name": name, "batOrder": order})

    return payload


def apply_live_schedule(payload: dict) -> dict:
    """Bump the live game's score in schedule responses so the collapsed
    row matches the relay's currentGameState."""
    if SCENARIO != "live":
        return payload
    overlay, _ = live_progress()
    games = payload.get("result", {}).get("games", [])
    if not games:
        return payload
    g = games[0]
    for src, dst in (("awayScore", "awayTeamScore"), ("homeScore", "homeTeamScore")):
        if src in overlay:
            try:
                g[dst] = int(overlay[src])
            except ValueError:
                pass
    return payload


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002,N802
        sys.stderr.write(f"[mock-kbo {SCENARIO}] {self.address_string()} - {format % args}\n")

    def _send(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/schedule/games":
            from_date = (query.get("fromDate") or [""])[0]
            try:
                payload = patch_date(load_fixture("schedule"), from_date)
                payload = apply_live_schedule(payload)
            except FileNotFoundError as e:
                self._send(500, {"error": str(e)})
                return
            self._send(200, payload)
            return

        match = re.fullmatch(r"/schedule/games/([^/]+)/relay", path)
        if match:
            try:
                payload = apply_live_timeline(load_fixture("relay"))
            except FileNotFoundError as e:
                self._send(500, {"error": str(e)})
                return
            self._send(200, payload)
            return

        self._send(404, {"error": f"no mock route for {path}"})


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write(
        f"[mock-kbo] scenario={SCENARIO} listening on http://127.0.0.1:{PORT}\n"
    )
    if SCENARIO == "live":
        sys.stderr.write(
            f"[mock-kbo] live timeline: {len(LIVE_SCRIPT)} plays @ {LIVE_TICK}s each "
            f"(~{len(LIVE_SCRIPT) * LIVE_TICK}s total)\n"
        )
    sys.stderr.write(
        f"[mock-kbo] launchctl setenv MANGTCH_KBO_MOCK_BASE http://127.0.0.1:{PORT}\n"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\n[mock-kbo] shutting down\n")
        server.server_close()


if __name__ == "__main__":
    main()
