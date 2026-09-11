SELECT pricing_hurdle_name,
       DATE_PART('year', rh.reqappdate) AS year,
       DATE_PART('month', rh.reqappdate) AS month,
       MIN(rh.reqappdate) AS first_date,
       COUNT(DISTINCT CASE WHEN aspect = 'APPLICATION' THEN loan_id END) AS apps,
       COUNT(DISTINCT CASE WHEN aspect = 'CONTRACT' THEN loan_id END) AS cons,
       SUM(booked) AS booked_cons,
       AVG(CASE WHEN aspect = 'APPLICATION' THEN CASE WHEN ABS(COALESCE(bcall_amtfin, acall_amtfin) - lcdf.adj_amount_financed_front) <= 250 THEN 1.0000 ELSE 0.0000 END END) AS full_call,
       COUNT(DISTINCT CASE WHEN aspect = 'CONTRACT' THEN loan_id END) * 1.0000
           / NULLIF(COUNT(DISTINCT CASE WHEN aspect = 'APPLICATION' THEN loan_id END), 0) AS b2l,
       AVG(rehashed * 1.0000) AS app_rehash_rate,
       AVG(CASE WHEN aspect = 'APPLICATION' THEN CASE WHEN COALESCE(bcall_discount_dollars, acall_discount_dollars) <= 2500 AND ABS(COALESCE(bcall_amtfin, acall_amtfin) - lcdf.adj_amount_financed_front) <= 250 THEN 1.0000 ELSE 0.0000 END END) AS low_disc_frac,
       SUM(CASE WHEN aspect = 'APPLICATION' THEN CASE WHEN COALESCE(bcall_discount_dollars, acall_discount_dollars) <= 2500 AND ABS(COALESCE(bcall_amtfin, acall_amtfin) - lcdf.adj_amount_financed_front) <= 250 THEN 1.0000 ELSE 0.0000 END END) AS low_disc_count,
       AVG(active_apr) AS avg_apr
FROM edwnpi.crm_dealer_dim cdd
LEFT JOIN edwnpi.los_deal_current_fact lcdf ON cdd.dealer_number = lcdf.dealer_number
LEFT JOIN sandbox.rehashes rh ON lcdf.loan_id = rh.appid
WHERE cdd.current_version_flag = 1
  AND lcdf.application_received_dtm >= '2024-01-01'
  AND acall_amtfin IS NOT NULL
  AND pricing_hurdle_name IS NOT NULL
  AND pricing_hurdle_name != 'mROA-KMX'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
