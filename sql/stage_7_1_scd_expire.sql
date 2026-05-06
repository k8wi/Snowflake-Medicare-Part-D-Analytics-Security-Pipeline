UPDATE cms_dw.analytics.dim_provider target
SET target.expiry_date = CURRENT_DATE() - 1, target.is_current = FALSE
FROM cms_dw.staging.stg_prescribers source
WHERE target.npi = source.npi
  AND target.is_current = TRUE
  AND (target.specialty <> source.specialty OR target.state <> source.state);