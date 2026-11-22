-- FactHospitalDemand : periodic snapshot, grain = hospital x medicine x month.
-- DemandMonth is the 1st of the month, so it joins DimDate at day level and rolls up by YearMonth.
create or replace table dwh.fact_hospital_demand as
select
    d.HospitalDemandRecordID,                               -- degenerate (PK)
    coalesce(dd.DateKey, -1)         as DateKey,
    coalesce(h.HospitalKey, -1)      as HospitalKey,
    coalesce(m.MedicineKey, -1)      as MedicineKey,
    coalesce(ds.DemandStatusKey, -1) as DemandStatusKey,
    -- fully additive (packs)
    d.ForecastDemandPacks, d.RequestedQuantityPacks, d.ApprovedQuantityPacks, d.ReceivedQuantityPacks,
    d.EmergencyRequestQuantityPacks, d.DispensedQuantityPacks, d.ConsumedQuantityPacks,
    d.WastageQuantityPacks, d.UnfulfilledDemandPacks, d.StockoutDays,
    -- semi-additive: sum across hospitals / medicines, NOT across months
    d.OpeningStockPacks, d.ClosingStockPacks,
    -- non-additive: average / weighted average only
    d.ServiceLevelPct, d.AverageLeadTimeDays, d.DemandTrendIndex, d.AverageOccupancyRatePct,
    d.OutpatientEncounters, d.EstimatedDiseaseCases, d.DiseaseRelatedAdmissions
from stg.hospital_demand d
left join dwh.dim_date dd           on dd.Date = d.DemandMonth
left join dwh.dim_hospital h        on h.HospitalID = d.HospitalID
left join dwh.dim_medicine m        on m.MedicineID = d.MedicineID
                                   and d.DemandMonth between m.EffectiveFromDate and m.EffectiveToDate
left join dwh.dim_demand_status ds  on ds.FormularyStatus = d.FormularyStatus
                                   and ds.MedicationRequestStatus = d.MedicationRequestStatus
order by DateKey;
