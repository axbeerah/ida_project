-- BOOTSTRAP RESAMPLING -> 95% confidence intervals for the headline KPIs.
-- Plain idea: re-draw the 500,000 sales many times (with replacement), recompute the KPI
-- each time, and see how much it moves. The middle 95% of those values is the interval.
-- Formal: Poisson bootstrap - each transaction gets weight w ~ Poisson(1) in each replicate
-- (w = 0,1,2,... drawn from the inverse Poisson CDF), CI = [2.5th, 97.5th] percentile.
select setseed({{seed}});

create or replace table mart.kpi_confidence_intervals as
with base as (
    select Year, DiseaseCategory, NetSalesAmountUSD as net, GrossMarginUSD as gm
    from mart.v_sales),
reps as (select r from range({{replicates}}) t(r)),
weighted as (
    select r, Year, DiseaseCategory, net, gm,
           case when u < 0.367879 then 0 when u < 0.735759 then 1 when u < 0.919699 then 2
                when u < 0.981012 then 3 when u < 0.996340 then 4 when u < 0.999406 then 5 else 6 end as w
    from (select r, b.*, random() as u from reps, base b)),
rep_kpis as (
    select r, Year, DiseaseCategory,
           sum(net * w) as net_sales, 100 * sum(gm * w) / nullif(sum(net * w), 0) as margin_pct
    from weighted group by all),
point as (
    select Year, DiseaseCategory, sum(net) as net_sales, 100 * sum(gm) / sum(net) as margin_pct
    from base group by all)
select p.Year, p.DiseaseCategory,
       round(p.net_sales, 2)                                  as NetSalesUSD,
       round(quantile_cont(r.net_sales, 0.025), 2)            as NetSalesCI95LowUSD,
       round(quantile_cont(r.net_sales, 0.975), 2)            as NetSalesCI95HighUSD,
       round(100 * (quantile_cont(r.net_sales, 0.975) - quantile_cont(r.net_sales, 0.025)) / 2 / p.net_sales, 2)
                                                              as NetSalesMarginOfErrorPct,
       round(p.margin_pct, 2)                                 as GrossMarginPct,
       round(quantile_cont(r.margin_pct, 0.025), 2)           as GrossMarginCI95LowPct,
       round(quantile_cont(r.margin_pct, 0.975), 2)           as GrossMarginCI95HighPct,
       {{replicates}}                                         as Replicates
from point p join rep_kpis r using (Year, DiseaseCategory)
group by p.Year, p.DiseaseCategory, p.net_sales, p.margin_pct
order by 1, 2;
