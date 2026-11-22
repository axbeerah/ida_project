-- =====================================================================
-- 00 SETUP : schemas, audit tables and reusable cleaning macros
-- raw     = CSVs copied as text (exact copy of the OLTP extracts)
-- stg     = cleaned and typed (transformations from Transform.OLTP sheet)
-- dwh     = star schema (dimensions + facts)
-- mart    = query layer (views used by the dashboard / stakeholders)
-- sandbox = optional oversampled data (never mixed into dwh facts)
-- audit   = load log and data-quality results for every run
-- =====================================================================
create schema if not exists raw;
create schema if not exists stg;
create schema if not exists dwh;
create schema if not exists mart;
create schema if not exists sandbox;
create schema if not exists audit;

create table if not exists audit.load_log (
    run_id varchar, table_name varchar, row_count bigint, loaded_at timestamp);

create table if not exists audit.dq_results (
    run_id varchar, check_file varchar, check_name varchar, severity varchar,
    failed_rows bigint, status varchar, checked_at timestamp);

-- trim + collapse repeated spaces; blank -> NULL
create or replace macro clean_txt(x) as nullif(regexp_replace(trim(x), '\s+', ' ', 'g'), '');
-- clean text with a default for missing values
create or replace macro clean_or(x, dflt) as coalesce(clean_txt(x), dflt);
-- identifiers: trim + uppercase
create or replace macro clean_id(x) as upper(clean_txt(x));
-- Y/N/1/0/True/False -> 'Yes' / 'No'
create or replace macro yes_no(x) as
    case when upper(trim(x)) in ('Y', 'YES', '1', 'TRUE', 'T') then 'Yes' else 'No' end;
-- 1/0 flag for additive counting of flags in facts
create or replace macro flag01(x) as
    case when upper(trim(x)) in ('Y', 'YES', '1', 'TRUE', 'T') then 1 else 0 end::smallint;
-- 'Not applicable' / 'not applicable' -> 'Not Applicable'
create or replace macro std_na(x) as
    case when lower(clean_txt(x)) in ('not applicable', 'n/a', 'na') then 'Not Applicable'
         else clean_or(x, 'Unknown') end;
