USE ROLE ACCOUNTADMIN;
USE DATABASE cms_dw;
USE SCHEMA analytics;



-- Create a string masking policy
CREATE OR REPLACE MASKING POLICY cms_dw.analytics.phi_name_mask AS (val STRING)
RETURNS STRING ->
  CASE
    -- Privileged roles get to see the actual names
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER') THEN val
    -- All other roles see the masked label
    ELSE '***[REDACTED PHI - HIPAA MASKED]***'
  END;

ALTER TABLE cms_dw.analytics.dim_provider 
  MODIFY COLUMN provider_name 
  SET MASKING POLICY cms_dw.analytics.phi_name_mask;

-- 3.1 Create the restricted role
CREATE ROLE IF NOT EXISTS analyst_restricted;

-- 3.2 Grant folder access (usage) on database and analytics schema
GRANT USAGE ON DATABASE cms_dw TO ROLE analyst_restricted;
GRANT USAGE ON SCHEMA cms_dw.analytics TO ROLE analyst_restricted;

-- 3.3 Grant read-only access to our dimension table
GRANT SELECT ON TABLE cms_dw.analytics.dim_provider TO ROLE analyst_restricted;

-- 3.4 Grant permission to use our computing engine (warehouse)
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE analyst_restricted;

-- 3.5 Automatically grant this new restricted role to your current logged-in user
DECLARE
  current_username VARCHAR;
BEGIN
  SELECT CURRENT_USER() INTO :current_username;
  EXECUTE IMMEDIATE 'GRANT ROLE analyst_restricted TO USER "' || current_username || '"';
END;


--VALIDATE

USE ROLE ACCOUNTADMIN;

SELECT npi, provider_name, specialty, state 
FROM cms_dw.analytics.dim_provider 
LIMIT 5;

USE ROLE analyst_restricted;
USE WAREHOUSE COMPUTE_WH; -- Re-link the warehouse to our new active session

SELECT npi, provider_name, specialty, state 
FROM cms_dw.analytics.dim_provider 
LIMIT 5;