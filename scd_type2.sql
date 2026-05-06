USE ROLE ACCOUNTADMIN;
USE DATABASE cms_dw;
USE SCHEMA analytics;

-- 1.1 Drop the old Type 1 dimension
DROP TABLE IF EXISTS cms_dw.analytics.dim_provider;

-- 1.2 Recreate the table with historical tracking dimensions (with the explicit ::DATE cast)
CREATE OR REPLACE TABLE cms_dw.analytics.dim_provider (
    provider_key     INT IDENTITY(1,1) PRIMARY KEY, -- Surrogate Key
    npi              INT,                           -- Natural Business Key
    provider_name    VARCHAR,
    specialty        VARCHAR,
    state            VARCHAR,
    effective_date   DATE DEFAULT CURRENT_DATE(),
    expiry_date      DATE DEFAULT '9999-12-31'::DATE, -- Explicitly cast the text string to a DATE object
    is_current       BOOLEAN DEFAULT TRUE
);

-- 1.3 Seed the table with your current staging data
INSERT INTO cms_dw.analytics.dim_provider (npi, provider_name, specialty, state)
SELECT 
  npi, 
  CONCAT_WS(', ', last_name, first_name) AS provider_name,
  specialty,
  state
FROM cms_dw.staging.stg_prescribers;



-- Standard, High-Performance SCD Type 2 Transaction
BEGIN TRANSACTION;

  -- Step A: Expire existing active records if their specialty or state has changed in staging
  UPDATE cms_dw.analytics.dim_provider target
  SET 
    target.expiry_date = CURRENT_DATE() - 1,
    target.is_current = FALSE
  FROM cms_dw.staging.stg_prescribers source
  WHERE target.npi = source.npi
    AND target.is_current = TRUE
    AND (
      target.specialty <> source.specialty 
      OR target.state <> source.state
    );

  -- Step B: Insert brand-new records AND the new active versions of modified records
  -- (If we expired a record in Step A, target.is_current = TRUE no longer matches, leaving target.npi as NULL)
  INSERT INTO cms_dw.analytics.dim_provider (npi, provider_name, specialty, state, effective_date, expiry_date, is_current)
  SELECT 
    source.npi,
    CONCAT_WS(', ', source.last_name, source.first_name) AS provider_name,
    source.specialty,
    source.state,
    CURRENT_DATE() AS effective_date,
    '9999-12-31' AS expiry_date,
    TRUE AS is_current
  FROM cms_dw.staging.stg_prescribers source
  LEFT JOIN cms_dw.analytics.dim_provider target
    ON source.npi = target.npi 
    AND target.is_current = TRUE
  WHERE target.npi IS NULL;

COMMIT;


--VALIDATE

SELECT npi, provider_name, specialty, state, effective_date, expiry_date, is_current 
FROM cms_dw.analytics.dim_provider 
LIMIT 1;

UPDATE cms_dw.staging.stg_prescribers
SET specialty = 'Data Engineering'
WHERE npi = 1003000126; -- Replace with your test NPI if different

SELECT provider_key, npi, provider_name, specialty, effective_date, expiry_date, is_current 
FROM cms_dw.analytics.dim_provider 
WHERE npi = 1003000126;