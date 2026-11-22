-- OPTIONAL OVERSAMPLING (only runs when the DAG parameter oversample_factor > 1)
-- Bootstrap oversampling = draw sales transactions WITH replacement until the table is
-- factor x the original size. Each copy gets a new SyntheticTransactionID.
-- Output goes to the SANDBOX schema only: the real facts in dwh are never inflated,
-- because duplicated rows would double revenue and quantities in every KPI.
select setseed({{seed}});

create or replace table sandbox.fact_pharmacy_sales_oversampled as
with base as (
    select *, row_number() over (order by SalesTransactionID) as _rn
    from dwh.fact_pharmacy_sales),
n as (select count(*) as n from base),
draws as (
    select i as DrawNo, 1 + floor(random() * n.n)::bigint as _rn
    from n, range(cast(round({{factor}} * n.n) as bigint)) t(i))
select b.* exclude (_rn),
       b.SalesTransactionID || '-OS' || lpad(d.DrawNo::varchar, 8, '0') as SyntheticTransactionID,
       {{factor}} as OversampleFactor
from draws d join base b using (_rn);

-- Proof that the mix is preserved: share of net sales per disease category, real vs oversampled
create or replace view sandbox.v_oversample_check as
with real as (
    select m.DiseaseCategory, sum(f.NetSalesAmountUSD) as v from dwh.fact_pharmacy_sales f
    join dwh.dim_medicine m using (MedicineKey) group by 1),
os as (
    select m.DiseaseCategory, sum(f.NetSalesAmountUSD) as v from sandbox.fact_pharmacy_sales_oversampled f
    join dwh.dim_medicine m using (MedicineKey) group by 1)
select DiseaseCategory,
       round(100 * real.v / sum(real.v) over (), 3) as RealSharePct,
       round(100 * os.v / sum(os.v) over (), 3)     as OversampledSharePct,
       round(real.v, 2) as RealNetSalesUSD, round(os.v, 2) as OversampledNetSalesUSD
from real join os using (DiseaseCategory) order by 1;
