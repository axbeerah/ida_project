-- Junk dimensions: one row per distinct combination of low-cardinality flags/statuses.
-- DimChannel (05) and DimDemandStatus (06). Type 0 (a combination never changes).

create sequence if not exists dwh.seq_channel start 1;
create table if not exists dwh.dim_channel (
    ChannelKey integer, SalesChannel varchar(30), PayerType varchar(30), PaymentMethod varchar(30),
    CustomerSegment varchar(30), EcommerceDeliveryStatus varchar(30), PrescriptionRequiredFlag varchar(3),
    SaleStatus varchar(20), ReturnFlag varchar(3), PromotionCode varchar(20));
insert into dwh.dim_channel
select -1, 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'No', 'Unknown', 'No', 'No Promotion'
where not exists (select 1 from dwh.dim_channel where ChannelKey = -1);
insert into dwh.dim_channel
select nextval('dwh.seq_channel'), s.* from (
    select distinct SalesChannel, PayerType, PaymentMethod, CustomerSegment, EcommerceDeliveryStatus,
                    PrescriptionRequiredFlag, SaleStatus, ReturnFlag, PromotionCode
    from stg.pharmacy_sale) s
where not exists (
    select 1 from dwh.dim_channel d
    where d.SalesChannel = s.SalesChannel and d.PayerType = s.PayerType and d.PaymentMethod = s.PaymentMethod
      and d.CustomerSegment = s.CustomerSegment and d.EcommerceDeliveryStatus = s.EcommerceDeliveryStatus
      and d.PrescriptionRequiredFlag = s.PrescriptionRequiredFlag and d.SaleStatus = s.SaleStatus
      and d.ReturnFlag = s.ReturnFlag and d.PromotionCode = s.PromotionCode);

create sequence if not exists dwh.seq_demand_status start 1;
create table if not exists dwh.dim_demand_status (
    DemandStatusKey integer, FormularyStatus varchar(30), MedicationRequestStatus varchar(30));
insert into dwh.dim_demand_status
select -1, 'Unknown', 'Unknown'
where not exists (select 1 from dwh.dim_demand_status where DemandStatusKey = -1);
insert into dwh.dim_demand_status
select nextval('dwh.seq_demand_status'), s.* from (
    select distinct FormularyStatus, MedicationRequestStatus from stg.hospital_demand) s
where not exists (select 1 from dwh.dim_demand_status d
                  where d.FormularyStatus = s.FormularyStatus
                    and d.MedicationRequestStatus = s.MedicationRequestStatus);
