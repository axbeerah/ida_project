-- DimPharmacy (05) and DimHospital (06) : SCD Type 1, persistent keys.
-- Both carry CustomerType so sales and demand can be shown side by side.

-- ---------- DimPharmacy ----------
create sequence if not exists dwh.seq_pharmacy start 1;
create table if not exists dwh.dim_pharmacy (
    PharmacyKey integer, PharmacyID varchar(20), PharmacyGLN varchar(13), PharmacyName varchar(100),
    PharmacyType varchar(40), HospitalID varchar(20), HospitalPharmacyFlag varchar(3),
    CustomerType varchar(10), LocationKey integer);
insert into dwh.dim_pharmacy (PharmacyKey, PharmacyID, PharmacyName, PharmacyType, HospitalID,
                              HospitalPharmacyFlag, CustomerType, LocationKey)
select -1, 'UNKNOWN', 'Unknown', 'Unknown', 'Not Applicable', 'No', 'Pharmacy', -1
where not exists (select 1 from dwh.dim_pharmacy where PharmacyKey = -1);

create or replace temp table src_pharmacy as
select p.PharmacyID, p.PharmacyGLN, p.PharmacyName, p.PharmacyType, p.HospitalID,
       case when p.HospitalID <> 'Not Applicable' then 'Yes' else 'No' end as HospitalPharmacyFlag,
       'Pharmacy' as CustomerType, coalesce(l.LocationKey, -1) as LocationKey
from (select * from stg.pharmacy_sale   -- 05 repeats the pharmacy on every sale: keep the latest
      qualify row_number() over (partition by PharmacyID order by SalesTimestampUTC desc) = 1) p
left join dwh.dim_location l
       on l.CountryCode = p.CountryCode and l.State = p.PharmacyState and l.City = p.PharmacyCity;

update dwh.dim_pharmacy d
set PharmacyName = s.PharmacyName, PharmacyType = s.PharmacyType, HospitalID = s.HospitalID,
    HospitalPharmacyFlag = s.HospitalPharmacyFlag, LocationKey = s.LocationKey
from src_pharmacy s where d.PharmacyID = s.PharmacyID;
insert into dwh.dim_pharmacy
select nextval('dwh.seq_pharmacy'), s.* from src_pharmacy s
where not exists (select 1 from dwh.dim_pharmacy d where d.PharmacyID = s.PharmacyID);

-- ---------- DimHospital ----------
create sequence if not exists dwh.seq_hospital start 1;
create table if not exists dwh.dim_hospital (
    HospitalKey integer, HospitalID varchar(20), HospitalGLN varchar(13), HospitalName varchar(100),
    HospitalType varchar(40), TraumaLevel varchar(20), LicensedBeds integer, ICUBeds integer,
    HospitalSizeBand varchar(10), CatchmentPopulation integer, HospitalPharmacyID varchar(20),
    CustomerType varchar(10), LocationKey integer);
-- -1 = 'Not Applicable': retail and e-commerce sales point here instead of a NULL key
insert into dwh.dim_hospital (HospitalKey, HospitalID, HospitalName, HospitalType, TraumaLevel,
                              HospitalSizeBand, HospitalPharmacyID, CustomerType, LocationKey)
select -1, 'Not Applicable', 'Not Applicable', 'Not Applicable', 'Not Applicable',
       'Not Applicable', 'Not Applicable', 'Hospital', -1
where not exists (select 1 from dwh.dim_hospital where HospitalKey = -1);

create or replace temp table src_hospital as
select h.HospitalID, h.HospitalGLN, h.HospitalName, h.HospitalType, h.TraumaLevel,
       h.LicensedBeds, h.ICUBeds,
       case ntile(3) over (order by h.LicensedBeds) when 1 then 'Small' when 2 then 'Medium' else 'Large' end
           as HospitalSizeBand,
       h.CatchmentPopulation,   -- constant per hospital (EDA), so moved from the fact to the dimension
       h.HospitalPharmacyID, 'Hospital' as CustomerType, coalesce(l.LocationKey, -1) as LocationKey
from (select * from stg.hospital_demand
      qualify row_number() over (partition by HospitalID order by DemandMonth desc) = 1) h
left join dwh.dim_location l on l.CountryCode = h.CountryCode and l.State = h.State and l.City = h.City;

update dwh.dim_hospital d
set HospitalName = s.HospitalName, HospitalType = s.HospitalType, TraumaLevel = s.TraumaLevel,
    LicensedBeds = s.LicensedBeds, ICUBeds = s.ICUBeds, HospitalSizeBand = s.HospitalSizeBand,
    CatchmentPopulation = s.CatchmentPopulation, HospitalPharmacyID = s.HospitalPharmacyID,
    LocationKey = s.LocationKey
from src_hospital s where d.HospitalID = s.HospitalID;
insert into dwh.dim_hospital
select nextval('dwh.seq_hospital'), s.* from src_hospital s
where not exists (select 1 from dwh.dim_hospital d where d.HospitalID = s.HospitalID);
