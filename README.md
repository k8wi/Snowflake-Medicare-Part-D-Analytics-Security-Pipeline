# Enterprise Medicare Part D Analytics & Security Pipeline (26.7M Rows)

An end-to-end, enterprise-grade ELT (Extract, Load, Transform) data pipeline designed to ingest, cleanse, model, audit, and secure **26,794,878 rows** of raw public healthcare data from the Centers for Medicare & Medicaid Services (CMS). 

This pipeline represents a highly optimized, HIPAA-compliant Star Schema built in Snowflake, sourced from Google Cloud Storage (GCS). It showcases advanced data engineering capabilities including **Slowly Changing Dimensions (SCD) Type 2**, **Dynamic Data Masking for PHI/PII**, and automated **Data Quality & Reconciliation** logging.

---

## 1. Cloud Architecture & Data Flow

The architecture operates under a strict separation of concerns, transitioning raw data securely across schemas while isolating compute and storage resources.

```
[ GCS Bucket ]
      │ (Secure Storage Integration / IAM-based trust)
      ▼
[ Snowflake Stage (External Stage) ]
      │
      ▼  (Stage 1: Raw Ingestion via COPY INTO)
[ cms_dw.raw.raw_partd_prescribers ] (All VARCHAR landing)
      │
      ▼  (Stage 2: Staging Layer with TRY_CAST data cleansing)
 ┌────┴────────────────────────┐
 ▼                             ▼
[ stg_prescribers ]      [ stg_drug_claims ]
 └────┬────────────────────────┬┘
      │                        │
      ▼                        ▼ (Stage 3: SCD Type 2 Merge Pipeline)
 ┌────────────────────────────────────────────────────────┐
 ▼                                                        ▼
[ dim_provider ]  ◀─────── [ fct_claims ] ───────▶  [ dim_drug ]
 (SCD Type 2)              (Clustered Table)
      │                            │
      ▼ (Dynamic Masking)          ▼
[ Secure Reporting Views ] ◀───────┘
      │
      ├─► [ v_dq_pipeline_scorecard ] (Continuous Data Quality Audit)
      └─► [ Analytical Business Insights Views ]
```

---

## 2. Advanced Enterprise Implementations

### A. Data Quality & Reconciliation Layer (UAT Audit Framework)
To prevent downstream reporting corruption, this pipeline features an active auditing framework that logs diagnostic assertions into a `dq_results` audit table. A dynamic scorecard view queries the latest execution pass to confirm pipeline health.

* **Reconciliation Checks:**
  1. **NPI Null-Rate Check:** Verifies provider identity completeness in staging.
  2. **Negative Cost Check:** Financial check ensuring no corrupt negative drug costs enter the analytical layer.
  3. **Raw-to-Staging Volume Audit:** Reconciles files processed vs. staging records loaded to capture any ingestion-stage data loss.

### B. HIPAA Compliance & Dynamic Data Masking (PHI/PII Protection)
Provider names in large-scale drug transaction pipelines are treated as Protected Health Information (PHI). 
* **Dynamic Masking Policy:** Built a reusable masking policy (`phi_name_mask`) using Role-Based Access Control (RBAC).
* **Security Enforcement:** Users with the `ACCOUNTADMIN` or `DATA_ENGINEER` roles see unmasked provider names. When users in the restricted `analyst_restricted` role query the exact same table, the column dynamically redacts content to `***[REDACTED PHI - HIPAA MASKED]***` on-the-fly without altering physical storage.

### C. Slowly Changing Dimensions (SCD) Type 2
Physicians change states, change practices, or specialize over time. A static warehouse snapshot fails to preserve transaction history accurately.
* **History Ledger:** Rebuilt `dim_provider` with system-managed Surrogate Keys (`provider_key`), effective/expiration timestamps, and active record flags (`is_current`).
* **Transactional Pipeline:** Implemented an ACID-compliant transaction block that gracefully deactivates expired provider states (setting `is_current = FALSE` and `expiry_date` to yesterday) and inserts the newly updated active records, guaranteeing robust longitudinal tracking.

---

## 3. Step-by-Step SQL Script Playbook

### Stage 1: Infrastructure & Raw Ingestion

