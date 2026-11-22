-- Data-quality checks on STAGING. Each query returns (check_name, severity, failed_rows).
-- severity 'error' stops the pipeline; 'warn' is logged in audit.dq_results only.
select 'medicine: MedicineID unique per EffectiveFromDate', 'error', count(*) - count(distinct (MedicineID, EffectiveFromDate)) from stg.medicine;
select 'medicine: GTIN14 is 14 digits (leading zero kept)', 'error', count(*) from stg.medicine where not regexp_full_match(GTIN14, '[0-9]{14}');
select 'medicine: StorageMinTempC < StorageMaxTempC', 'error', count(*) from stg.medicine where StorageMinTempC >= StorageMaxTempC;
select 'medicine: prices not negative', 'error', count(*) from stg.medicine where least(UnitManufacturingCostUSD, WholesalePriceUSD, RecommendedRetailPriceUSD) < 0;
select 'sales: SalesTransactionID unique', 'error', count(*) - count(distinct SalesTransactionID) from stg.pharmacy_sale;
select 'sales: SalesDate parsed', 'error', count(*) from stg.pharmacy_sale where SalesDate is null;
select 'sales: Gross = Qty x UnitPrice (+/- 1 cent)', 'error', count(*) from stg.pharmacy_sale where abs(GrossSalesAmountUSD - QuantitySoldPacks * UnitRetailPriceUSD) > 0.011;
select 'sales: Net = Gross - Discount (+/- 1 cent)', 'error', count(*) from stg.pharmacy_sale where abs(NetSalesAmountUSD - (GrossSalesAmountUSD - DiscountAmountUSD)) > 0.011;
select 'sales: Margin = Net - COGS (tax excluded)', 'error', count(*) from stg.pharmacy_sale where abs(GrossMarginUSD - (NetSalesAmountUSD - CostOfGoodsSoldUSD)) > 0.011;
select 'sales: Returned <= Sold', 'error', count(*) from stg.pharmacy_sale where ReturnedQuantityPacks > QuantitySoldPacks;
select 'sales: MedicineID exists in master', 'error', count(*) from stg.pharmacy_sale s where not exists (select 1 from stg.medicine m where m.MedicineID = s.MedicineID);
select 'sales: WarehouseLotID exists in warehouse file', 'warn', count(*) from stg.pharmacy_sale s where not exists (select 1 from stg.inventory_snapshot i where i.WarehouseLotID = s.WarehouseLotID);
select 'sales: sold on/before batch expiry', 'warn', count(*) from stg.pharmacy_sale where SalesDate > BatchExpiryDate;
select 'demand: one row per hospital x medicine x month', 'error', count(*) - count(distinct (HospitalID, MedicineID, DemandMonth)) from stg.hospital_demand;
select 'demand: Approved <= Requested', 'warn', count(*) from stg.hospital_demand where ApprovedQuantityPacks > RequestedQuantityPacks;
select 'demand: Received <= Approved', 'warn', count(*) from stg.hospital_demand where ReceivedQuantityPacks > ApprovedQuantityPacks;
select 'demand: Closing = Opening + Received - Dispensed - Wastage', 'error', count(*) from stg.hospital_demand where ClosingStockPacks <> OpeningStockPacks + ReceivedQuantityPacks - DispensedQuantityPacks - WastageQuantityPacks;
select 'demand: StockoutDays within 0..days in month', 'error', count(*) from stg.hospital_demand where StockoutDays < 0 or StockoutDays > day(last_day(DemandMonth));
select 'demand: ICUBeds <= LicensedBeds', 'error', count(*) from stg.hospital_demand where ICUBeds > LicensedBeds;
select 'demand: HospitalPharmacyID found in sales file', 'warn', count(*) from (select distinct HospitalPharmacyID from stg.hospital_demand) h where not exists (select 1 from stg.pharmacy_sale s where s.PharmacyID = h.HospitalPharmacyID);
select 'inventory: InventorySnapshotID unique', 'error', count(*) - count(distinct InventorySnapshotID) from stg.inventory_snapshot;
select 'inventory: Closing = Opening + In - Out +/- Adjustment', 'error', count(*) from stg.inventory_snapshot where ClosingQuantityPacks <> OpeningQuantityPacks + ReceivedQuantityPacks - ShippedQuantityPacks + TransferInQuantityPacks - TransferOutQuantityPacks - DamagedQuantityPacks - ExpiredQuantityPacks + AdjustmentQuantityPacks;
select 'inventory: lot expiry = batch expiry in 02', 'warn', count(*) from stg.inventory_snapshot i join stg.batch b using (ProductionBatchID) where i.BatchExpiryDate <> b.ExpiryDate;
select 'inventory: every warehouse has a location in 03', 'error', count(*) from (select distinct WarehouseID from stg.inventory_snapshot) w where not exists (select 1 from stg.warehouse_location l where l.WarehouseID = w.WarehouseID);
select 'batch: ExpiryDate after BatchReleaseDate', 'error', count(*) from stg.batch where ExpiryDate <= BatchReleaseDate;
