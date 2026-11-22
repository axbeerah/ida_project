-- DimLocation : conformed geography shared by pharmacies (05), hospitals (06) and
-- warehouses (03).  Hierarchy Country > State > City.  SCD Type 1, persistent keys.
create sequence if not exists dwh.seq_location start 1;
create table if not exists dwh.dim_location (
    LocationKey integer, CountryCode varchar(3), Country varchar(40),
    State varchar(60), City varchar(60));

insert into dwh.dim_location
select -1, 'NA', 'Unknown', 'Unknown', 'Unknown'
where not exists (select 1 from dwh.dim_location where LocationKey = -1);

create or replace temp table src_location as
select distinct CountryCode,
       case CountryCode when 'US' then 'United States' else CountryCode end as Country,
       State, City
from (select CountryCode, PharmacyState as State, PharmacyCity as City from stg.pharmacy_sale
      union select CountryCode, State, City from stg.hospital_demand
      union select CountryCode, State, City from stg.warehouse_location)
where City is not null;

insert into dwh.dim_location
select nextval('dwh.seq_location'), s.CountryCode, s.Country, s.State, s.City
from src_location s
where not exists (select 1 from dwh.dim_location d
                  where d.CountryCode = s.CountryCode and d.State = s.State and d.City = s.City);