```sql
-- 1.1 Secure Storage Integration (Cross-Cloud Trust)
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE OR REPLACE STORAGE INTEGRATION gcs_cms_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'GCS'
  ENABLED = TRUE
  STORAGE_ALLOWED_LOCATIONS = ('gcs://cms-partd-data-demo/');

-- Retrieve the generated service account email to grant Storage Object Viewer in GCP
DESC STORAGE INTEGRATION gcs_cms_integration;

-- 1.2 Schema and Folder Framework
CREATE DATABASE IF NOT EXISTS cms_dw;
CREATE SCHEMA IF NOT EXISTS cms_dw.raw;
USE DATABASE cms_dw;
USE SCHEMA raw;

-- 1.3 Create CSV File Format
CREATE OR REPLACE FILE FORMAT cms_dw.raw.cms_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE;

-- 1.4 Create External Stage Pointer
CREATE OR REPLACE STAGE cms_dw.raw.gcs_cms_stage
  URL = 'gcs://cms-partd-data-demo/'
  STORAGE_INTEGRATION = gcs_cms_integration
  FILE_FORMAT = cms_dw.raw.cms_csv_format;

-- 1.5 Target Raw Landing Table
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

-- 1.6 Execute Ingestion
COPY INTO cms_dw.raw.raw_partd_prescribers
FROM @cms_dw.raw.gcs_cms_stage
FILE_FORMAT = (FORMAT_NAME = cms_dw.raw.cms_csv_format)
ON_ERROR = 'CONTINUE';
```

---

### Stage 2: Staging & Cleanse (Handling suppression flags with TRY_CAST)

```sql
CREATE SCHEMA IF NOT EXISTS cms_dw.staging;
USE SCHEMA cms_dw.staging;

-- 2.1 Staging Providers (Trimming and casing)
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

-- 2.2 Staging Claims (Converting suppressed asterisk data '*' safely to NULL)
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
```

---

### Stage 3: Dimensional Modeling (Star Schema & SCD Type 2 Foundation)

```sql
CREATE SCHEMA IF NOT EXISTS cms_dw.analytics;
USE SCHEMA cms_dw.analytics;

-- 3.1 Dimension: Providers (With SCD Type 2 tracking structures)
CREATE OR REPLACE TABLE cms_dw.analytics.dim_provider (
    provider_key     INT IDENTITY(1,1) PRIMARY KEY,
    npi              INT,
    provider_name    VARCHAR,
    specialty        VARCHAR,
    state            VARCHAR,
    effective_date   DATE DEFAULT CURRENT_DATE(),
    expiry_date      DATE DEFAULT '9999-12-31'::DATE,
    is_current       BOOLEAN DEFAULT TRUE
);

-- Seed Initial Dimension State
INSERT INTO cms_dw.analytics.dim_provider (npi, provider_name, specialty, state)
SELECT 
  npi, 
  CONCAT_WS(', ', last_name, first_name) AS provider_name,
  specialty,
  state
FROM cms_dw.staging.stg_prescribers;

-- 3.2 Dimension: Drugs (Surrogate Key generation)
CREATE OR REPLACE TABLE cms_dw.analytics.dim_drug (
  drug_key INT IDENTITY(1,1),
  drug_name VARCHAR,
  generic_name VARCHAR,
  is_generic VARCHAR(1)
);

INSERT INTO cms_dw.analytics.dim_drug (drug_name, generic_name, is_generic)
SELECT DISTINCT 
  drug_name, 
  generic_name,
  CASE WHEN drug_name = generic_name THEN 'Y' ELSE 'N' END AS is_generic
FROM cms_dw.staging.stg_drug_claims;

-- 3.3 Central Fact Table: Claims (Optimized with denormalized filtering keys)
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
  ON c.npi = p.npi 
  AND p.is_current = TRUE; -- Link transactions to the active provider dimension record
```

---

### Stage 4: Advanced Analytical SQL Layer

