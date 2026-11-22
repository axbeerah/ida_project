"""Export the query layer: every mart view -> exports/<view>.csv, plus one compact
dashboard/data.json used by the web dashboard (the 'running demo')."""
import json
import logging
from datetime import date, datetime
from decimal import Decimal

from etl import config
from etl.db import connect

log = logging.getLogger(__name__)

MART_OBJECTS = ["q1_sales_trend", "q2_demand_vs_sales", "q3_unmet_vs_stockouts",
                "kpi_monthly", "what_if_base", "kpi_confidence_intervals"]


def _rows(con, sql):
    cur = con.execute(sql)
    cols = [d[0] for d in cur.description]
    out = []
    for r in cur.fetchall():
        out.append({c: (float(v) if isinstance(v, Decimal) else
                        v.isoformat() if isinstance(v, (date, datetime)) else v)
                    for c, v in zip(cols, r)})
    return out


def export_query_layer(run_id: str = "manual") -> dict:
    config.EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    config.DASHBOARD_DIR.mkdir(parents=True, exist_ok=True)
    con = connect()
    counts = {}
    try:
        existing = {r[0] for r in con.execute(
            "select table_name from information_schema.tables where table_schema = 'mart'").fetchall()}
        for obj in MART_OBJECTS:
            if obj not in existing:
                continue
            out = config.EXPORT_DIR / f"{obj}.csv"
            con.execute(f"copy (select * from mart.{obj}) to '{out.as_posix()}' (header, delimiter ',')")
            counts[obj] = con.execute(f"select count(*) from mart.{obj}").fetchone()[0]
            log.info("exported mart.%s -> %s (%s rows)", obj, out.name, counts[obj])

        data = {
            "generated_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
            "run_id": run_id,
            "kpi_monthly": _rows(con, "select * from mart.kpi_monthly"),
            "q1_by_channel_month": _rows(con, """
                select YearMonth, ChannelGroup, sum(PacksSold) PacksSold, round(sum(NetSalesUSD),2) NetSalesUSD
                from mart.q1_sales_trend group by all order by 1, 2"""),
            "q1_by_disease_year": _rows(con, """
                select Year, DiseaseCategory, ChannelGroup, sum(PacksSold) PacksSold,
                       round(sum(NetSalesUSD),2) NetSalesUSD, round(sum(GrossMarginUSD),2) GrossMarginUSD
                from mart.q1_sales_trend group by all order by 1, 2, 3"""),
            "q1_by_state_year": _rows(con, """
                select Year, State, sum(PacksSold) PacksSold, round(sum(NetSalesUSD),2) NetSalesUSD
                from mart.q1_sales_trend group by all order by 1, 4 desc"""),
            "q2_hospital_summary": _rows(con, """
                select HospitalName, HospitalType, sum(ForecastPacks) ForecastPacks, sum(ConsumedPacks) ConsumedPacks,
                       sum(HospitalPharmacySoldPacks) SoldPacks, sum(UnfulfilledPacks) UnfulfilledPacks,
                       round(100*(1 - sum(abs(ForecastErrorPacks))*1.0/nullif(sum(ConsumedPacks),0)),2) ForecastAccuracyPct,
                       round(sum(HospitalPharmacySoldPacks)*1.0/nullif(sum(ConsumedPacks),0),3) SalesToConsumptionRatio
                from mart.q2_demand_vs_sales group by all order by 1"""),
            "q2_biggest_gaps": _rows(con, """
                select YearMonth, HospitalName, GenericName, DiseaseCategory, ForecastPacks, ConsumedPacks,
                       HospitalPharmacySoldPacks, ForecastErrorPacks, AbsPctError
                from mart.q2_demand_vs_sales where ConsumedPacks >= 50
                order by abs(ForecastErrorPacks) desc limit 15"""),
            "q2_disease_month": _rows(con, """
                select YearMonth, DiseaseCategory, sum(ForecastPacks) ForecastPacks, sum(ConsumedPacks) ConsumedPacks,
                       sum(HospitalPharmacySoldPacks) SoldPacks
                from mart.q2_demand_vs_sales group by all order by 1, 2"""),
            "q3_unmet": _rows(con, "select * from mart.q3_unmet_vs_stockouts order by UnmetPacks desc limit 40"),
            "q3_signal_summary": _rows(con, """
                select SupplySideSignal, count(*) Cases, sum(UnmetPacks) UnmetPacks
                from mart.q3_unmet_vs_stockouts group by 1 order by 3 desc"""),
            "what_if_base": _rows(con, "select * from mart.what_if_base"),
            "confidence": _rows(con, "select * from mart.kpi_confidence_intervals") if "kpi_confidence_intervals" in existing else [],
            "table_counts": _rows(con, " union all ".join(
                f"select 'dwh.{t}' as TableName, count(*) as Rows from dwh.{t}" for t in [
                    "dim_date", "dim_location", "dim_medicine", "dim_pharmacy", "dim_hospital",
                    "dim_warehouse", "dim_lot", "dim_batch", "dim_channel", "dim_demand_status",
                    "fact_pharmacy_sales", "fact_hospital_demand", "fact_inventory_snapshot"])),
            "dq_latest": _rows(con, """
                select check_file, check_name, severity, failed_rows, status from audit.dq_results
                where run_id = (select run_id from audit.dq_results order by checked_at desc limit 1)
                order by check_file, check_name"""),
        }
    finally:
        con.close()
    payload = json.dumps(data, default=str, separators=(",", ":"))
    (config.DASHBOARD_DIR / "data.json").write_text(payload)
    # self-contained demo page: the template with this run's data embedded
    template = (config.DASHBOARD_DIR / "template.html").read_text()
    html = template.replace("/*__DASHBOARD_DATA__*/null", payload.replace("</", "<\\/"))
    (config.DASHBOARD_DIR / "index.html").write_text(html)
    log.info("wrote dashboard/data.json and dashboard/index.html")
    return counts
