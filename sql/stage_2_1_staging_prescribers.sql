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