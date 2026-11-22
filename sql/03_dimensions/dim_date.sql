-- DimDate : generated calendar (no source CSV). Covers whole years around every
-- source date. Role-playing: sales date, demand month (1st of month), snapshot date.
-- Season uses the NORTHERN hemisphere (all locations are in the US).
create or replace table dwh.dim_date as
with bounds as (
    select date_trunc('year', min(d))::date as d0,
           (date_trunc('year', max(d)) + interval 1 year - interval 1 day)::date as d1
    from (select SalesDate d from stg.pharmacy_sale
          union all select DemandMonth from stg.hospital_demand
          union all select SnapshotDate from stg.inventory_snapshot)
),
days as (
    select unnest(generate_series(d0, d1, interval 1 day))::date as Date from bounds
)
select
    cast(strftime(Date, '%Y%m%d') as integer)        as DateKey,
    Date,
    day(Date)                                         as Day,
    dayname(Date)                                     as DayName,
    weekofyear(Date)                                  as WeekOfYear,
    month(Date)                                       as Month,
    monthname(Date)                                   as MonthName,
    'Q' || quarter(Date)                              as Quarter,
    year(Date)                                        as Year,
    strftime(Date, '%Y-%m')                           as YearMonth,
    case when dayofweek(Date) in (0, 6) then 'Yes' else 'No' end as WeekendFlag,
    case when month(Date) in (12, 1, 2) then 'Winter'
         when month(Date) in (3, 4, 5)  then 'Spring'
         when month(Date) in (6, 7, 8)  then 'Summer'
         else 'Autumn' end                            as Season
from days
union all
select -1, null, null, 'Unknown', null, null, 'Unknown', 'NA', null, 'Unknown', 'No', 'Unknown';
