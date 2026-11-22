-- STAGING: 02 manufacturing (batches), 03 delivery (warehouse locations), 04 warehouse snapshots

-- 02 -> stg.batch : one row per production batch
create or replace table stg.batch as
select
    clean_id(ProductionBatchID)            as ProductionBatchID,
    clean_id(ManufacturingOrderID)         as ManufacturingOrderID,
    clean_id(MedicineID)                   as MedicineID,
    clean_id(PlantID)                      as PlantID,
    clean_or(BatchStatus, 'Unknown')       as BatchStatus,
    clean_or(QualityTestStatus, 'Unknown') as QualityTestStatus,
    try_cast(BatchReleaseDate as date)     as BatchReleaseDate,
    try_cast(ExpiryDate as date)           as ExpiryDate,
    try_cast(StandardBatchSizePacks as integer) as StandardBatchSizePacks
from raw.manufacturing_data;

-- 03 -> stg.warehouse_location : 04 has no address, so the city/state of each
-- warehouse comes from the delivery file (DestinationWarehouseID)
create or replace table stg.warehouse_location as
select
    clean_id(DestinationWarehouseID)     as WarehouseID,
    clean_txt(DestinationWarehouseGLN)   as WarehouseGLN,
    clean_txt(DestinationWarehouseName)  as WarehouseName,
    clean_txt(DestinationCity)           as City,
    clean_id(DestinationState)           as State,
    clean_id(DestinationCountryCode)     as CountryCode
from raw.manufacturer_delivery_data
qualify row_number() over (partition by clean_id(DestinationWarehouseID)
                           order by try_cast(DispatchDate as date) desc) = 1;

-- 04 -> stg.inventory_snapshot : one row per warehouse lot per day
create or replace table stg.inventory_snapshot as
select
    clean_id(InventorySnapshotID)        as InventorySnapshotID,
    try_cast(SnapshotDate as date)       as SnapshotDate,
    clean_id(WarehouseLotID)             as WarehouseLotID,
    clean_id(InboundShipmentID)          as InboundShipmentID,
    try_cast(InboundShipmentLineNumber as integer) as InboundShipmentLineNumber,
    clean_id(ProductionBatchID)          as ProductionBatchID,
    clean_id(MedicineID)                 as MedicineID,
    clean_id(WarehouseID)                as WarehouseID,
    clean_txt(WarehouseGLN)              as WarehouseGLN,
    clean_txt(WarehouseName)             as WarehouseName,
    clean_id(StorageZoneID)              as StorageZoneID,
    clean_txt(StorageCondition)          as StorageCondition,
    try_cast(BatchExpiryDate as date)    as BatchExpiryDate,
    clean_or(InventoryStatus, 'Unknown') as InventoryStatus,
    coalesce(try_cast(OpeningQuantityPacks as integer), 0)       as OpeningQuantityPacks,
    coalesce(try_cast(ReceivedQuantityPacks as integer), 0)      as ReceivedQuantityPacks,
    coalesce(try_cast(PutawayQuantityPacks as integer), 0)       as PutawayQuantityPacks,
    coalesce(try_cast(QuarantineQuantityPacks as integer), 0)    as QuarantineQuantityPacks,
    coalesce(try_cast(AvailableQuantityPacks as integer), 0)     as AvailableQuantityPacks,
    coalesce(try_cast(ReservedQuantityPacks as integer), 0)      as ReservedQuantityPacks,
    coalesce(try_cast(PickedQuantityPacks as integer), 0)        as PickedQuantityPacks,
    coalesce(try_cast(ShippedQuantityPacks as integer), 0)       as ShippedQuantityPacks,
    coalesce(try_cast(TransferInQuantityPacks as integer), 0)    as TransferInQuantityPacks,
    coalesce(try_cast(TransferOutQuantityPacks as integer), 0)   as TransferOutQuantityPacks,
    coalesce(try_cast(DamagedQuantityPacks as integer), 0)       as DamagedQuantityPacks,
    coalesce(try_cast(ExpiredQuantityPacks as integer), 0)       as ExpiredQuantityPacks,
    coalesce(try_cast(AdjustmentQuantityPacks as integer), 0)    as AdjustmentQuantityPacks,
    coalesce(try_cast(ClosingQuantityPacks as integer), 0)       as ClosingQuantityPacks,
    coalesce(try_cast(AllocatedBinCapacityPacks as integer), 0)  as AllocatedBinCapacityPacks,
    flag01(StockoutFlag)                 as StockoutFlag,
    flag01(NearExpiryFlag)               as NearExpiryFlag,
    try_cast(WarehouseTotalCapacityPacks as integer) as WarehouseTotalCapacityPacks,
    clean_or(WarehouseActivityStatus, 'Unknown')     as WarehouseActivityStatus
from raw.warehouse_data;
