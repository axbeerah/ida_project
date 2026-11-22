-- =====================================================================
-- QUERY LAYER (schema mart) : views stakeholders and the dashboard read.
-- q1-q3 are the 3 dimensional queries from the Star.Schema sheet.
-- =====================================================================

-- Helper: one flat, readable sales view (star join done once)
create or replace view mart.v_sales as
select f.*, d.Date, d.Year, d.Quarter, d.YearMonth, d.MonthName, d.Season,
       m.MedicineID, m.GenericName, m.DiseaseCategory, m.TherapeuticClass, m.ColdChainFlag, m.PriceBand,
       p.PharmacyID, p.PharmacyName, p.PharmacyType,
       c.SalesChannel, c.PayerType, c.PaymentMethod, c.CustomerSegment, c.PromotionCode,
       -- 3-way channel used by the business: hospital pharmacies are a separate channel
       case when p.PharmacyType = 'Hospital Pharmacy' then 'Hospital Pharmacy'
            when c.SalesChannel = 'Ecommerce' then 'E-commerce'
            else 'Retail Pharmacy' end as ChannelGroup,
       l.Country, l.State, l.City
from dwh.fact_pharmacy_sales f
join dwh.dim_date d      on d.DateKey = f.DateKey
join dwh.dim_medicine m  on m.MedicineKey = f.MedicineKey
join dwh.dim_pharmacy p  on p.PharmacyKey = f.PharmacyKey
join dwh.dim_channel c   on c.ChannelKey = f.ChannelKey
join dwh.dim_location l  on l.LocationKey = p.LocationKey;

-- Q1: How did sales quantity and net revenue change month by month for each disease category,
--     split by channel (retail, hospital pharmacy, e-commerce) and by state?
create or replace view mart.q1_sales_trend as
select Year, YearMonth, DiseaseCategory, ChannelGroup, State,
       count(*)                                  as Transactions,
       sum(QuantitySoldPacks)                    as PacksSold,
       round(sum(NetSalesAmountUSD), 2)          as NetSalesUSD,
       round(sum(GrossMarginUSD), 2)             as GrossMarginUSD,
       round(100 * sum(GrossMarginUSD) / nullif(sum(NetSalesAmountUSD), 0), 2) as GrossMarginPct
from mart.v_sales
group by all;

-- Q2: For every month, hospital and medicine: forecast vs actual consumption vs quantity sold
--     through that hospital's own pharmacy (drill-across on conformed Date, Hospital, Medicine).
create or replace view mart.q2_demand_vs_sales as
with s as (
    select d.YearMonth, f.HospitalKey, m.MedicineID, sum(f.QuantitySoldPacks) as SoldPacks
    from dwh.fact_pharmacy_sales f
    join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey
    where f.HospitalKey <> -1
    group by all),
dm as (
    select d.YearMonth, f.HospitalKey, m.MedicineID,
           sum(f.ForecastDemandPacks) as ForecastPacks, sum(f.ConsumedQuantityPacks) as ConsumedPacks,
           sum(f.DispensedQuantityPacks) as DispensedPacks, sum(f.UnfulfilledDemandPacks) as UnfulfilledPacks
    from dwh.fact_hospital_demand f
    join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey
    group by all)
select dm.YearMonth, h.HospitalName, h.HospitalType, mm.MedicineID, mm.GenericName, mm.DiseaseCategory,
       dm.ForecastPacks, dm.ConsumedPacks, dm.DispensedPacks, dm.UnfulfilledPacks,
       coalesce(s.SoldPacks, 0)                                  as HospitalPharmacySoldPacks,
       dm.ForecastPacks - dm.ConsumedPacks                       as ForecastErrorPacks,
       round(100.0 * abs(dm.ForecastPacks - dm.ConsumedPacks) / nullif(dm.ConsumedPacks, 0), 2) as AbsPctError,
       round(coalesce(s.SoldPacks, 0) * 1.0 / nullif(dm.ConsumedPacks, 0), 3) as SalesToConsumptionRatio
from dm
left join s using (YearMonth, HospitalKey, MedicineID)
join dwh.dim_hospital h on h.HospitalKey = dm.HospitalKey
join dwh.dim_medicine mm on mm.MedicineID = dm.MedicineID and mm.CurrentFlag = 'Yes';

