"""Proves the SCD Type 2 logic of DimMedicine on a throw-away database.

The real dataset has one price version per medicine (all EffectiveFromDate = 2023-01-01),
so this test simulates a price change for MED001 on 2025-01-01 and checks that:
  * the old row is closed (EffectiveToDate = 2024-12-31, CurrentFlag = 'No')
  * a new current row is added with the new price and a NEW surrogate key
  * a Type 1 change (brand name) overwrites ALL versions, without a new row
  * re-running with no change adds nothing (idempotent)
Run:  python tests/test_scd2_dim_medicine.py
"""
import os
import sys
import tempfile
from pathlib import Path

tmp = Path(tempfile.mkdtemp()) / "scd2_test.duckdb"
os.environ["PHARMA_DWH_DB"] = str(tmp)
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from etl import db  # noqa: E402

db.run_sql_file("00_setup/00_create_schemas.sql")
db.load_raw_file("01_master_data")
db.run_sql_file("02_staging/stg_medicine.sql")
db.run_sql_file("03_dimensions/dim_medicine.sql")

con = db.connect()
n0 = con.execute("select count(*) from dwh.dim_medicine where MedicineKey <> -1").fetchone()[0]
assert n0 == 63, n0
old_key, old_price = con.execute(
    "select MedicineKey, RecommendedRetailPriceUSD from dwh.dim_medicine where MedicineID = 'MED001'").fetchone()

# --- simulate a new master extract: MED001 price rises from 2025-01-01, brand renamed (Type 1)
con.execute("""update stg.medicine
               set RecommendedRetailPriceUSD = RecommendedRetailPriceUSD + 1,
                   EffectiveFromDate = date '2025-01-01', FictionalBrandName = 'ClariMetform01-XR'
               where MedicineID = 'MED001'""")
con.close()
db.run_sql_file("03_dimensions/dim_medicine.sql")

con = db.connect()
rows = con.execute("""select MedicineKey, RecommendedRetailPriceUSD, EffectiveFromDate::varchar,
                             EffectiveToDate::varchar, CurrentFlag, FictionalBrandName
                      from dwh.dim_medicine where MedicineID = 'MED001' order by EffectiveFromDate""").fetchall()
for r in rows:
    print(r)
assert len(rows) == 2, "expected two versions of MED001"
(k1, p1, f1, t1, c1, b1), (k2, p2, f2, t2, c2, b2) = rows
assert k1 == old_key and p1 == old_price and t1 == "2024-12-31" and c1 == "No"
assert k2 != old_key and p2 == old_price + 1 and f2 == "2025-01-01" and t2 == "9999-12-31" and c2 == "Yes"
assert b1 == b2 == "ClariMetform01-XR", "Type 1 attribute must be overwritten on every version"
con.close()

# --- re-run with the same extract: nothing new
db.run_sql_file("03_dimensions/dim_medicine.sql")
con = db.connect()
assert con.execute("select count(*) from dwh.dim_medicine where MedicineKey <> -1").fetchone()[0] == 64
con.close()
print("SCD2 test PASSED: history kept, Type 1 overwritten, re-run idempotent")