```sql
USE SCHEMA cms_dw.analytics;

-- 4.1 Top 10 Prescribers per State (Window Ranking)
CREATE OR REPLACE VIEW cms_dw.analytics.v_top_10_prescribers_by_state AS
WITH ranked_spend AS (
  SELECT 
    p.state,
    p.provider_name,
    p.specialty,
    SUM(f.total_drug_cost) AS total_spend,
    DENSE_RANK() OVER (PARTITION BY p.state ORDER BY SUM(f.total_drug_cost) DESC) as spend_rank
  FROM cms_dw.analytics.fct_claims f
  JOIN cms_dw.analytics.dim_provider p ON f.npi = p.npi AND p.is_current = TRUE
  GROUP BY p.state, p.provider_name, p.specialty
)
SELECT * FROM ranked_spend WHERE spend_rank <= 10;

-- 4.2 Specialty Brand-to-Generic Ratio (Conditional Aggregations)
CREATE OR REPLACE VIEW cms_dw.analytics.v_specialty_brand_ratios AS
SELECT 
  f.specialty,
  SUM(CASE WHEN d.is_generic = 'N' THEN f.claim_count ELSE 0 END) AS brand_claims,
  SUM(CASE WHEN d.is_generic = 'Y' THEN f.claim_count ELSE 0 END) AS generic_claims,
  ROUND(brand_claims / NULLIF(brand_claims + generic_claims, 0), 4) AS brand_ratio
FROM cms_dw.analytics.fct_claims f
JOIN cms_dw.analytics.dim_drug d ON f.drug_key = d.drug_key
GROUP BY f.specialty;

-- 4.3 Year-over-Year Drug Volumes (Offset Lag Analyticals)
CREATE OR REPLACE VIEW cms_dw.analytics.v_yoy_drug_volume AS
WITH yearly_agg AS (
  SELECT 
    d.drug_name,
    f.reporting_year,
    SUM(f.claim_count) AS total_claims
  FROM fct_claims f
  JOIN dim_drug d ON f.drug_key = d.drug_key
  GROUP BY d.drug_name, f.reporting_year
)
SELECT 
  drug_name,
  reporting_year,
  total_claims,
  LAG(total_claims) OVER (PARTITION BY drug_name ORDER BY reporting_year) as previous_year_claims,
  ROUND(((total_claims - previous_year_claims) / NULLIF(previous_year_claims, 0)) * 100, 2) AS yoy_pct_change
FROM yearly_agg;
```

---

### Stage 5: Data Quality Logging & Reconciliation

```sql
-- 5.1 Create Logging Schema
CREATE OR REPLACE TABLE cms_dw.analytics.dq_results (
    check_name        VARCHAR,
    layer             VARCHAR,
    records_checked   NUMBER,
    records_failed    NUMBER,
    failure_rate_pct  NUMBER(5,2),
    status            VARCHAR,
    checked_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Check A: Staging NPI Null-Rates
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'null_npi_rate', 'staging', COUNT(*),
    SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2),
    CASE WHEN SUM(CASE WHEN npi IS NULL THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) < 1 THEN 'PASS' ELSE 'FAIL' END,
    CURRENT_TIMESTAMP()
FROM cms_dw.staging.stg_prescribers;

-- Check B: Negative Cost Outliers
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'negative_drug_cost', 'fact', COUNT(*),
    SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0), 2),
    CASE WHEN SUM(CASE WHEN total_drug_cost < 0 THEN 1 ELSE 0 END) = 0 THEN 'PASS' ELSE 'FAIL' END,
    CURRENT_TIMESTAMP()
FROM cms_dw.analytics.fct_claims;

-- Check C: Raw-to-Staging Volume Reconciliation
INSERT INTO cms_dw.analytics.dq_results
SELECT
    'raw_to_staging_row_reconciliation', 'staging',
    (SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers),
    ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)),
    ROUND(ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) * 100.0 
      / NULLIF((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers), 0), 2),
    CASE WHEN ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) < 1000 THEN 'PASS' ELSE 'WARN' END,
    CURRENT_TIMESTAMP();

-- 5.2 Dynamic DQ Performance Scorecard
CREATE OR REPLACE VIEW cms_dw.analytics.v_dq_pipeline_scorecard AS
SELECT check_name, layer, records_checked, records_failed, failure_rate_pct, status, checked_at
FROM cms_dw.analytics.dq_results
QUALIFY ROW_NUMBER() OVER (PARTITION BY check_name ORDER BY checked_at DESC) = 1;
```

---

### Stage 6: Security Enforcement & HIPAA Dynamic Masking

