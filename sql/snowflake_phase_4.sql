-- Stage 4: Create the Analytical Views

USE SCHEMA cms_dw.analytics;

-- View 1: Top 10 Prescribers by State
-- Interview Talking Point: "Demonstrates window functions (DENSE_RANK) to partition and rank massive datasets."
CREATE OR REPLACE VIEW cms_dw.analytics.v_top_10_prescribers_by_state AS
WITH ranked_spend AS (
  SELECT 
    p.state,
    p.provider_name,
    p.specialty,
    SUM(f.total_drug_cost) AS total_spend,
    DENSE_RANK() OVER (PARTITION BY p.state ORDER BY SUM(f.total_drug_cost) DESC) as spend_rank
  FROM cms_dw.analytics.fct_claims f
  JOIN cms_dw.analytics.dim_provider p ON f.npi = p.npi
  GROUP BY p.state, p.provider_name, p.specialty
)
SELECT * FROM ranked_spend WHERE spend_rank <= 10;


-- View 2: Brand vs Generic Ratio by Specialty
-- Interview Talking Point: "Demonstrates conditional aggregation to calculate dynamic metrics across dimensions."
CREATE OR REPLACE VIEW cms_dw.analytics.v_specialty_brand_ratios AS
SELECT 
  f.specialty,
  SUM(CASE WHEN d.is_generic = 'N' THEN f.claim_count ELSE 0 END) AS brand_claims,
  SUM(CASE WHEN d.is_generic = 'Y' THEN f.claim_count ELSE 0 END) AS generic_claims,
  ROUND(brand_claims / NULLIF(brand_claims + generic_claims, 0), 4) AS brand_ratio
FROM cms_dw.analytics.fct_claims f
JOIN cms_dw.analytics.dim_drug d ON f.drug_key = d.drug_key
GROUP BY f.specialty;


-- View 3: Year-over-Year (YoY) Claim Volume Change
-- Interview Talking Point: "Demonstrates time-series analysis using lead/lag analytic functions."
CREATE OR REPLACE VIEW cms_dw.analytics.v_yoy_drug_volume AS
WITH yearly_agg AS (
  SELECT 
    d.drug_name,
    f.reporting_year,
    SUM(f.claim_count) AS total_claims
  FROM cms_dw.analytics.fct_claims f
  JOIN cms_dw.analytics.dim_drug d ON f.drug_key = d.drug_key
  GROUP BY d.drug_name, f.reporting_year
)
SELECT 
  drug_name,
  reporting_year,
  total_claims,
  LAG(total_claims) OVER (PARTITION BY drug_name ORDER BY reporting_year) as previous_year_claims,
  ROUND(((total_claims - previous_year_claims) / NULLIF(previous_year_claims, 0)) * 100, 2) AS yoy_pct_change
FROM yearly_agg;


-- Validate

-- Query a sample of the view
SELECT * FROM cms_dw.analytics.v_top_10_prescribers_by_state 
ORDER BY state, spend_rank 
LIMIT 20;

-- Assert that no state has more than 10 records
SELECT state, COUNT(*) as prescriber_count
FROM cms_dw.analytics.v_top_10_prescribers_by_state
GROUP BY state
HAVING COUNT(*) > 10;

-- Query specialties with the highest brand-name drug ratios
SELECT specialty, brand_claims, generic_claims, brand_ratio
FROM cms_dw.analytics.v_specialty_brand_ratios
WHERE brand_claims > 100 OR generic_claims > 100 -- Filters out low-volume outliers
ORDER BY brand_ratio DESC
LIMIT 15;


-- Test query simulating 2025 vs 2026 data to force the YoY logic to trigger
WITH simulated_two_year_data AS (
  -- Year 1: Actual 2026 data
  SELECT drug_key, reporting_year, claim_count 
  FROM cms_dw.analytics.fct_claims
  UNION ALL
  -- Year 2: Simulated 2025 data (arbitrarily cutting claim counts in half)
  SELECT drug_key, 2025 AS reporting_year, ROUND(claim_count * 0.5) AS claim_count 
  FROM cms_dw.analytics.fct_claims
),
yearly_agg AS (
  SELECT 
    d.drug_name,
    s.reporting_year,
    SUM(s.claim_count) AS total_claims
  FROM simulated_two_year_data s
  JOIN cms_dw.analytics.dim_drug d ON s.drug_key = d.drug_key
  GROUP BY d.drug_name, s.reporting_year
)
SELECT 
  drug_name,
  reporting_year,
  total_claims,
  LAG(total_claims) OVER (PARTITION BY drug_name ORDER BY reporting_year) as previous_year_claims,
  ROUND(((total_claims - previous_year_claims) / NULLIF(previous_year_claims, 0)) * 100, 2) AS yoy_pct_change
FROM yearly_agg
ORDER BY drug_name, reporting_year
LIMIT 20;