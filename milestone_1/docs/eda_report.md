# EDA report — source data profiling

Run on the full dataset before the design was finalised. The raw query output is in [`eda_raw_output.txt`](eda_raw_output.txt),
and the same findings are in the `EDA.Findings` sheet of the workbook. Each finding that matters is enforced as a
data-quality check in `sql/06_quality/`.

## Volumes

| File | Rows | Grain | Period |
|---|---|---|---|
| 01_master_data | 63 | medicine SKU | prices effective 2023-01-01 |
| 02_manufacturing_data | 561 | production batch | 2023–2025 |
| 03_manufacturer_delivery_data | 999 | shipment line (897 shipments) | 2023–2025 |
| 04_warehouse_data | 112,184 | warehouse lot × day | 2023-01-23 → 2025-12-31 |
| 05_pharmacy_sales_data | 500,000 | sales transaction | 2023-01-30 → 2025-12-31 |
| 06_hospital_demand_data | 27,216 | hospital × medicine × month | 2023-01 → 2025-12 |
| 07_iot_streaming_data | 293,425 | sensor reading | not used in Milestone 1 |

## Data quality

- **No duplicate keys** in any grain (SalesTransactionID, InventorySnapshotID, hospital × medicine × month).
- **Referential integrity is complete.** Every MedicineID, WarehouseLotID and ProductionBatchID in sales exists in the
  master, warehouse and manufacturing files. Each of the 12 hospital pharmacies maps to exactly one hospital.
- **No spelling or case problems** in categorical columns. The staging rules (trim, case, null defaults) still run, to protect future loads.
- **Expected nulls only:** HospitalID on retail and e-commerce sales (390,808 rows), PrescriptionID on OTC sales (37,316),
  DockToStockHours except on receipt days, and the warehouse/shipment fields in IoT depending on the asset type.
- **Formulas that hold on 100 % of rows** (used as DQ rules):
  - Gross = Quantity × Unit price; Net = Gross − Discount; Margin = Net − COGS (tax excluded)
  - Warehouse: Closing = Opening + Received − Shipped + TransferIn − TransferOut − Damaged − Expired + Adjustment
  - Hospital: Closing = Opening + Received − Dispensed − Wastage
  - Lot expiry date (04) = batch expiry date (02); DaysToExpiryAtSale = BatchExpiryDate − SalesDate
- **Assumptions in the first design that did not hold, now corrected:**
  - `UnfulfilledDemandPacks = Requested − Received` is false on 27,123 rows. It measures unmet patient demand and is non-zero on only 83 rows.
  - `Dispensed = Consumed` holds on only 92 rows, so both are kept.
  - `SalesChannel` has 2 values, not 3. Hospital pharmacies are identified through `PharmacyType`.
  - `CatchmentPopulation` is constant per hospital, so it is a dimension attribute.
  - Encounters and disease cases vary by medicine, so they stay as row-level non-additive measures.

## Business observations

- Pharmacy sales show strong winter peaks (Dec 2023 – Jan 2024 and especially Jan 2025, $1.18M in one month).
- Hospitals consume about 1.9M packs a year, warehouses ship about 3.0M packs a year, and pharmacy sales are about 0.2M packs a year.
  Stock and cover KPIs must therefore use warehouse outflow, not pharmacy sales.
- Gross margin is very stable at about 23.4 % across categories and years.