```sql
-- 6.1 Define HIPAA Masking Policy
CREATE OR REPLACE MASKING POLICY cms_dw.analytics.phi_name_mask AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER') THEN val
    ELSE '***[REDACTED PHI - HIPAA MASKED]***'
  END;

-- 6.2 Bind Policy to Provider Name Column
ALTER TABLE cms_dw.analytics.dim_provider 
  MODIFY COLUMN provider_name 
  SET MASKING POLICY cms_dw.analytics.phi_name_mask;

-- 6.3 Secure Role-Based Access Control Setup
CREATE ROLE IF NOT EXISTS analyst_restricted;
GRANT USAGE ON DATABASE cms_dw TO ROLE analyst_restricted;
GRANT USAGE ON SCHEMA cms_dw.analytics TO ROLE analyst_restricted;
GRANT SELECT ON TABLE cms_dw.analytics.dim_provider TO ROLE analyst_restricted;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE analyst_restricted;
```

---

### Stage 7: SCD Type 2 Transaction Pipeline

```sql
-- Explicit SCD Type 2 ACID Transaction Block
BEGIN TRANSACTION;

  -- A. Expire outdated records when staging attributes change
  UPDATE cms_dw.analytics.dim_provider target
  SET 
    target.expiry_date = CURRENT_DATE() - 1,
    target.is_current = FALSE
  FROM cms_dw.staging.stg_prescribers source
  WHERE target.npi = source.npi
    AND target.is_current = TRUE
    AND (target.specialty <> source.specialty OR target.state <> source.state);

  -- B. Insert new active tracking records
  INSERT INTO cms_dw.analytics.dim_provider (npi, provider_name, specialty, state, effective_date, expiry_date, is_current)
  SELECT 
    source.npi,
    CONCAT_WS(', ', source.last_name, source.first_name) AS provider_name,
    source.specialty,
    source.state,
    CURRENT_DATE() AS effective_date,
    '9999-12-31'::DATE AS expiry_date,
    TRUE AS is_current
  FROM cms_dw.staging.stg_prescribers source
  LEFT JOIN cms_dw.analytics.dim_provider target
    ON source.npi = target.npi AND target.is_current = TRUE
  WHERE target.npi IS NULL;

COMMIT;
```

---

### Stage 8: Physical Table Clustering & Performance Optimization

```sql
-- 8.1 Establish Unclustered Evaluation Run
SELECT state, specialty, SUM(total_drug_cost) AS total_cost, SUM(claim_count) AS total_claims
FROM cms_dw.analytics.fct_claims
WHERE state = 'NY' AND specialty = 'Internal Medicine'
GROUP BY state, specialty;

-- Observe execution profile in Query History (scans 100% of micro-partitions)

-- 8.2 Organize micro-partitions on disk by key query filters
ALTER TABLE cms_dw.analytics.fct_claims CLUSTER BY (state, specialty);

-- 8.3 Evaluate Post-Clustering Run (Forcing cache-bypass)
SELECT state, specialty, SUM(total_drug_cost) AS total_cost, SUM(claim_count) AS total_claims
FROM cms_dw.analytics.fct_claims
WHERE state = 'NY' AND specialty = 'Internal Medicine' AND reporting_year = 2026
GROUP BY state, specialty;

-- Verify Partition Pruning (micro-partitions scanned falls under 5%)
```

---

## 4. Key Takeaways 

* **How did you handle the * suppressed records?**
  * Used `TRY_CAST` to gracefully convert `*` privacy-masked values to `NULL` before using `COALESCE` to default them to `0`. This keeps the ingestion engine running without throwing structural mismatch exceptions.
* **Why did you denormalize State and Specialty into the Fact Table?**
  * Denormalizing high-frequency search and query filters directly into the central fact table avoids expensive dimensional cross-join tables in modern analytical cloud platforms. This directly enables physical table clustering, which drastically speeds up query performance via targeted partition pruning.
* **Why use Explicit Transactions for SCD Type 2 instead of a standard MERGE?**
  * A standard multi-branch `MERGE` statement can become very slow on large tables with millions of rows. Splitting the logic into explicit transactional operations (an index-driven `UPDATE` to expire records, followed by a set-based `INSERT` for new records) runs much faster and scales linearly.