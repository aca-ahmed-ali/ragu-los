SELECT pricing_hurdle_name,
       DATE_PART('year', rh.reqappdate) AS year,
       DATE_PART('month', rh.reqappdate) AS month,
       MIN(rh.reqappdate) AS first_date,
       COUNT(DISTINCT CASE WHEN aspect = 'APPLICATION' THEN loan_id END) AS apps,
       COUNT(DISTINCT CASE WHEN aspect = 'CONTRACT' THEN loan_id END) AS cons,
       AVG(CASE WHEN aspect = 'APPLICATION' THEN rehashed * 1.0000 END) AS app_rehash_rate,
       AVG(CASE WHEN aspect = 'CONTRACT' THEN rehashed * 1.0000 END) AS con_rehash_rate
FROM edwnpi.crm_dealer_dim cdd
LEFT JOIN edwnpi.los_deal_current_fact lcdf ON cdd.dealer_number = lcdf.dealer_number
LEFT JOIN sandbox.rehashes rh ON lcdf.loan_id = rh.appid
WHERE cdd.current_version_flag = 1
  AND lcdf.application_received_dtm >= '2025-05-01'
  AND acall_amtfin IS NOT NULL
  AND pricing_hurdle_name IS NOT NULL
  AND pricing_hurdle_name != 'mROA-KMX'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
