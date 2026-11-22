-- DimMedicine : SCD Type 2 on list prices (cost, wholesale, retail), Type 1 on
-- descriptive attributes, Type 0 on identifiers.  The table is PERSISTENT: it is
-- never dropped, so price history survives every run.
create sequence if not exists dwh.seq_medicine start 1;
create table if not exists dwh.dim_medicine (
    MedicineKey integer, MedicineID varchar(20), InternalSKU varchar(30), GTIN14 varchar(14),
    GenericName varchar(100), FictionalBrandName varchar(100), DiseaseCategory varchar(60),
    ICD10Category varchar(60), ATCCode varchar(15), TherapeuticClass varchar(60),
    DosageForm varchar(40), Strength varchar(30), RouteOfAdministration varchar(30),
    PackSize integer, BaseUnitOfMeasure varchar(20), PrescriptionClass varchar(30),
    ControlledMedicineFlag varchar(3), ColdChainFlag varchar(3),
    StorageMinTempC decimal(5,1), StorageMaxTempC decimal(5,1), MaxHumidityPct decimal(5,2),
    ShelfLifeMonths integer, ProductStatus varchar(20),
    UnitManufacturingCostUSD decimal(12,2), WholesalePriceUSD decimal(12,2),
    RecommendedRetailPriceUSD decimal(12,2),
    EffectiveFromDate date, EffectiveToDate date, CurrentFlag varchar(3), PriceBand varchar(10));

insert into dwh.dim_medicine (MedicineKey, MedicineID, GenericName, FictionalBrandName, DiseaseCategory,
    TherapeuticClass, EffectiveFromDate, EffectiveToDate, CurrentFlag, PriceBand)
select -1, 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown', 'Unknown', date '1900-01-01', date '9999-12-31', 'Yes', 'Unknown'
where not exists (select 1 from dwh.dim_medicine where MedicineKey = -1);

-- 1) SCD Type 2: insert a new version when the medicine is new, or when a list price
--    differs from the version that is current today
insert into dwh.dim_medicine
select nextval('dwh.seq_medicine'), s.MedicineID, s.InternalSKU, s.GTIN14, s.GenericName,
       s.FictionalBrandName, s.DiseaseCategory, s.ICD10Category, s.ATCCode, s.TherapeuticClass,
       s.DosageForm, s.Strength, s.RouteOfAdministration, s.PackSize, s.BaseUnitOfMeasure,
       s.PrescriptionClass, s.ControlledMedicineFlag, s.ColdChainFlag, s.StorageMinTempC,
       s.StorageMaxTempC, s.MaxHumidityPct, s.ShelfLifeMonths, s.ProductStatus,
       s.UnitManufacturingCostUSD, s.WholesalePriceUSD, s.RecommendedRetailPriceUSD,
       s.EffectiveFromDate, date '9999-12-31', 'Yes', null
from stg.medicine s
left join dwh.dim_medicine d on d.MedicineID = s.MedicineID and d.CurrentFlag = 'Yes'
where d.MedicineKey is null
   or (s.EffectiveFromDate > d.EffectiveFromDate and (
          s.UnitManufacturingCostUSD  is distinct from d.UnitManufacturingCostUSD
       or s.WholesalePriceUSD         is distinct from d.WholesalePriceUSD
       or s.RecommendedRetailPriceUSD is distinct from d.RecommendedRetailPriceUSD));

-- 2) close old versions: EffectiveTo = next version's start - 1 day; only the newest is current
update dwh.dim_medicine d
set EffectiveToDate = v.EffectiveToDate, CurrentFlag = v.CurrentFlag
from (select MedicineKey,
             coalesce(lead(EffectiveFromDate) over w - interval 1 day, date '9999-12-31')::date as EffectiveToDate,
             case when lead(EffectiveFromDate) over w is null then 'Yes' else 'No' end as CurrentFlag
      from dwh.dim_medicine where MedicineKey <> -1
      window w as (partition by MedicineID order by EffectiveFromDate)) v
where d.MedicineKey = v.MedicineKey;

-- 3) SCD Type 1: overwrite descriptive attributes on every version of the medicine
update dwh.dim_medicine d
set GenericName = s.GenericName, FictionalBrandName = s.FictionalBrandName,
    DiseaseCategory = s.DiseaseCategory, ICD10Category = s.ICD10Category, ATCCode = s.ATCCode,
    TherapeuticClass = s.TherapeuticClass, PrescriptionClass = s.PrescriptionClass,
    ControlledMedicineFlag = s.ControlledMedicineFlag, ColdChainFlag = s.ColdChainFlag,
    StorageMinTempC = s.StorageMinTempC, StorageMaxTempC = s.StorageMaxTempC,
    MaxHumidityPct = s.MaxHumidityPct, ShelfLifeMonths = s.ShelfLifeMonths, ProductStatus = s.ProductStatus
from (select * from stg.medicine qualify row_number() over (partition by MedicineID order by EffectiveFromDate desc) = 1) s
where d.MedicineID = s.MedicineID;

-- 4) PriceBand (derived): Low / Medium / High using tertile cut-offs of the CURRENT retail prices
update dwh.dim_medicine d
set PriceBand = case when d.RecommendedRetailPriceUSD <= c.p33 then 'Low'
                     when d.RecommendedRetailPriceUSD <= c.p67 then 'Medium' else 'High' end
from (select quantile_cont(RecommendedRetailPriceUSD, 1/3) as p33,
             quantile_cont(RecommendedRetailPriceUSD, 2/3) as p67
      from dwh.dim_medicine where CurrentFlag = 'Yes' and MedicineKey <> -1) c
where d.MedicineKey <> -1;
