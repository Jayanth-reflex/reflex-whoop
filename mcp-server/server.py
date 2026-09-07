#!/usr/bin/env python3
"""Read-only MCP server over a ReflexWhoop export snapshot.

Points at the `reflexwhoop.sqlite` produced by the app's Export button
(Data tab -> Export data -> Share export), pulled to this Mac via
AirDrop/Files/Finder. Deliberately does **not** read the live on-device
database directly — that one has WAL sidecar files this server doesn't
manage, and a personal MCP server has no business touching your live data
anyway. Point it at a snapshot; re-export and re-point when you want fresh
data.

Opens the database in SQLite's `mode=ro` URI mode, so nothing this process
does can write to your history even if a bug tried to — the OS enforces
that, not just the code below. `query()` additionally allowlists to
SELECT/WITH statements, rejects anything with a second statement or a
DDL/write keyword, caps rows returned, and aborts a query that runs too
long.
"""
from __future__ import annotations

import os
import re
import sqlite3
import time
from pathlib import Path
from typing import Any

from mcp.server.mcpserver import MCPServer

DB_PATH = Path(
    os.environ.get("REFLEXWHOOP_DB_PATH", "~/Documents/ReflexWhoop/reflexwhoop.sqlite")
).expanduser()
ROW_CAP = 500
QUERY_TIMEOUT_SECONDS = 5

mcp = MCPServer("reflexwhoop")

_DISALLOWED = re.compile(
    r"\b(insert|update|delete|drop|alter|attach|detach|vacuum|pragma|create|replace|reindex)\b",
    re.IGNORECASE,
)


def _connect() -> sqlite3.Connection:
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"No database at {DB_PATH}. In the app: Data tab -> Export data -> "
            f"Share export, save reflexwhoop.sqlite to this path (or set "
            f"REFLEXWHOOP_DB_PATH to wherever you put it)."
        )
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=QUERY_TIMEOUT_SECONDS)
    conn.row_factory = sqlite3.Row
    deadline = time.monotonic() + QUERY_TIMEOUT_SECONDS
    conn.set_progress_handler(lambda: 0 if time.monotonic() < deadline else 1, 1000)
    return conn


def _validate_select(sql: str) -> None:
    stripped = sql.strip().rstrip(";")
    if ";" in stripped:
        raise ValueError("Only a single statement is allowed (no semicolons).")
    if not re.match(r"(?is)^\s*(select|with)\b", stripped):
        raise ValueError("Only SELECT (or WITH ... SELECT) statements are allowed.")
    if _DISALLOWED.search(stripped):
        raise ValueError("Statement contains a disallowed keyword.")


def _rows(cursor: sqlite3.Cursor, limit: int = ROW_CAP) -> list[dict[str, Any]]:
    return [dict(row) for row in cursor.fetchmany(limit)]


@mcp.tool()
def schema() -> dict[str, list[dict[str, str]]]:
    """Tables and their columns, so you can write your own SQL for `query`."""
    conn = _connect()
    try:
        tables = [
            r["name"]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            )
        ]
        return {
            table: [{"name": c["name"], "type": c["type"]} for c in conn.execute(f"PRAGMA table_info({table})")]
            for table in tables
        }
    finally:
        conn.close()


@mcp.tool()
def query(sql: str) -> list[dict[str, Any]]:
    """Read-only SQL against the export snapshot. SELECT/WITH only, capped at
    500 rows, single statement, no PRAGMA/DDL/write keywords."""
    _validate_select(sql)
    conn = _connect()
    try:
        return _rows(conn.execute(sql))
    finally:
        conn.close()


