-- Temp table: first app/contract processing timestamps per loan
SELECT loan_id,
       MIN(CASE WHEN function_name = 'workflow_pre_bureau_calculate' THEN created_utc_dtm END) AS first_app_processing,
       MIN(CASE WHEN function_name = 'workflow_calculate_contract' THEN created_utc_dtm END) AS first_contract_processing
INTO #time_received
FROM odsnpi.pricing_service_log psl
WHERE function_name IN ('workflow_pre_bureau_calculate', 'workflow_calculate_contract')
GROUP BY 1;

-- Conversion by LOB (weekly cohorts)
SELECT ldcf.dealer_pricing_hurdle,
       FLOOR(DATE_DIFF('day', first_app_processing, SYSDATE) / 7) AS w,
       MIN(first_app_processing::DATE) AS first_day,
       COUNT(DISTINCT tr.loan_id) AS apps,
       COUNT(CASE WHEN DATEDIFF('day', first_app_processing, first_contract_processing) <= 7 THEN tr.loan_id END) AS first_week_cons,
       COUNT(CASE WHEN first_contract_processing IS NOT NULL THEN tr.loan_id END) AS contracts,
       first_week_cons * 1.000 / apps AS first_week_conversion,
       contracts * 1.000 / apps AS conversion
FROM #time_received tr
LEFT JOIN edwnpi.los_deal_current_fact ldcf
    ON ldcf.loan_id = tr.loan_id AND ldcf.aspect = 'APPLICATION'
WHERE tr.first_app_processing >= '2025-06-01'
  AND dealer_pricing_hurdle IN ('mROA-AN', 'mROA-ENT', 'mROA-FLD', 'mROA-FRN', 'mROA-KMX', 'mROA-MCY', 'mROA-STG')
  AND DATEDIFF('day', first_app_processing, SYSDATE) >= 7
GROUP BY 1, 2
ORDER BY 1, 2;
