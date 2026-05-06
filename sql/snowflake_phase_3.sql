-- Stage 3 — The Dimensional Model.

-- Step 3.1: Create a dedicated schema folder for our clean analytical model
CREATE SCHEMA IF NOT EXISTS cms_dw.analytics;
USE SCHEMA cms_dw.analytics;


-- Step 3.2: Build the Provider Dimension Table (dim_provider)
-- We denormalize first and last names into a clean display name
CREATE OR REPLACE TABLE cms_dw.analytics.dim_provider AS
SELECT
  npi,
  CONCAT_WS(', ', last_name, first_name) AS provider_name,
  specialty,
  state
FROM cms_dw.staging.stg_prescribers;


-- Step 3.3: Build the Drug Dimension Table (dim_drug)
-- We use an auto-incrementing surrogate key (identity) to uniquely identify each drug
CREATE OR REPLACE TABLE cms_dw.analytics.dim_drug (
  drug_key INT IDENTITY(1,1),
  drug_name VARCHAR,
  generic_name VARCHAR,
  is_generic VARCHAR(1)
);

-- Populate the Drug Dimension with unique drugs from our claims data
INSERT INTO cms_dw.analytics.dim_drug (drug_name, generic_name, is_generic)
SELECT DISTINCT 
  drug_name, 
  generic_name,
  CASE WHEN drug_name = generic_name THEN 'Y' ELSE 'N' END AS is_generic
FROM cms_dw.staging.stg_drug_claims;


-- Step 3.4: Build the central Fact Table (fct_claims)
-- We join our staging claims to our newly created drug dimension to swap text names for the surrogate drug_key
CREATE OR REPLACE TABLE cms_dw.analytics.fct_claims AS
SELECT
  c.npi,
  d.drug_key,
  p.state,
  p.specialty,
  c.claim_count,
  c.beneficiary_count,
  c.total_drug_cost,
  c.total_day_supply,
  2026 AS reporting_year
FROM cms_dw.staging.stg_drug_claims c
JOIN cms_dw.analytics.dim_drug d 
  ON c.drug_name = d.drug_name 
  AND c.generic_name = d.generic_name
JOIN cms_dw.analytics.dim_provider p 
  ON c.npi = p.npi;


-- Validate

SELECT 
  p.provider_name,
  p.specialty,
  p.state,
  d.drug_name,
  d.is_generic,
  f.claim_count,
  f.total_drug_cost
FROM cms_dw.analytics.fct_claims f
JOIN cms_dw.analytics.dim_provider p ON f.npi = p.npi
JOIN cms_dw.analytics.dim_drug d ON f.drug_key = d.drug_key
LIMIT 10;