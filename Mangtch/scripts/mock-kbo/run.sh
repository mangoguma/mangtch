#!/usr/bin/env bash
# Spin up a local Naver Sports mock for KBO testing.
#
# Usage:
#   ./run.sh                    # default: scenario=live, port=8765
#   ./run.sh scheduled          # pre-game state
#   ./run.sh finished           # post-game results
#   ./run.sh cancelled          # rain-out
#   ./run.sh mixed              # 5 games covering all states (1 live + 2 finished + 1 scheduled + 1 cancelled)
#   MOCK_PORT=9000 ./run.sh live
#   MOCK_TICK_SECONDS=3 ./run.sh live   # speed up the live timeline
#
# Then in another terminal:
#   export MANGTCH_KBO_MOCK_BASE=http://127.0.0.1:8765
#   open /Applications/Mangtch.app   # or rebuild via build-app.sh after launchctl env
#
# Mangtch reads MANGTCH_KBO_MOCK_BASE at process start, so the env var
# must be visible to the launching shell. For Finder-launched apps use
# `launchctl setenv MANGTCH_KBO_MOCK_BASE http://127.0.0.1:8765` and
# relaunch the app from the dock/Finder.

set -euo pipefail

scenario="${1:-live}"
case "$scenario" in
  live|scheduled|finished|cancelled|mixed) ;;
  *)
    echo "unknown scenario: $scenario (live | scheduled | finished | cancelled | mixed)" >&2
    exit 1
    ;;
esac

cd "$(dirname "$0")"
export MOCK_SCENARIO="$scenario"
export MOCK_PORT="${MOCK_PORT:-8765}"
exec python3 server.py
