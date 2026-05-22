# vendor_selection

Overview
--------
This repository contains SQL models and utilities for ranking vendors by a value-for-money score that balances delivery performance, scale (volume), and price. The score is designed to prefer vendors that are reliable, proven at scale, and cost-effective.

Goals
-----
- Join vendor pricing, performance, and manager (metadata) staging models.
- Compute a vendor score that combines delivery rate and volume, and penalizes price.
- Rank vendors and products by score (at country, vendor, and product levels).
- Report average send amount and delivery rate for vendor groups to support selection decisions.

Score formula (plain English)
-----------------------------
score = performance value / price penalty

Translated:
round( ((deliver_rate_decimal) * ln(1 + send_amount)) / (1 + 10000 * rate), 4 ) AS score

Where:
- deliver_rate_decimal = coalesce(deliver_rate, 0) / 100.0
  - Converts deliver_rate from percentage to decimal (98 → 0.98). Nulls treated as 0.
- ln(1 + coalesce(send_amount, 0))
  - Volume factor using natural log to give diminishing returns for very large volumes.
- 1 + 10000 * coalesce(rate, 0)
  - Price penalty. The 10000 constant scales small rate decimals so price materially affects rankings.
- round(..., 4)
  - Standardize the score to 4 decimal places.

Why this design?
- Multiplying delivery rate by a log(volume) rewards vendors that are both reliable and proven at scale, but prevents huge-volume vendors from dominating purely by size.
- Dividing by (1 + 10000 * rate) penalizes higher price; the 1 prevents division-by-zero.
- Rounding to 4 decimals simplifies display and ranking; ties can occur because ranks are computed on rounded scores.

Recommended SQL implementation
----------------------------------------
The example below demonstrates:
1. Join of three staging models: vendor_pricing, vendor_performance, vendor_manager (on vendor_id, country_code)
2. Score calculation
3. Product- and vendor-level aggregation and ranking
4. Reporting average send_amount and deliver_rate at vendor level

Replace the table names / CTE sources with your environment (dbt models, schemas, or tables) as needed.

```sql
with
pricing as (
  select vendor_id, country_code, product_id, rate
  from staging.vendor_pricing
),
performance as (
  select vendor_id, country_code, product_id, deliver_rate, send_amount
  from staging.vendor_performance
),
manager as (
  select vendor_id, country_code, vendor_name
  from staging.vendor_manager
),

vendor_base as (
  select
    p.vendor_id,
    p.country_code,
    p.product_id,
    p.rate,
    pf.deliver_rate,
    pf.send_amount,
    m.vendor_name,
    round(
      (
        (coalesce(pf.deliver_rate, 0) / 100.0) * ln(1 + coalesce(pf.send_amount, 0))
      ) / (1 + 10000 * coalesce(p.rate, 0))
    , 4) as score
  from pricing p
  left join performance pf
    on p.vendor_id = pf.vendor_id
    and p.country_code = pf.country_code
    and p.product_id = pf.product_id
  left join manager m
    on p.vendor_id = m.vendor_id
    and p.country_code = m.country_code
),

-- product- and vendor-level ranks
scored as (
  select
    *,
    dense_rank() over (partition by country_code order by score desc nulls last) as country_product_rank,
    dense_rank() over (partition by country_code, vendor_id order by score desc nulls last) as vendor_product_rank
  from vendor_base
),

-- vendor-level aggregation (best product score and averages)
vendor_agg as (
  select
    country_code,
    vendor_id,
    vendor_name,
    max(score) as vendor_score,                        -- vendor's best product score in that country
    avg(send_amount) as avg_send_amount,
    avg(deliver_rate) as avg_deliver_rate,
    count(distinct product_id) as product_count
  from scored
  group by country_code, vendor_id, vendor_name
),

-- final: product rows with vendor-level metrics
final as (
  select
    s.*,
    va.vendor_score,
    va.avg_send_amount,
    va.avg_deliver_rate
  from scored s
  left join vendor_agg va
    on s.country_code = va.country_code
    and s.vendor_id = va.vendor_id
)

select * from final;
```

Ranking patterns & notes
------------------------
- country-level ranking (products): dense_rank() partition by country_code order by score desc
- vendor-level ranking (products per vendor): dense_rank() partition by country_code, vendor_id order by score desc
- vendor-level score is computed as the vendor's best product score (max(score)) per country — this lets you rank vendors by their top offering in each market.
- Consider ranking on the raw (unrounded) score if ties are problematic; rounding to 4 decimals is mainly for display consistency.

Impact: Why the project saves vendor selection operation time (the 40%)
---------------------------------------------------------------------
We report two measurable operational improvements:
1. Data collection automation: procurement previously spent ~10 hours/week manually pulling Excel files from suppliers; with the dashboard, repeated data collection is automated and refreshes in ~1 minute.
2. Logistics improvement: by dynamically replacing low-performing suppliers, the logistics delay rate was reduced by 40%—this reduces follow-up/rework time.

How the "40% overall time savings" is calculated (example with assumptions)
- We must separate two things: (A) time saved from automating manual data pulls and (B) time saved from fewer logistics incidents (rework/communication).
- Example conservative calculation:

