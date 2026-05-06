-- Stage 2: Create the Staging Tables

-- Step 2.1: Create a brand new schema folder for staging
CREATE SCHEMA IF NOT EXISTS cms_dw.staging;
USE SCHEMA cms_dw.staging;

-- Step 2.2: Create Clean Prescribers Staging Table
CREATE OR REPLACE TABLE cms_dw.staging.stg_prescribers AS
SELECT DISTINCT
  CAST(Prscrbr_NPI AS INT) AS npi,
  NULLIF(TRIM(Prscrbr_Last_Org_Name), '') AS last_name,
  NULLIF(TRIM(Prscrbr_First_Name), '') AS first_name,
  UPPER(NULLIF(TRIM(Prscrbr_City), '')) AS city,
  UPPER(NULLIF(TRIM(Prscrbr_State_Abrvtn), '')) AS state,
  NULLIF(TRIM(Prscrbr_Type), '') AS specialty
FROM cms_dw.raw.raw_partd_prescribers
WHERE Prscrbr_NPI IS NOT NULL;

-- Step 2.3: Create Clean Claims Staging Table
CREATE OR REPLACE TABLE cms_dw.staging.stg_drug_claims AS
SELECT
  CAST(Prscrbr_NPI AS INT) AS npi,
  UPPER(NULLIF(TRIM(Brnd_Name), '')) AS drug_name,
  UPPER(NULLIF(TRIM(Gnrc_Name), '')) AS generic_name,
  COALESCE(TRY_CAST(NULLIF(TRIM(Tot_Benes), '') AS INT), 0) AS beneficiary_count,
  COALESCE(TRY_CAST(NULLIF(TRIM(Tot_Clms), '') AS INT), 0) AS claim_count,
  COALESCE(TRY_CAST(NULLIF(TRIM(Tot_30day_Fills), '') AS DOUBLE), 0.0) AS total_30_day_fills,
  COALESCE(TRY_CAST(NULLIF(TRIM(Tot_Day_Suply), '') AS INT), 0) AS total_day_supply,
  COALESCE(TRY_CAST(NULLIF(TRIM(Tot_Drug_Cst), '') AS DOUBLE), 0.0) AS total_drug_cost
FROM cms_dw.raw.raw_partd_prescribers
WHERE Prscrbr_NPI IS NOT NULL AND Brnd_Name IS NOT NULL;

-- Validate 

-- Check if the first table exists and has data
SELECT COUNT(*) AS prescriber_count FROM cms_dw.staging.stg_prescribers;

-- Check if the second table exists and has data
SELECT COUNT(*) AS claims_count FROM cms_dw.staging.stg_drug_claims;