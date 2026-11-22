-- FactInventorySnapshot : periodic snapshot, grain = warehouse lot x snapshot date.
create or replace table dwh.fact_inventory_snapshot as
select
    i.InventorySnapshotID,                                  -- degenerate (PK)
    coalesce(dd.DateKey, -1)      as DateKey,
    coalesce(w.WarehouseKey, -1)  as WarehouseKey,
    coalesce(l.LotKey, -1)        as LotKey,
    coalesce(m.MedicineKey, -1)   as MedicineKey,
    i.InventoryStatus,                                      -- degenerate status
    -- semi-additive stock levels (sum across warehouses/lots, not across dates)
    i.OpeningQuantityPacks, i.ClosingQuantityPacks, i.AvailableQuantityPacks, i.ReservedQuantityPacks,
    i.QuarantineQuantityPacks, i.AllocatedBinCapacityPacks,
    -- fully additive daily movements
    i.ReceivedQuantityPacks, i.PutawayQuantityPacks, i.PickedQuantityPacks, i.ShippedQuantityPacks,
    i.TransferInQuantityPacks, i.TransferOutQuantityPacks, i.DamagedQuantityPacks,
    i.ExpiredQuantityPacks, i.AdjustmentQuantityPacks,
    -- flags as 1/0 so SUM = number of snapshots with the condition
    i.StockoutFlag, i.NearExpiryFlag,
    datediff('day', i.SnapshotDate, i.BatchExpiryDate) as DaysToExpiry   -- non-additive
from stg.inventory_snapshot i
left join dwh.dim_date dd       on dd.Date = i.SnapshotDate
left join dwh.dim_warehouse w   on w.WarehouseID = i.WarehouseID
left join dwh.dim_lot l         on l.WarehouseLotID = i.WarehouseLotID
left join dwh.dim_medicine m    on m.MedicineID = i.MedicineID
                               and i.SnapshotDate between m.EffectiveFromDate and m.EffectiveToDate
order by DateKey;
