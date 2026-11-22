"""
Milestone 1 - Sales & Demand Intelligence (SDI) data mart
==========================================================
raw CSV (7 OLTP extracts)  ->  staging (clean + typed)  ->  DQ checks
   ->  dimensions (10, persistent surrogate keys, SCD1/SCD2)  ->  facts (3)
   ->  DQ reconciliation  ->  query layer (mart views + bootstrap CIs)
   ->  optional oversampling (sandbox)  ->  export CSV/JSON for the dashboard

Warehouse engine: DuckDB file at warehouse/pharma_sdi.duckdb
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.models.param import Param
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import BranchPythonOperator, PythonOperator
from airflow.utils.task_group import TaskGroup

# make the project's etl package importable (dags/ sits next to etl/)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from etl import config, db, export  # noqa: E402

DOC = __doc__


def _sql(rel_path, log_tables=None, params_from_dag=None):
    """params_from_dag maps a {{placeholder}} in the SQL file to a DAG param name."""
    def run(**ctx):
        params = {ph: ctx["params"][p] for ph, p in (params_from_dag or {}).items()}
        return db.run_sql_file(rel_path, run_id=ctx["run_id"], params=params, log_tables=log_tables)
    return run


def _check_sources(**ctx):
    missing = [s for s in config.SOURCES if not any(
        (config.RAW_DIR / f"{s}{e}").exists() for e in (".csv", ".csv.gz"))]
    if missing:
        raise FileNotFoundError(f"Missing source files in data/raw: {missing}")
    return {s: config.source_path(s).name for s in config.SOURCES}


def _load_raw(stem):
    def run(**ctx):
        return db.load_raw_file(stem, run_id=ctx["run_id"])
    return run


def _checks(rel_path):
    def run(**ctx):
        return db.run_checks(rel_path, run_id=ctx["run_id"])
    return run


def _choose_oversampling(**ctx):
    factor = float(ctx["params"]["oversample_factor"])
    return "query_layer.oversample_sales" if factor > 1 else "query_layer.skip_oversampling"


def _export(**ctx):
    return export.export_query_layer(run_id=ctx["run_id"])


default_args = {
    "owner": "sdi-data-mart",
    "retries": 1,
    "retry_delay": timedelta(minutes=1),
}

with DAG(
    dag_id="pharma_sdi_data_mart",
    description="Milestone 1: Sales & Demand Intelligence data mart (raw -> star schema -> query layer)",
    doc_md=DOC,
    start_date=datetime(2025, 1, 1),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    max_active_tasks=1,          # DuckDB allows one writer at a time
    default_args=default_args,
    tags=["milestone-1", "dwh", "duckdb", "sales-demand"],
    params={
        "oversample_factor": Param(1.0, type="number", minimum=1, maximum=10,
                                   description="1 = off. >1 writes a bootstrap-oversampled copy of the "
                                               "sales fact to the sandbox schema (real facts untouched)."),
        "bootstrap_replicates": Param(200, type="integer", minimum=20, maximum=1000,
                                      description="Resamples used for the 95% confidence intervals."),
        "seed": Param(0.42, type="number", minimum=0, maximum=1,
                      description="Random seed for reproducible resampling."),
    },
) as dag:

    start = EmptyOperator(task_id="start")
    setup = PythonOperator(task_id="create_schemas_and_macros",
                           python_callable=_sql("00_setup/00_create_schemas.sql"))

    # ------------------------------------------------------------------ EXTRACT
    with TaskGroup("extract_raw", tooltip="Copy the 7 OLTP CSV extracts into the raw schema") as extract:
        check = PythonOperator(task_id="check_source_files", python_callable=_check_sources)
        prev = check
        for stem in config.SOURCES:
            t = PythonOperator(task_id=f"load_{stem}", python_callable=_load_raw(stem))
            prev >> t
            prev = t

    # ------------------------------------------------------------------ STAGING
    with TaskGroup("staging", tooltip="Clean, standardise and type (Transform.OLTP sheet)") as staging:
        s_med = PythonOperator(task_id="stg_medicine", python_callable=_sql(
            "02_staging/stg_medicine.sql", ["stg.medicine"]))
        s_sup = PythonOperator(task_id="stg_supply", python_callable=_sql(
            "02_staging/stg_supply.sql", ["stg.batch", "stg.warehouse_location", "stg.inventory_snapshot"]))
        s_sd = PythonOperator(task_id="stg_sales_and_demand", python_callable=_sql(
            "02_staging/stg_sales_demand.sql", ["stg.pharmacy_sale", "stg.hospital_demand"]))
        dq_stg = PythonOperator(task_id="dq_checks_staging", python_callable=_checks("06_quality/dq_staging.sql"))
        [s_med, s_sup, s_sd] >> dq_stg

    # ------------------------------------------------------------------ DIMENSIONS
    with TaskGroup("dimensions", tooltip="10 dimensions, persistent surrogate keys") as dims:
        d_date = PythonOperator(task_id="dim_date", python_callable=_sql(
            "03_dimensions/dim_date.sql", ["dwh.dim_date"]))
        d_loc = PythonOperator(task_id="dim_location", python_callable=_sql(
            "03_dimensions/dim_location.sql", ["dwh.dim_location"]))
        d_med = PythonOperator(task_id="dim_medicine_scd2", python_callable=_sql(
            "03_dimensions/dim_medicine.sql", ["dwh.dim_medicine"]))
        d_sup = PythonOperator(task_id="dim_batch_lot_warehouse", python_callable=_sql(
            "03_dimensions/dim_supply.sql", ["dwh.dim_batch", "dwh.dim_lot", "dwh.dim_warehouse"]))
        d_cus = PythonOperator(task_id="dim_pharmacy_hospital", python_callable=_sql(
            "03_dimensions/dim_customer.sql", ["dwh.dim_pharmacy", "dwh.dim_hospital"]))
        d_junk = PythonOperator(task_id="dim_channel_demand_status_junk", python_callable=_sql(
            "03_dimensions/dim_junk.sql", ["dwh.dim_channel", "dwh.dim_demand_status"]))
        d_loc >> [d_sup, d_cus]

    # ------------------------------------------------------------------ FACTS
    with TaskGroup("facts", tooltip="3 fact tables, full reload per run") as facts:
        f_sales = PythonOperator(task_id="fact_pharmacy_sales", python_callable=_sql(
            "04_facts/fact_pharmacy_sales.sql", ["dwh.fact_pharmacy_sales"]))
        f_dem = PythonOperator(task_id="fact_hospital_demand", python_callable=_sql(
            "04_facts/fact_hospital_demand.sql", ["dwh.fact_hospital_demand"]))
        f_inv = PythonOperator(task_id="fact_inventory_snapshot", python_callable=_sql(
            "04_facts/fact_inventory_snapshot.sql", ["dwh.fact_inventory_snapshot"]))
        dq_dwh = PythonOperator(task_id="dq_checks_star_schema", python_callable=_checks("06_quality/dq_warehouse.sql"))
        [f_sales, f_dem, f_inv] >> dq_dwh

    # ------------------------------------------------------------------ QUERY LAYER
    with TaskGroup("query_layer", tooltip="mart views, bootstrap CIs, optional oversampling, exports") as ql:
        views = PythonOperator(task_id="create_mart_views", python_callable=_sql(
            "05_query_layer/query_layer_views.sql"))
        boot = PythonOperator(task_id="bootstrap_kpi_confidence_intervals", python_callable=_sql(
            "07_oversampling/bootstrap_confidence.sql", ["mart.kpi_confidence_intervals"],
            params_from_dag={"replicates": "bootstrap_replicates", "seed": "seed"}))
        branch = BranchPythonOperator(task_id="oversampling_enabled", python_callable=_choose_oversampling)
        over = PythonOperator(task_id="oversample_sales", python_callable=_sql(
            "07_oversampling/oversample_sales.sql", ["sandbox.fact_pharmacy_sales_oversampled"],
            params_from_dag={"factor": "oversample_factor", "seed": "seed"}))
        skip = EmptyOperator(task_id="skip_oversampling")
        exp = PythonOperator(task_id="export_query_layer", python_callable=_export,
                             trigger_rule="none_failed_min_one_success")
        views >> boot >> branch >> [over, skip] >> exp

    end = EmptyOperator(task_id="end")

    start >> setup >> extract >> staging >> dims >> facts >> ql >> end
