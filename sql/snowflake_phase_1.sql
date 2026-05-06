-- A. Stage Data from GCS

-- 1. Ensure we are using the Admin role and active warehouse
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

-- 2. Ensure our database and schema folders exist
CREATE DATABASE IF NOT EXISTS cms_dw;
CREATE SCHEMA IF NOT EXISTS cms_dw.raw;

-- 3. Explicitly tell our session to use this schema
USE DATABASE cms_dw;
USE SCHEMA raw;

-- 4. Recreate the File Format inside cms_dw.raw
CREATE OR REPLACE FILE FORMAT cms_dw.raw.cms_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE;

-- 5. Recreate the Stage inside cms_dw.raw pointing to your GCS bucket
CREATE OR REPLACE STAGE cms_dw.raw.gcs_cms_stage
  URL = 'gcs://cms-partd-data-demo/'
  STORAGE_INTEGRATION = gcs_cms_integration
  FILE_FORMAT = cms_dw.raw.cms_csv_format;

-- 6. Recreate the Raw Table inside cms_dw.raw
CREATE OR REPLACE TABLE cms_dw.raw.raw_partd_prescribers (
  Prscrbr_NPI VARCHAR,
  Prscrbr_Last_Org_Name VARCHAR,
  Prscrbr_First_Name VARCHAR,
  Prscrbr_City VARCHAR,
  Prscrbr_State_Abrvtn VARCHAR,
  Prscrbr_State_FIPS VARCHAR,
  Prscrbr_Type VARCHAR,
  Prscrbr_Type_Src VARCHAR,
  Brnd_Name VARCHAR,
  Gnrc_Name VARCHAR,
  Tot_Clms VARCHAR,
  Tot_30day_Fills VARCHAR,
  Tot_Day_Suply VARCHAR,
  Tot_Drug_Cst VARCHAR,
  Tot_Benes VARCHAR,
  GE65_Sprsn_Flag VARCHAR,
  GE65_Tot_Clms VARCHAR,
  GE65_Tot_30day_Fills VARCHAR,
  GE65_Tot_Drug_Cst VARCHAR,
  GE65_Tot_Day_Suply VARCHAR,
  GE65_Bene_Sprsn_Flag VARCHAR,
  GE65_Tot_Benes VARCHAR
);

-- 7. Execute the COPY INTO using absolute, fully-qualified paths
COPY INTO cms_dw.raw.raw_partd_prescribers
FROM @cms_dw.raw.gcs_cms_stage
FILE_FORMAT = (FORMAT_NAME = cms_dw.raw.cms_csv_format)
ON_ERROR = 'CONTINUE';




-- B. Validate if all data loaded correctly

SELECT COUNT(*) AS total_rows_loaded 
FROM cms_dw.raw.raw_partd_prescribers;

SELECT 
  Prscrbr_NPI, 
  Prscrbr_Last_Org_Name, 
  Prscrbr_First_Name, 
  Brnd_Name, 
  Tot_Clms, 
  Tot_Drug_Cst
FROM cms_dw.raw.raw_partd_prescribers
LIMIT 10;

SELECT
  COUNT(*) AS total_records,
  COUNT(Prscrbr_NPI) AS non_null_npis,
  COUNT(DISTINCT Prscrbr_NPI) AS unique_providers_loaded,
  (COUNT(*) - COUNT(Prscrbr_NPI)) AS null_npi_count
FROM cms_dw.raw.raw_partd_prescribers;

SELECT 
  FILE_NAME,
  STATUS,
  ROW_COUNT,
  ROW_PARSED,
  ERROR_COUNT
FROM TABLE(information_schema.copy_history(
  TABLE_NAME=>'cms_dw.raw.raw_partd_prescribers', 
  START_TIME=>DATEADD(hours, -2, CURRENT_TIMESTAMP())
));

