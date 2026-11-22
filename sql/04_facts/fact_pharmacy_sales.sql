-- FactPharmacySales : transactional, grain = one sales transaction.
-- Full reload each run (dimension keys are persistent, so reloads are reproducible).
-- Every lookup falls back to the -1 'Unknown' / 'Not Applicable' member, never NULL.
create or replace table dwh.fact_pharmacy_sales as
select
    s.SalesTransactionID,                                   -- degenerate (PK)
    s.PharmacyOrderID,                                      -- degenerate
    s.PharmacyDeliveryID,                                   -- degenerate
    coalesce(dd.DateKey, -1)        as DateKey,
    coalesce(m.MedicineKey, -1)     as MedicineKey,         -- SCD2 version valid on the sale date
    coalesce(p.PharmacyKey, -1)     as PharmacyKey,
    coalesce(h.HospitalKey, -1)     as HospitalKey,         -- -1 = Not Applicable (retail / e-commerce)
    coalesce(c.ChannelKey, -1)      as ChannelKey,
    coalesce(w.WarehouseKey, -1)    as WarehouseKey,
    coalesce(l.LotKey, -1)          as LotKey,
    coalesce(b.BatchKey, -1)        as BatchKey,
    s.QuantitySoldPacks,
    s.GrossSalesAmountUSD,
    s.DiscountAmountUSD,
    s.NetSalesAmountUSD,
    s.SalesTaxUSD,
    s.CostOfGoodsSoldUSD,
    s.GrossMarginUSD,
    s.ReturnedQuantityPacks,
    s.UnitRetailPriceUSD,                                   -- non-additive: never SUM
    datediff('day', s.SalesDate, s.BatchExpiryDate) as DaysToExpiryAtSale   -- non-additive
from stg.pharmacy_sale s
left join dwh.dim_date dd       on dd.Date = s.SalesDate
left join dwh.dim_medicine m    on m.MedicineID = s.MedicineID
                               and s.SalesDate between m.EffectiveFromDate and m.EffectiveToDate
left join dwh.dim_pharmacy p    on p.PharmacyID = s.PharmacyID
left join dwh.dim_hospital h    on h.HospitalID = s.HospitalID
left join dwh.dim_channel c     on c.SalesChannel = s.SalesChannel and c.PayerType = s.PayerType
                               and c.PaymentMethod = s.PaymentMethod and c.CustomerSegment = s.CustomerSegment
                               and c.EcommerceDeliveryStatus = s.EcommerceDeliveryStatus
                               and c.PrescriptionRequiredFlag = s.PrescriptionRequiredFlag
                               and c.SaleStatus = s.SaleStatus and c.ReturnFlag = s.ReturnFlag
                               and c.PromotionCode = s.PromotionCode
left join dwh.dim_warehouse w   on w.WarehouseID = s.SourceWarehouseID
left join dwh.dim_lot l         on l.WarehouseLotID = s.WarehouseLotID
left join dwh.dim_batch b       on b.ProductionBatchID = s.ProductionBatchID
order by DateKey;   -- physical ordering by date ~ clustered index / month partition pruning
