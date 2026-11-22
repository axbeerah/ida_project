-- STAGING: 05 pharmacy sales and 06 hospital demand

-- 05 -> stg.pharmacy_sale : one row per sales transaction
create or replace table stg.pharmacy_sale as
select
    clean_id(SalesTransactionID)          as SalesTransactionID,
    try_cast(SalesDate as date)           as SalesDate,
    try_cast(SalesTimestampUTC as timestamp) as SalesTimestampUTC,
    clean_or(SalesChannel, 'Unknown')     as SalesChannel,
    clean_id(PharmacyID)                  as PharmacyID,
    clean_txt(PharmacyGLN)                as PharmacyGLN,
    clean_txt(PharmacyName)               as PharmacyName,
    clean_or(PharmacyType, 'Unknown')     as PharmacyType,
    coalesce(clean_id(HospitalID), 'Not Applicable') as HospitalID,   -- blank = retail / e-commerce
    clean_txt(PharmacyCity)               as PharmacyCity,
    clean_id(PharmacyState)               as PharmacyState,
    clean_id(CountryCode)                 as CountryCode,
    clean_id(PharmacyOrderID)             as PharmacyOrderID,
    clean_id(PharmacyDeliveryID)          as PharmacyDeliveryID,
    clean_id(WarehouseLotID)              as WarehouseLotID,
    clean_id(SourceWarehouseID)           as SourceWarehouseID,
    clean_id(ProductionBatchID)           as ProductionBatchID,
    clean_id(MedicineID)                  as MedicineID,
    try_cast(BatchExpiryDate as date)     as BatchExpiryDate,
    coalesce(try_cast(QuantitySoldPacks as integer), 0)          as QuantitySoldPacks,
    try_cast(UnitRetailPriceUSD as decimal(12,2))                as UnitRetailPriceUSD,
    coalesce(try_cast(GrossSalesAmountUSD as decimal(12,2)), 0)  as GrossSalesAmountUSD,
    coalesce(try_cast(DiscountAmountUSD as decimal(12,2)), 0)    as DiscountAmountUSD,
    coalesce(try_cast(NetSalesAmountUSD as decimal(12,2)), 0)    as NetSalesAmountUSD,
    coalesce(try_cast(SalesTaxUSD as decimal(12,2)), 0)          as SalesTaxUSD,
    coalesce(try_cast(CostOfGoodsSoldUSD as decimal(12,2)), 0)   as CostOfGoodsSoldUSD,
    coalesce(try_cast(GrossMarginUSD as decimal(12,2)), 0)       as GrossMarginUSD,
    coalesce(try_cast(ReturnedQuantityPacks as integer), 0)      as ReturnedQuantityPacks,
    -- junk-dimension attributes (DimChannel)
    clean_or(PayerType, 'Unknown')        as PayerType,
    clean_or(PaymentMethod, 'Unknown')    as PaymentMethod,
    clean_or(CustomerSegment, 'Unknown')  as CustomerSegment,
    std_na(EcommerceDeliveryStatus)       as EcommerceDeliveryStatus,
    yes_no(PrescriptionRequiredFlag)      as PrescriptionRequiredFlag,
    clean_or(SaleStatus, 'Unknown')       as SaleStatus,
    yes_no(ReturnFlag)                    as ReturnFlag,
    case when upper(clean_or(PromotionCode, 'NONE')) = 'NONE' then 'No Promotion'
         else upper(clean_txt(PromotionCode)) end as PromotionCode
from raw.pharmacy_sales_data;

-- 06 -> stg.hospital_demand : one row per hospital x medicine x month
create or replace table stg.hospital_demand as
select
    clean_id(HospitalDemandRecordID)      as HospitalDemandRecordID,
    try_cast(DemandMonth as date)         as DemandMonth,
    clean_id(HospitalID)                  as HospitalID,
    clean_txt(HospitalGLN)                as HospitalGLN,
    clean_txt(HospitalName)               as HospitalName,
    clean_or(HospitalType, 'Unknown')     as HospitalType,
    clean_id(HospitalPharmacyID)          as HospitalPharmacyID,
    clean_txt(City)                       as City,
    clean_id(State)                       as State,
    clean_id(CountryCode)                 as CountryCode,
    try_cast(LicensedBeds as integer)     as LicensedBeds,
    try_cast(ICUBeds as integer)          as ICUBeds,
    try_cast(AverageOccupancyRatePct as decimal(5,2)) as AverageOccupancyRatePct,
    case when clean_txt(TraumaLevel) is null then 'Not Classified'
         when clean_txt(TraumaLevel) = 'None' then 'No Trauma Level'
         else clean_txt(TraumaLevel) end  as TraumaLevel,
    try_cast(CatchmentPopulation as integer) as CatchmentPopulation,
    clean_id(MedicineID)                  as MedicineID,
    try_cast(EstimatedDiseaseCases as integer)     as EstimatedDiseaseCases,
    try_cast(DiseaseRelatedAdmissions as integer)  as DiseaseRelatedAdmissions,
    try_cast(OutpatientEncounters as integer)      as OutpatientEncounters,
    coalesce(try_cast(ForecastDemandPacks as integer), 0)           as ForecastDemandPacks,
    coalesce(try_cast(RequestedQuantityPacks as integer), 0)        as RequestedQuantityPacks,
    coalesce(try_cast(ApprovedQuantityPacks as integer), 0)         as ApprovedQuantityPacks,
    coalesce(try_cast(ReceivedQuantityPacks as integer), 0)         as ReceivedQuantityPacks,
    coalesce(try_cast(EmergencyRequestQuantityPacks as integer), 0) as EmergencyRequestQuantityPacks,
    coalesce(try_cast(OpeningStockPacks as integer), 0)             as OpeningStockPacks,
    coalesce(try_cast(DispensedQuantityPacks as integer), 0)        as DispensedQuantityPacks,
    coalesce(try_cast(ConsumedQuantityPacks as integer), 0)         as ConsumedQuantityPacks,
    coalesce(try_cast(WastageQuantityPacks as integer), 0)          as WastageQuantityPacks,
    coalesce(try_cast(ClosingStockPacks as integer), 0)             as ClosingStockPacks,
    coalesce(try_cast(UnfulfilledDemandPacks as integer), 0)        as UnfulfilledDemandPacks,
    coalesce(try_cast(StockoutDays as integer), 0)                  as StockoutDays,
    try_cast(ServiceLevelPct as decimal(5,2))                       as ServiceLevelPct,
    try_cast(AverageLeadTimeDays as decimal(6,2))                   as AverageLeadTimeDays,
    try_cast(DemandTrendIndex as decimal(8,3))                      as DemandTrendIndex,
    clean_or(MedicationRequestStatus, 'Unknown') as MedicationRequestStatus,
    clean_or(FormularyStatus, 'Unknown')         as FormularyStatus
from raw.hospital_demand_data;
