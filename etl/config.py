"""Paths and source-file settings. Everything is relative to the project root,
so the same code runs locally and inside the Airflow Docker container."""
import os
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get("PHARMA_DWH_HOME", Path(__file__).resolve().parents[1]))
RAW_DIR = PROJECT_ROOT / "data" / "raw"
SQL_DIR = PROJECT_ROOT / "sql"
WAREHOUSE_DIR = PROJECT_ROOT / "warehouse"
EXPORT_DIR = PROJECT_ROOT / "exports"
DASHBOARD_DIR = PROJECT_ROOT / "dashboard"
DB_PATH = Path(os.environ.get("PHARMA_DWH_DB", WAREHOUSE_DIR / "pharma_sdi.duckdb"))

# source file stem -> (raw table name, expected row count from the dataset guide)
SOURCES = {
    "01_master_data": ("raw.master_data", 63),
    "02_manufacturing_data": ("raw.manufacturing_data", 561),
    "03_manufacturer_delivery_data": ("raw.manufacturer_delivery_data", 999),
    "04_warehouse_data": ("raw.warehouse_data", 112_184),
    "05_pharmacy_sales_data": ("raw.pharmacy_sales_data", 500_000),
    "06_hospital_demand_data": ("raw.hospital_demand_data", 27_216),
    "07_iot_streaming_data": ("raw.iot_streaming_data", 293_425),
}


def source_path(stem: str) -> Path:
    """Return the CSV for a source, accepting plain .csv or compressed .csv.gz."""
    for ext in (".csv", ".csv.gz"):
        p = RAW_DIR / f"{stem}{ext}"
        if p.exists():
            return p
    raise FileNotFoundError(f"Source file {stem}.csv(.gz) not found in {RAW_DIR}")
