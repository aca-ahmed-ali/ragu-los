WITH ranked_decision_prov AS (
    SELECT
        prov.dealdetailid AS deal_detail_id,
        prov.decisioncd AS decision,
        ROW_NUMBER() OVER (PARTITION BY prov.dealdetailid ORDER BY prov.decisionid ASC) AS decision_row_number_front,
        ROW_NUMBER() OVER (PARTITION BY prov.dealdetailid ORDER BY prov.decisionid DESC) AS decision_row_number_back
    FROM odsnpi.prov_loan_decisions prov
    WHERE prov.datasourceid = 17 AND prov.decisioncd != 'I'
),
ranked_decision_los AS (
    SELECT
        los_decision.deal_detail_id,
        los_decision.status_name AS decision,
        ROW_NUMBER() OVER (PARTITION BY los_decision.deal_detail_id ORDER BY los_decision.deal_status_id ASC) AS decision_row_number_front,
        ROW_NUMBER() OVER (PARTITION BY los_decision.deal_detail_id ORDER BY los_decision.deal_status_id DESC) AS decision_row_number_back
    FROM odsnpi.los_deal_status_scd los_decision
    WHERE los_decision.current_version_flag = 1 AND los_decision.status_name != 'Expired'
),
deal_detail_list AS (
    SELECT
        los.los_deal_current_fact_universal_id AS deal_detail_id,
        los.data_source_id
    FROM edwnpi.los_deal_current_fact los
    INNER JOIN edwnpi.dealer_rollup_scd_current dru_ddl
        ON dru_ddl.dealer_number = los.dealer_number
    WHERE los.data_source_id IN (17, 100)
      AND los.aspect = 'APPLICATION'
      AND dru_ddl.riskdealergroup NOT IN ('KMX')
      AND los.application_received_date BETWEEN '2024-01-01' AND CURRENT_DATE
),
decision AS (
    SELECT
        ddl.deal_detail_id,
        ddl.data_source_id,
        MAX(CASE WHEN rdp.decision_row_number_front = 1 THEN rdp.decision
                 WHEN rdl.decision_row_number_front = 1 THEN rdl.decision END) AS first_decision,
        MAX(CASE WHEN rdp.decision_row_number_back = 1 THEN rdp.decision
                 WHEN rdl.decision_row_number_back = 1 THEN rdl.decision END) AS last_decision
    FROM deal_detail_list ddl
    LEFT JOIN ranked_decision_prov rdp ON ddl.deal_detail_id = rdp.deal_detail_id AND ddl.data_source_id = 17
    LEFT JOIN ranked_decision_los rdl ON ddl.deal_detail_id = rdl.deal_detail_id AND ddl.data_source_id = 100
    GROUP BY ddl.deal_detail_id, ddl.data_source_id
),
base AS (
    SELECT
        DATE_TRUNC('week', ldcf.application_received_date) AS week_start,
        dru.riskdealergroup AS lob,
        CASE
            WHEN rh.acall_amtfin - ldcf.req_amount_financed_front BETWEEN -250 AND 250
                AND dec.first_decision IN ('L', 'LC', 'Approved', 'Conditional Approval')
                THEN 1
            ELSE 0
        END AS sa_flag,
        CASE
            WHEN (
                    (rh.acall_discount_dollars <= 2500
                        AND ABS(rh.acall_amtfin - ldcf.adj_amount_financed_front) <= 250)
                    OR (rh.bcall_discount_dollars <= 2500
                        AND ABS(rh.bcall_amtfin - ldcf.adj_amount_financed_front) <= 250)
                 )
                AND dec.last_decision NOT IN ('G', 'T', 'FT', 'Declined', 'Final Turndown')
                THEN 1
            ELSE 0
        END AS full_call_flag,
        CASE WHEN ldcf.status_name = 'FUNDED' THEN 1 ELSE 0 END AS funded_flag
    FROM edwnpi.los_deal_current_fact ldcf
    INNER JOIN edwnpi.dealer_rollup_scd_current dru
        ON dru.dealer_number = ldcf.dealer_number
    LEFT JOIN sandbox.rehashes rh ON ldcf.loan_id = rh.appid
    LEFT JOIN decision dec ON ldcf.los_deal_current_fact_universal_id = dec.deal_detail_id
    WHERE ldcf.deal_deleted_flag = 0
      AND ldcf.data_source_id = 100
      AND dru.riskdealergroup NOT IN ('KMX')
      AND (ldcf.status_name = 'FUNDED' OR ldcf.aspect = 'APPLICATION')
      AND ldcf.application_received_date BETWEEN '2024-01-01' AND
          CASE WHEN ldcf.aspect = 'APPLICATION'
               THEN DATEADD(DAY, -14, CURRENT_DATE)
               ELSE CURRENT_DATE END
)
SELECT
    week_start,
    lob,
    COUNT(*) AS total_apps,
    AVG(full_call_flag * 1.0) AS full_call_rate,
    AVG(sa_flag * 1.0) AS sa_rate,
    SUM(funded_flag) * 1.0 / NULLIF(SUM(full_call_flag), 0) AS conversion_rate
FROM base
GROUP BY 1, 2
ORDER BY 1, 2;