@mcp.tool()
def daily_summary(start: str | None = None, end: str | None = None) -> list[dict[str, Any]]:
    """Joined recovery + sleep + strain + readiness per day. `start`/`end` are
    inclusive ISO dates ('2026-01-01'); omit either for an open range."""
    conn = _connect()
    try:
        cursor = conn.execute(
            """
            SELECT day, recovery_score, hrv_rmssd_milli, resting_heart_rate,
                   respiratory_rate, day_strain, sleep_performance_percentage,
                   sleep_debt_milli, readiness_score, confidence, user_calibrating
            FROM daily_metrics
            WHERE (:start IS NULL OR day >= :start) AND (:end IS NULL OR day <= :end)
            ORDER BY day
            """,
            {"start": start, "end": end},
        )
        return _rows(cursor, limit=2000)
    finally:
        conn.close()


@mcp.tool()
def trend(metric: str, start: str | None = None, end: str | None = None) -> list[dict[str, Any]]:
    """Rolling baseline series (mean/stddev/z-score, 30- and 60-day windows)
    for one metric column of daily_metrics, e.g. 'hrv_rmssd_milli'."""
    conn = _connect()
    try:
        cursor = conn.execute(
            """
            SELECT day, window_days, mean_val, stddev_val, z_score
            FROM baselines
            WHERE metric = :metric
              AND (:start IS NULL OR day >= :start) AND (:end IS NULL OR day <= :end)
            ORDER BY day, window_days
            """,
            {"metric": metric, "start": start, "end": end},
        )
        return _rows(cursor, limit=2000)
    finally:
        conn.close()


@mcp.tool()
def correlations(min_n: int = 0) -> list[dict[str, Any]]:
    """Precomputed predictor -> next-day-recovery correlations (Spearman rho,
    sample size, Benjamini-Hochberg-corrected p-value, strength band). This is
    one person's data — suggestive, not causal; see docs/design.md."""
    conn = _connect()
    try:
        cursor = conn.execute(
            """
            SELECT predictor, outcome, lag_days, rho, n, p_value, p_value_bh_corrected, strength
            FROM correlations
            WHERE n >= :min_n
            ORDER BY ABS(rho) DESC
            """,
            {"min_n": min_n},
        )
        return _rows(cursor)
    finally:
        conn.close()


@mcp.tool()
def workouts(sport: str | None = None, start: str | None = None, end: str | None = None) -> list[dict[str, Any]]:
    """Workout sessions with zone durations. `start`/`end` are epoch seconds
    compared against the workout's start; omit either for an open range."""
    conn = _connect()
    try:
        cursor = conn.execute(
            """
            SELECT w.id, w.start, w.end, w.sport_name, w.strain, w.average_heart_rate,
                   w.max_heart_rate, w.kilojoule, w.distance_meter,
                   z.zone_zero_milli, z.zone_one_milli, z.zone_two_milli,
                   z.zone_three_milli, z.zone_four_milli, z.zone_five_milli
            FROM workouts w
            LEFT JOIN workout_zone_durations z ON z.workout_id = w.id
            WHERE (:sport IS NULL OR w.sport_name = :sport)
              AND (:start IS NULL OR w.start >= :start) AND (:end IS NULL OR w.start <= :end)
            ORDER BY w.start DESC
            """,
            {"sport": sport, "start": start, "end": end},
        )
        return _rows(cursor, limit=1000)
    finally:
        conn.close()


@mcp.tool()
def hrv_session(session_id: str) -> dict[str, Any] | None:
    """Per-BLE-session RR-derived HRV suite (rMSSD, SDNN, pNN50, DFA-alpha1)
    plus session metadata, if that session has been analyzed."""
    conn = _connect()
    try:
        row = conn.execute(
            """
            SELECT s.id, s.started_at, s.ended_at, s.mode, s.channels_json,
                   m.rmssd_milli, m.sdnn_milli, m.pnn50_pct, m.dfa_alpha1,
                   m.rr_artifact_rejection_pct, m.respiratory_rate, m.signal_quality
            FROM ble_sessions s
            LEFT JOIN session_metrics m ON m.session_id = s.id
            WHERE s.id = ?
            """,
            (session_id,),
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


if __name__ == "__main__":
    mcp.run()