-- Q3: Where did hospitals report unfulfilled demand while warehouses in the same state had
--     stockouts or low stock? (drill-across Demand x Inventory on Date-month, Medicine, Location-state)
create or replace view mart.q3_unmet_vs_stockouts as
with u as (
    select d.YearMonth, l.State, m.DiseaseCategory,
           sum(f.UnfulfilledDemandPacks) as UnmetPacks, sum(f.StockoutDays) as HospitalStockoutDays
    from dwh.fact_hospital_demand f
    join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_hospital h on h.HospitalKey = f.HospitalKey
    join dwh.dim_location l on l.LocationKey = h.LocationKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey
    group by all),
i as (
    select d.YearMonth, l.State, m.DiseaseCategory,
           sum(f.StockoutFlag) as WarehouseStockoutSnapshots,
           round(avg(f.ClosingQuantityPacks), 1) as AvgLotClosingPacks,
           sum(f.NearExpiryFlag) as NearExpirySnapshots
    from dwh.fact_inventory_snapshot f
    join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_warehouse w on w.WarehouseKey = f.WarehouseKey
    join dwh.dim_location l on l.LocationKey = w.LocationKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey
    group by all)
select u.YearMonth, u.State, u.DiseaseCategory, u.UnmetPacks, u.HospitalStockoutDays,
       coalesce(i.WarehouseStockoutSnapshots, 0) as WarehouseStockoutSnapshots,
       i.AvgLotClosingPacks, coalesce(i.NearExpirySnapshots, 0) as NearExpirySnapshots,
       case when i.State is null then 'No warehouse in state'
            when i.WarehouseStockoutSnapshots > 0 then 'Warehouse stockout same month'
            else 'Warehouse had stock' end as SupplySideSignal
from u left join i using (YearMonth, State, DiseaseCategory)
where u.UnmetPacks > 0;

-- KPI overview per month (all three facts, aggregated to month first, then joined)
create or replace view mart.kpi_monthly as
with s as (
    select YearMonth, sum(NetSalesAmountUSD) as NetSalesUSD, sum(GrossMarginUSD) as GrossMarginUSD,
           sum(QuantitySoldPacks) as PacksSold, sum(ReturnedQuantityPacks) as ReturnedPacks,
           count(*) as Transactions
    from mart.v_sales group by 1),
dm as (
    select d.YearMonth, sum(f.ForecastDemandPacks) as ForecastPacks, sum(f.ConsumedQuantityPacks) as ConsumedPacks,
           sum(abs(f.ForecastDemandPacks - f.ConsumedQuantityPacks)) as AbsErrorPacks,
           sum(f.UnfulfilledDemandPacks) as UnfulfilledPacks,
           sum(f.ServiceLevelPct * f.RequestedQuantityPacks) / nullif(sum(f.RequestedQuantityPacks), 0) as ServiceLevelPct
    from dwh.fact_hospital_demand f join dwh.dim_date d on d.DateKey = f.DateKey group by 1),
inv as (
    select d.YearMonth, sum(f.StockoutFlag) as StockoutSnapshots, count(*) as Snapshots,
           sum(f.ExpiredQuantityPacks) as ExpiredPacks, sum(f.DamagedQuantityPacks) as DamagedPacks,
           sum(f.ReceivedQuantityPacks) as WarehouseReceivedPacks,
           sum(f.ShippedQuantityPacks) as WarehouseShippedPacks, count(distinct f.DateKey) as SnapshotDays
    from dwh.fact_inventory_snapshot f join dwh.dim_date d on d.DateKey = f.DateKey group by 1),
eom as (  -- semi-additive: closing stock on the LAST snapshot date of each month
    select d.YearMonth, sum(f.ClosingQuantityPacks) as MonthEndStockPacks
    from dwh.fact_inventory_snapshot f join dwh.dim_date d on d.DateKey = f.DateKey
    where f.DateKey in (select max(f2.DateKey) from dwh.fact_inventory_snapshot f2
                        join dwh.dim_date d2 on d2.DateKey = f2.DateKey group by d2.YearMonth)
    group by 1)
