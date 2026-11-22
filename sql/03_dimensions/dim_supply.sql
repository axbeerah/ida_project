-- DimBatch, DimLot, DimWarehouse : supply-side dimensions (SCD Type 1, persistent keys)

-- ---------- DimBatch (02) ----------
create sequence if not exists dwh.seq_batch start 1;
create table if not exists dwh.dim_batch (
    BatchKey integer, ProductionBatchID varchar(30), ManufacturingOrderID varchar(30),
    MedicineID varchar(20), PlantID varchar(20), BatchStatus varchar(20), QualityTestStatus varchar(20),
    BatchReleaseDate date, ExpiryDate date, StandardBatchSizePacks integer);
insert into dwh.dim_batch (BatchKey, ProductionBatchID, BatchStatus, QualityTestStatus)
select -1, 'UNKNOWN', 'Unknown', 'Unknown'
where not exists (select 1 from dwh.dim_batch where BatchKey = -1);
update dwh.dim_batch d set BatchStatus = s.BatchStatus, QualityTestStatus = s.QualityTestStatus
from stg.batch s where d.ProductionBatchID = s.ProductionBatchID;
insert into dwh.dim_batch
select nextval('dwh.seq_batch'), s.* from stg.batch s
where not exists (select 1 from dwh.dim_batch d where d.ProductionBatchID = s.ProductionBatchID);

-- ---------- DimLot (04) ----------
create sequence if not exists dwh.seq_lot start 1;
create table if not exists dwh.dim_lot (
    LotKey integer, WarehouseLotID varchar(30), ProductionBatchID varchar(30),
    InboundShipmentID varchar(30), InboundShipmentLineNumber integer, BatchExpiryDate date);
insert into dwh.dim_lot (LotKey, WarehouseLotID, ProductionBatchID)
select -1, 'UNKNOWN', 'UNKNOWN'
where not exists (select 1 from dwh.dim_lot where LotKey = -1);
insert into dwh.dim_lot
select nextval('dwh.seq_lot'), s.* from (
    select distinct WarehouseLotID, ProductionBatchID, InboundShipmentID,
           InboundShipmentLineNumber, BatchExpiryDate
    from stg.inventory_snapshot) s
where not exists (select 1 from dwh.dim_lot d where d.WarehouseLotID = s.WarehouseLotID);

-- ---------- DimWarehouse (04 + location from 03) ----------
create sequence if not exists dwh.seq_warehouse start 1;
create table if not exists dwh.dim_warehouse (
    WarehouseKey integer, WarehouseID varchar(20), WarehouseGLN varchar(13), WarehouseName varchar(100),
    WarehouseTotalCapacityPacks integer, WarehouseActivityStatus varchar(30), LocationKey integer);
insert into dwh.dim_warehouse (WarehouseKey, WarehouseID, WarehouseName, LocationKey)
select -1, 'UNKNOWN', 'Unknown', -1
where not exists (select 1 from dwh.dim_warehouse where WarehouseKey = -1);

create or replace temp table src_warehouse as
select w.WarehouseID, w.WarehouseGLN, w.WarehouseName, w.WarehouseTotalCapacityPacks,
       w.WarehouseActivityStatus, coalesce(l.LocationKey, -1) as LocationKey
from (select * from stg.inventory_snapshot
      qualify row_number() over (partition by WarehouseID order by SnapshotDate desc) = 1) w
left join stg.warehouse_location wl on wl.WarehouseID = w.WarehouseID
left join dwh.dim_location l on l.CountryCode = wl.CountryCode and l.State = wl.State and l.City = wl.City;

update dwh.dim_warehouse d
set WarehouseName = s.WarehouseName, WarehouseTotalCapacityPacks = s.WarehouseTotalCapacityPacks,
    WarehouseActivityStatus = s.WarehouseActivityStatus, LocationKey = s.LocationKey
from src_warehouse s where d.WarehouseID = s.WarehouseID;
insert into dwh.dim_warehouse
select nextval('dwh.seq_warehouse'), s.* from src_warehouse s
where not exists (select 1 from dwh.dim_warehouse d where d.WarehouseID = s.WarehouseID);
