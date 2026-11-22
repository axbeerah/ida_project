# Milestone 1 — SDI Data Mart

Sales & Demand Intelligence data mart for the pharma supply chain case (Problem 1 in the dataset guide:
*sales and demand come from separate systems at different levels of detail, with no unified view of demand*).

## Requirement checklist

| Requirement | Status | Evidence |
|---|---|---|
| **Complete Excel file** | Done | [`excel/DWH_Template_Milestone1_SDI_DataMart.xlsx`](excel/DWH_Template_Milestone1_SDI_DataMart.xlsx): all template sheets complete, plus `EDA.Findings` and `Implementation.Map` |
| **Airflow till query layer** | Done | DAG [`pharma_sdi_data_mart`](../dags/pharma_sdi_data_mart_dag.py): extract → staging → DQ → dimensions → facts → DQ → query layer (`mart` schema) → exports 

## What was built

**Excel design → code, one to one.** The `Implementation.Map` sheet of the workbook lists the Airflow task and the repository
file for every step of the design.

| Layer | Objects | Rows (last run) |
|---|---|---|
| raw | 7 tables, one per source CSV, all columns as text | 934,448 |
| staging | `stg.medicine, batch, warehouse_location, inventory_snapshot, pharmacy_sale, hospital_demand` | 640,000+ |
| dimensions | DimDate 1,097 · DimLocation 23 · DimMedicine 64 · DimPharmacy 61 · DimHospital 13 · DimWarehouse 7 · DimLot 965 · DimBatch 562 · DimChannel 1,784 · DimDemandStatus 7 | (counts include the -1 member) |
| facts | FactPharmacySales 500,000 · FactHospitalDemand 27,216 · FactInventorySnapshot 112,184 | 639,400 |
| query layer | `mart.q1_sales_trend`, `mart.q2_demand_vs_sales`, `mart.q3_unmet_vs_stockouts`, `mart.kpi_monthly`, `mart.what_if_base`, `mart.kpi_confidence_intervals` | exported to [`../exports`](../exports) |

Design decisions that came out of the data profiling (full list in [`docs/eda_report.md`](docs/eda_report.md)):

- **Hospital pharmacy is a channel of its own.** The source has only two sales channels, *Physical Pharmacy* and *Ecommerce*.
  Hospital-pharmacy sales are separated in the query layer through `PharmacyType`, which gives three channel groups.
- **`UnfulfilledDemandPacks` is not Requested − Received.** That rule fails on 27,123 rows, so the check uses the
  stock balance that holds on every row: Closing = Opening + Received − Dispensed − Wastage.
- **`CatchmentPopulation` moved to DimHospital** because it is constant per hospital.
- **Days of Cover uses warehouse outflow.** Pharmacy sales are only about 10 % of what leaves the warehouses, because
  hospitals are supplied directly. Using sales gave 1,000+ days of cover; warehouse outflow gives about 80 days.
- **SCD Type 2 on medicine prices** is built and tested (`tests/test_scd2_dim_medicine.py`), even though the
  current master file has only one price version per medicine.

## The three dimensional queries and what they found

| # | Question | Finding from the last run |
|---|---|---|
| Q1 | Monthly sales by disease category, channel and state | Retail 60 %, hospital pharmacies 23 %, e-commerce 17 % of $5.97M net sales. Strong winter peaks (Dec–Jan); Jan 2025 is the peak month at $1.18M. |
| Q2 | Forecast demand vs. hospital consumption vs. hospital-pharmacy sales | Forecast accuracy 92.8–95.1 % per month, with a slight under-forecast bias (−1.1 %). Hospital pharmacies sell only 2.3 % of what hospitals consume. |
| Q3 | Unmet hospital demand vs. warehouse stockouts in the same state | 2,563 packs unmet in 78 cases; 73 % happened while the state's warehouse still had stock, so the cause is distribution rather than supply. |

## Screenshots of the successful run

| | |
|---|---|
| DAG graph, all task groups expanded | [`02_dag_graph_success.png`](demo/screenshots/02_dag_graph_success.png) |
| Grid view, 30 tasks green (oversampling branch skipped as configured) | [`03_dag_grid_all_tasks_success.png`](demo/screenshots/03_dag_grid_all_tasks_success.png) |
| Staging data-quality log (25 checks) | [`04_log_dq_checks_staging.png`](demo/screenshots/04_log_dq_checks_staging.png) |
| Star-schema reconciliation log (18 checks) | [`05_log_dq_checks_star_schema.png`](demo/screenshots/05_log_dq_checks_star_schema.png) |
| Fact load and query-layer export logs | [`06`](demo/screenshots/06_log_fact_pharmacy_sales.png), [`07`](demo/screenshots/07_log_export_query_layer.png) |
| DAG list and parameters | [`01`](demo/screenshots/01_airflow_dag_list.png), [`08`](demo/screenshots/08_dag_details_params.png) |