select s.YearMonth,
       round(s.NetSalesUSD, 2) as NetSalesUSD,
       round(100 * s.GrossMarginUSD / nullif(s.NetSalesUSD, 0), 2) as GrossMarginPct,
       s.PacksSold, s.Transactions,
       round(100.0 * s.ReturnedPacks / nullif(s.PacksSold, 0), 3) as ReturnRatePct,
       dm.ForecastPacks, dm.ConsumedPacks,
       round(100 * (1 - dm.AbsErrorPacks * 1.0 / nullif(dm.ConsumedPacks, 0)), 2) as ForecastAccuracyPct,
       round(100.0 * (dm.ForecastPacks - dm.ConsumedPacks) / nullif(dm.ConsumedPacks, 0), 2) as ForecastBiasPct,
       dm.UnfulfilledPacks, round(dm.ServiceLevelPct, 2) as ServiceLevelPct,
       round(100.0 * inv.StockoutSnapshots / nullif(inv.Snapshots, 0), 3) as StockoutRatePct,
       round(100.0 * (inv.ExpiredPacks + inv.DamagedPacks) / nullif(inv.WarehouseReceivedPacks, 0), 3) as ExpiredDamagedPct,
       inv.WarehouseShippedPacks, eom.MonthEndStockPacks,
       -- Days of cover = month-end stock / average packs shipped per day by the warehouses.
       -- (Warehouse outflow, not pharmacy sales: warehouses also supply hospitals.)
       round(eom.MonthEndStockPacks / nullif(inv.WarehouseShippedPacks * 1.0 / inv.SnapshotDays, 0), 1) as DaysOfCover
from s left join dm using (YearMonth) left join inv using (YearMonth) left join eom using (YearMonth)
order by s.YearMonth;

-- What-if base table: one row per disease category with the last 12 months' run-rates.
-- The dashboard applies "demand +x%" and "supply delay of n days" on top of these numbers.
create or replace view mart.what_if_base as
with last_date as (select max(Date) as d from mart.v_sales),
s as (
    select DiseaseCategory,
           sum(QuantitySoldPacks) / 365.0                           as AvgDailyPacksSold,
           sum(NetSalesAmountUSD) / nullif(sum(QuantitySoldPacks), 0) as NetPricePerPackUSD,
           sum(GrossMarginUSD) / nullif(sum(QuantitySoldPacks), 0)    as MarginPerPackUSD
    from mart.v_sales, last_date where Date > d - interval 365 day group by 1),
dm as (
    select m.DiseaseCategory, sum(f.ConsumedQuantityPacks) / 12.0 as AvgMonthlyHospitalConsumption
    from dwh.fact_hospital_demand f join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey, last_date
    where d.Date > last_date.d - interval 365 day group by 1),
st as (
    select m.DiseaseCategory, sum(f.ClosingQuantityPacks) as CurrentStockPacks
    from dwh.fact_inventory_snapshot f join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey
    where f.DateKey = (select max(DateKey) from dwh.fact_inventory_snapshot) group by 1),
ship as (
    select m.DiseaseCategory, sum(f.ShippedQuantityPacks) / 365.0 as AvgDailyShippedPacks
    from dwh.fact_inventory_snapshot f join dwh.dim_date d on d.DateKey = f.DateKey
    join dwh.dim_medicine m on m.MedicineKey = f.MedicineKey, last_date
    where d.Date > last_date.d - interval 365 day group by 1)
select s.DiseaseCategory,
       round(s.AvgDailyPacksSold, 1) as AvgDailyPacksSold,
       round(ship.AvgDailyShippedPacks, 1) as AvgDailyShippedPacks,
       round(s.NetPricePerPackUSD, 2) as NetPricePerPackUSD,
       round(s.MarginPerPackUSD, 2) as MarginPerPackUSD,
       round(dm.AvgMonthlyHospitalConsumption, 0) as AvgMonthlyHospitalConsumption,
       coalesce(st.CurrentStockPacks, 0) as CurrentStockPacks,
       round(coalesce(st.CurrentStockPacks, 0) / nullif(ship.AvgDailyShippedPacks, 0), 1) as DaysOfCover
from s left join dm using (DiseaseCategory) left join st using (DiseaseCategory)
       left join ship using (DiseaseCategory)
order by 1;
