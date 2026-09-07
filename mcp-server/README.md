# ReflexWhoop MCP server

Read-only MCP server over an exported ReflexWhoop snapshot, so Claude on your
Mac can query your own WHOOP data. Runs on the Mac, not the phone — this is
plain Python, not part of the iOS app.

## Setup

```bash
cd mcp-server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Export a snapshot from the app first: **Data tab -> Export data -> Share
export**, then save `reflexwhoop.sqlite` from that export to
`~/Documents/ReflexWhoop/reflexwhoop.sqlite` (the default path), or set
`REFLEXWHOOP_DB_PATH` to wherever you put it. Re-export and re-save whenever
you want Claude looking at fresher data — this server never touches the live
on-device database or a WAL directly.

## Register with Claude Code

```bash
claude mcp add reflexwhoop -- python3 /absolute/path/to/mcp-server/server.py
```

(Use the venv's `python3` if you didn't activate it globally — e.g.
`/absolute/path/to/mcp-server/.venv/bin/python3`.) Set `REFLEXWHOOP_DB_PATH`
in your shell profile first if you're not using the default path.

## What it can't do

Opens the database with SQLite's `mode=ro` URI flag — verified (see
`ExporterTests`-style manual check during development) that a raw write
attempt against that connection fails at the SQLite level with
`attempt to write a readonly database`, not just at the validation layer
below. `query()` additionally only allows a single `SELECT`/`WITH` statement,
rejects PRAGMA/DDL/write keywords, caps results at 500 rows, and aborts a
query that runs past 5 seconds.

## Tools

| Tool | Purpose |
|---|---|
| `schema()` | tables + columns, so Claude can write its own SQL |
| `query(sql)` | read-only SQL, single SELECT/WITH statement, row-capped |
| `daily_summary(start?, end?)` | joined recovery + sleep + strain + readiness per day |
| `trend(metric, start?, end?)` | rolling baseline series for one `daily_metrics` column |
| `correlations(min_n?)` | precomputed predictor -> next-day-recovery correlations |
| `workouts(sport?, start?, end?)` | sessions with zone durations |
| `hrv_session(session_id)` | per-BLE-session RR-derived HRV suite |

## Parquet conversion (optional)

```bash
python3 tools/to_parquet.py path/to/export_dir
```

Converts every CSV in an export folder to `export_dir/parquet/<table>.parquet`
using pandas + pyarrow. Runs on the Mac — there's no maintained pure-Swift
Parquet writer worth depending on for the app itself.
