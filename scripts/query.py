"""Run any SQL against the warehouse (read-only). Handy for the demo video.

  python scripts/query.py "select * from mart.q1_sales_trend where Year = 2025 limit 10"
  python scripts/query.py q1        # shortcuts: q1, q2, q3, kpi, whatif, ci, dq
"""
import sys
from pathlib import Path

import duckdb

DB = Path(__file__).resolve().parents[1] / "warehouse" / "pharma_sdi.duckdb"
SHORTCUTS = {
    "q1": "select * from mart.q1_sales_trend where Year = 2025 order by NetSalesUSD desc limit 15",
    "q2": "select * from mart.q2_demand_vs_sales order by abs(ForecastErrorPacks) desc limit 15",
    "q3": "select * from mart.q3_unmet_vs_stockouts order by UnmetPacks desc limit 15",
    "kpi": "select * from mart.kpi_monthly",
    "whatif": "select * from mart.what_if_base",
    "ci": "select * from mart.kpi_confidence_intervals",
    "dq": "select check_name, severity, failed_rows, status from audit.dq_results "
          "where run_id = (select run_id from audit.dq_results order by checked_at desc limit 1)",
}

sql = SHORTCUTS.get(sys.argv[1], sys.argv[1]) if len(sys.argv) > 1 else SHORTCUTS["kpi"]
con = duckdb.connect(str(DB), read_only=True)
con.sql(sql).show(max_width=250, max_rows=60)
