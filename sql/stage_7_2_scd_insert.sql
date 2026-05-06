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