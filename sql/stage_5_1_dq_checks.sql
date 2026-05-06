INSERT INTO cms_dw.analytics.dq_results
SELECT
    'raw_to_staging_row_reconciliation', 'staging',
    (SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers),
    ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)),
    ROUND(ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) * 100.0 / NULLIF((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers), 0), 2),
    CASE WHEN ABS((SELECT COUNT(*) FROM cms_dw.raw.raw_partd_prescribers) - (SELECT COUNT(*) FROM cms_dw.staging.stg_drug_claims)) < 1000 THEN 'PASS' ELSE 'WARN' END,
    CURRENT_TIMESTAMP();