USE ROLE ACCOUNTADMIN;
USE DATABASE cms_dw;
USE SCHEMA analytics;

-- Create the Data Quality Log Table
CREATE OR REPLACE TABLE cms_dw.analytics.dq_results (
    check_name        VARCHAR,
    layer             VARCHAR,          -- 'raw', 'staging', 'fact'
    records_checked   NUMBER,
    records_failed    NUMBER,
    failure_rate_pct  NUMBER(5,2),
    status            VARCHAR,          -- 'PASS' / 'WARN' / 'FAIL'
    checked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Check 1: NULL NPI rate in staging (Validates provider identity integrity)
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'null_npi_rate'                             AS check_name,
    'staging'                                   AS layer,
    COUNT(*)                                    AS records_checked,
    SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) AS records_failed,
    ROUND(SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS failure_rate_pct,
    CASE WHEN SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) < 1 
         THEN 'PASS' ELSE 'FAIL' END            AS status,
    CURRENT_TIMESTAMP()
FROM cms_dw.staging.stg_prescribers;


-- Check 2: Negative drug costs (Financial audit checking for data corruption)
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'negative_drug_cost'    AS check_name,
    'fact'                  AS layer,
    COUNT(*)                AS records_checked,
    SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END) AS records_failed,
    ROUND(SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2) AS failure_rate_pct,
    CASE WHEN SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END) = 0 
         THEN 'PASS' ELSE 'FAIL' END AS status,
    CURRENT_TIMESTAMP()
FROM cms_dw.analytics.fct_claims;


-- Check 3: Raw-to-Staging Row Reconciliation (Validates complete data transit with no loss)
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'raw_to_staging_row_reconciliation'         AS check_name,
    'staging'                                   AS layer,
    (SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) AS records_checked,
    ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) 
      - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) AS records_failed,
    ROUND(ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) 
      - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) * 100.0 
      / NULLIF((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers), 0), 2) AS failure_rate_pct,
    CASE WHEN ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) 
                - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) < 1000 
         THEN 'PASS' ELSE 'WARN' END AS status,
    CURRENT_TIMESTAMP();

CREATE OR REPLACE VIEW cms_dw.analytics.v_dq_pipeline_scorecard AS
SELECT 
  check_name,
  layer,
  records_checked,
  records_failed,
  failure_rate_pct,
  status,
  checked_at
FROM cms_dw.analytics.dq_results
QUALIFY ROW_NUMBER() OVER (PARTITION BY check_name ORDER BY checked_at DESC) = 1;

SELECT * FROM cms_dw.analytics.v_dq_pipeline_scorecard;