Assumptions (example that leads to ~40% overall reduction):
- Original total vendor-selection workload (all tasks related to vendor selection & follow-up): 30 hours/week
  - Manual data pulls: 10 hours/week
  - Communications & follow-up (including logistics delay handling): 5 hours/week
  - Analysis & admin: 15 hours/week
- Automation effect:
  - Manual data pulls reduced from 10 hours to ~0.017 hours (1 minute) → direct save ≈ 9.983 hours
- Logistics improvement:
  - Logistics delay rate reduced by 40% → assume communications & follow-up time reduces proportionally:
    - Follow-up time saved = 0.40 * 5 hours = 2 hours
- Total saved = 9.983 + 2 = 11.983 hours
- Overall % reduction = 11.983 / 30 ≈ 0.3994 → ~39.94% ≈ 40%

Key points:
- The 40% figure is an overall operational reduction (not only the direct saving from automation).
- The exact % depends on the original distribution of time across tasks. Using the concrete numbers above (30h total, 10h manual pulls, 5h follow-up), the combined automation + logistics improvement yields ~40% reduction.
- If you change the assumed original total hours or the share of time spent on data pulling vs. follow-up, the overall percentage will change. The README documents the assumptions and computation so stakeholders can re-run the math with their real-time measurements.

Worked numeric example (data-collection-only)
- Old: 10 hours/week = 600 minutes
- New: 1 minute/week
- Direct reduction = (600 - 1) / 600 ≈ 99.83% for the data-collection task alone
- But the vendor-selection operation includes many tasks; combining the direct reduction with rework reduction yields the reported ~40% overall reduction (see the worked calculation above).

Technical challenges & solutions
-------------------------------
1) Overlapping effective periods in historical quotation data
- Problem: historical quotations had overlapping effective date ranges, so a single transaction timestamp might match multiple candidate prices.
- Solution: derive valid non-overlapping price intervals per vendor/product using LEAD/LAG to compute the next effective_from (or effective_to), then join transactions to those intervals. Alternatively use a time-range BETWEEN or lateral/time-range join depending on your SQL engine.

Example A — use LEAD to build non-overlapping ranges (Postgres / BigQuery / Snowflake style):

```sql
with prices_with_bounds as (
  select
    vendor_id,
    product_id,
    effective_from as valid_from,
    coalesce(lead(effective_from) over (partition by vendor_id, product_id order by effective_from), '9999-12-31') as valid_to_exclusive,
    price
  from raw.vendor_quotes
)
select t.*,
       p.price as price_at_txn
from transactions t
left join prices_with_bounds p
  on t.vendor_id = p.vendor_id
  and t.product_id = p.product_id
  and t.transaction_ts >= p.valid_from
  and t.transaction_ts < p.valid_to_exclusive;
```

Example B — time-range BETWEEN / lateral join (engines with APPLY/lateral or range types):

```sql
select t.*,
       p.price
from transactions t
left join lateral (
  select price
  from raw.vendor_quotes q
  where q.vendor_id = t.vendor_id
    and q.product_id = t.product_id
    and t.transaction_ts between q.effective_from and coalesce(q.effective_to, '9999-12-31')
  order by q.effective_from desc
  limit 1
) p on true;
```

Notes:
- Use explicit tie-breakers (e.g., prefer the quote with the latest effective_from) when multiple overlaps remain after cleaning.
- As a data-quality step, detect overlapping quotations and log them for review.

2) Defensive null handling & scaling constants
- Treat null deliver_rate or send_amount as 0 deliberately (penalizes missing data).
- Document the 10000 scaling constant and add tests to evaluate sensitivity.

Testing & validation
--------------------
- Unit test score calculation with deterministic inputs (include the worked example).
- Create fixture datasets that exercise:
  - deliver_rate null
  - send_amount 0
  - rate 0
  - overlapping quotes
- Run sensitivity analysis over the 10000 constant to evaluate price sensitivity.

Repository structure (suggested)
--------------------------------
- models/
  - staging/
    - vendor_pricing.sql
    - vendor_performance.sql
    - vendor_manager.sql
    - vendor_quotes.sql
  - marts/
    - int_vendor_selection__vendor_pricing_performance_manager.sql  -- main scoring + ranking model
    - vendor_aggregates.sql
- tests/ (unit tests for the score and example cases)
- docs/ (design, assumptions, tuning notes)

How to run
----------
- If using dbt: place SQL models in dbt `models/` folders and run `dbt run`.
- In a plain SQL environment: run the SQL snippets after replacing `staging.*` with your table names.
- Add tests to validate exact score outputs for deterministic inputs.

Next steps & suggestions
------------------------
- Add a short automated job that recalculates vendor_score and notifies procurement if vendor_rank changes by more than N positions.
- Add sensitivity tests to sweep the 10000 constant and produce a report on rank churn.
- Add a small demo dataset and unit tests to CI so the formula and the 40% calculation are reproducible.
- If desired, I can produce a commented version of int_vendor_selection__vendor_pricing_performance_manager.sql with line-by-line explanations or add the LEAD/LAG price-cleaning model to the repo.

Contact / Maintainers
---------------------
- Maintainer: repository owner (see repo settings for contact)
- For questions about tuning constants or ranking behavior, open an issue describing the observed behavior and a sample vendor pair to compare.

License
-------
Specify a license (e.g., MIT) at the repo root if this code is to be openly reused.
