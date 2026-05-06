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