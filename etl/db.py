"""Small runner around DuckDB used by every Airflow task.

- run_sql_file: executes one .sql file (statements separated by ';') and logs row counts
- load_raw_file: copies one CSV into the raw schema as text (no type guessing, keeps leading zeros)
- run_checks: runs a data-quality SQL file and fails the task if an 'error' check fails
"""
import json
import logging
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

import duckdb

from etl import config

log = logging.getLogger(__name__)


def connect() -> duckdb.DuckDBPyConnection:
    config.WAREHOUSE_DIR.mkdir(parents=True, exist_ok=True)
    return duckdb.connect(str(config.DB_PATH))


def _split(sql: str) -> list[str]:
    # strip line comments, then split on ';' at line ends (our SQL files never use ';' inside strings)
    sql = re.sub(r"--[^\n]*", "", sql)
    return [s.strip() for s in re.split(r";\s*\n|;\s*$", sql) if s.strip()]


def _log_load(con, run_id: str, table: str) -> int:
    n = con.execute(f"select count(*) from {table}").fetchone()[0]
    con.execute(
        "insert into audit.load_log values (?, ?, ?, ?)",
        [run_id, table, n, datetime.now(timezone.utc).replace(tzinfo=None)],
    )
    log.info("%s -> %s rows", table, f"{n:,}")
    return n


def run_sql_file(rel_path: str, run_id: str = "manual", params: dict | None = None,
                 log_tables: list[str] | None = None) -> dict:
    path = config.SQL_DIR / rel_path
    sql = path.read_text()
    for k, v in (params or {}).items():
        sql = sql.replace("{{" + k + "}}", str(v))
    con = connect()
    try:
        for stmt in _split(sql):
            con.execute(stmt)
        counts = {t: _log_load(con, run_id, t) for t in (log_tables or [])}
    finally:
        con.close()
    log.info("ran %s", rel_path)
    return counts


def load_raw_file(stem: str, run_id: str = "manual") -> int:
    table, expected = config.SOURCES[stem]
    src = config.source_path(stem)
    con = connect()
    try:
        con.execute(
            f"create or replace table {table} as "
            f"select *, '{src.name}' as _source_file, now()::timestamp as _loaded_at "
            f"from read_csv('{src.as_posix()}', header=true, all_varchar=true)"
        )
        n = _log_load(con, run_id, table)
    finally:
        con.close()
    if n != expected:
        log.warning("%s: %s rows loaded, dataset guide says %s", table, n, expected)
    return n


def run_checks(rel_path: str, run_id: str = "manual") -> list[dict]:
    """Each check query returns (check_name, severity, failed_rows). Results are stored in
    audit.dq_results; any failed 'error' check stops the pipeline."""
    path = config.SQL_DIR / rel_path
    con = connect()
    results = []
    try:
        for stmt in _split(path.read_text()):
            name, severity, failed = con.execute(stmt).fetchone()
            status = "PASS" if failed == 0 else ("FAIL" if severity == "error" else "WARN")
            con.execute(
                "insert into audit.dq_results values (?, ?, ?, ?, ?, ?, ?)",
                [run_id, Path(rel_path).name, name, severity, failed, status,
                 datetime.now(timezone.utc).replace(tzinfo=None)],
            )
            results.append({"check": name, "severity": severity, "failed_rows": failed, "status": status})
            log.info("[%s] %-60s failed_rows=%s", status, name, failed)
    finally:
        con.close()
    failures = [r for r in results if r["status"] == "FAIL"]
    if failures:
        raise ValueError(f"Data quality errors: {json.dumps(failures, indent=1)}")
    return results


def new_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6]
