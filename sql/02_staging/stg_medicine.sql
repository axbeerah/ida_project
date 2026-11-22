-- STAGING: 01_master_data -> stg.medicine  (one row per MedicineID version)
-- Transformations follow the Transform.OLTP sheet rows 1-30.
create or replace table stg.medicine as
select
    clean_id(MedicineID)                                  as MedicineID,
    clean_id(InternalSKU)                                 as InternalSKU,
    clean_txt(GTIN14)                                     as GTIN14,          -- text: keeps leading zero
    clean_txt(GenericName)                                as GenericName,
    clean_txt(FictionalBrandName)                         as FictionalBrandName,
    clean_or(DiseaseCategory, 'Unclassified')             as DiseaseCategory,
    clean_or(ICD10Category, 'Unclassified')               as ICD10Category,
    coalesce(clean_id(ATCCode), 'UNCLASSIFIED')           as ATCCode,
    clean_or(TherapeuticClass, 'Unclassified')            as TherapeuticClass,
    clean_txt(DosageForm)                                 as DosageForm,
    clean_txt(Strength)                                   as Strength,
    clean_txt(RouteOfAdministration)                      as RouteOfAdministration,
    try_cast(PackSize as integer)                         as PackSize,
    clean_txt(BaseUnitOfMeasure)                          as BaseUnitOfMeasure,
    clean_txt(PrescriptionClass)                          as PrescriptionClass,
    yes_no(ControlledMedicineFlag)                        as ControlledMedicineFlag,
    yes_no(ColdChainFlag)                                 as ColdChainFlag,
    try_cast(StorageMinTempC as decimal(5,1))             as StorageMinTempC,
    try_cast(StorageMaxTempC as decimal(5,1))             as StorageMaxTempC,
    try_cast(MaxHumidityPct as decimal(5,2))              as MaxHumidityPct,
    try_cast(ShelfLifeMonths as integer)                  as ShelfLifeMonths,
    clean_txt(ProductStatus)                              as ProductStatus,
    round(try_cast(UnitManufacturingCostUSD as decimal(12,4)), 2)::decimal(12,2)  as UnitManufacturingCostUSD,
    round(try_cast(WholesalePriceUSD as decimal(12,4)), 2)::decimal(12,2)         as WholesalePriceUSD,
    round(try_cast(RecommendedRetailPriceUSD as decimal(12,4)), 2)::decimal(12,2) as RecommendedRetailPriceUSD,
    try_cast(EffectiveFromDate as date)                   as EffectiveFromDate
from raw.master_data;
