# ReflexWhoop MCP server

A read-only [MCP](https://modelcontextprotocol.io) server over an exported ReflexWhoop
snapshot, so Claude on your Mac can query your own data. Plain Python on the Mac; it
never touches the phone or the live database.

## Setup

Requires Python 3.10+.

```bash
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

In the app, **Archive → Export a copy → Share**, and save the export's
`reflexwhoop.sqlite` to `~/Documents/ReflexWhoop/reflexwhoop.sqlite`, or anywhere with
`REFLEXWHOOP_DB_PATH` pointing at it. Export again whenever you want fresher data.

Register it with Claude Code, using absolute paths:

```bash
claude mcp add reflexwhoop -- /absolute/path/to/mcp-server/.venv/bin/python3 /absolute/path/to/mcp-server/server.py
```

Add `-e REFLEXWHOOP_DB_PATH=/path/to/reflexwhoop.sqlite` before `--` if the snapshot
isn't at the default path.

## Tools

| Tool | Returns |
|---|---|
| `schema()` | tables and columns, so Claude can write its own SQL |
| `query(sql)` | one read-only `SELECT`/`WITH` statement, up to 500 rows |
| `daily_summary(start?, end?)` | recovery, sleep, strain and readiness per day |
| `trend(metric, start?, end?)` | one metric's 30- and 60-day baselines per day: mean, SD, z-score |
| `correlations(min_n?)` | predictor → next-day recovery: rho, n, corrected p, strength |
| `workouts(sport?, start?, end?)` | workouts with zone durations |
| `ble_sessions()` | band recordings, newest first, with decode coverage and `signal_quality` |
| `ble_heart_rate(session_id)` | one recording's per-minute heart rate |
| `hrv_session(session_id)` | one recording's derived metrics; the RR-based HRV columns are `NULL` until an RR channel is decoded |

Caveats the tools also state: `sleep_debt_milli` is WHOOP's capped debt term, not debt
owed, and `readiness_score` is built on it
([why](../docs/DECISIONS.md#readiness-hidden-until-sleep-debt-is-rebuilt));
correlations on one person's data are suggestive, not causal.

## Read-only, twice over

The database is opened with SQLite's `mode=ro` URI flag, so a write fails at the SQLite
level ("attempt to write a readonly database") whatever the code does. On top of that,
`query()` accepts a single `SELECT` or `WITH`, rejects write, DDL and `PRAGMA`
keywords, caps rows at 500 and aborts after 5 seconds.

## Parquet

```bash
.venv/bin/python3 tools/to_parquet.py /path/to/export-folder
```

Writes `parquet/<table>.parquet` for every CSV in an export, with pandas and pyarrow.
It runs on the Mac because there's no maintained pure-Swift Parquet writer worth
depending on.
