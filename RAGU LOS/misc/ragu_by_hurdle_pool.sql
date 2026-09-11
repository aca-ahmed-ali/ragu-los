WITH base AS (
    SELECT
        ldcf.loan_id,
        ldcf.account_number,
        DATE_TRUNC('month', ldcf.application_received_dtm) AS app_month,

        ragu.gross_loss_ragu,
        ragu.recovery_multiplier,
        ragu.ltv,
        ragu.apr,
        ragu.amt_financed,

        CASE
            WHEN ldcf.dealer_pricing_hurdle = 'mROA-KMX'
                THEN CASE WHEN lrn.roa >= 500 THEN '1) Lower' ELSE '2) Higher' END
            WHEN ldcf.dealer_pricing_hurdle = 'mROA-FLD'
                THEN CASE WHEN COALESCE(lrn.maxltv, 0) > 750 THEN '1) Lower' ELSE '2) Higher' END
            WHEN ldcf.data_source_id = 101
                THEN CASE WHEN COALESCE(lrn.maxltv, 0) < 500 THEN '2) Higher' ELSE '1) Lower' END
            WHEN COALESCE(lrn.maxltv, 0) < 500
                OR (COALESCE(lrn.maxltv, 0) < 850
                    AND ldcf.dealer_pricing_hurdle = 'mROA-MCY'
                    AND ldcf.application_received_dtm >= '2024-06-19')
                THEN '2) Higher'
            ELSE '1) Lower'
        END AS hurdle


    FROM los_deal_current_fact ldcf

    LEFT JOIN sandbox.loan_random_numbers lrn
        ON lrn.loan_id = ldcf.loan_id

    LEFT JOIN sandbox.gl_ragu_individual ragu
        ON ragu.account_number = ldcf.account_number

    WHERE ldcf.application_received_dtm >= '2025-01-01'
      AND aspect = 'CONTRACT'
      AND lob = '{lob}'
),

weighted_avgs AS (
    SELECT
        app_month,
        hurdle,
        COUNT(*)                                          AS loan_count,
        SUM(amt_financed)                                AS total_amt_financed,

        SUM(gross_loss_ragu * amt_financed)
            / NULLIF(SUM(amt_financed), 0)               AS wavg_gross_loss_ragu,

        SUM(CASE WHEN recovery_multiplier IS NOT NULL
                 THEN recovery_multiplier * amt_financed END)
            / NULLIF(SUM(CASE WHEN recovery_multiplier IS NOT NULL
                              THEN amt_financed END), 0) AS wavg_recovery_multiplier,

        SUM(CASE WHEN ltv IS NOT NULL
                 THEN ltv * amt_financed END)
            / NULLIF(SUM(CASE WHEN ltv IS NOT NULL
                              THEN amt_financed END), 0) AS wavg_ltv,

        SUM(apr * amt_financed)
            / NULLIF(SUM(amt_financed), 0)               AS wavg_apr

    FROM base
    GROUP BY app_month, hurdle
)

SELECT
    app_month,
    hurdle,
    loan_count,
    total_amt_financed,

    wavg_gross_loss_ragu,
    wavg_recovery_multiplier,
    wavg_ltv,
    wavg_apr,

    wavg_gross_loss_ragu * 0.5 * wavg_recovery_multiplier
        * (wavg_recovery_multiplier / 0.58 - 1.0)       AS recovery_impact,

    (1.59 / NULLIF(wavg_ltv, 0) - 1.0) * (17.0 / 0.65) AS ltv_impact,

    (0.25 - wavg_apr) / 0.01 * (0.7 / 0.65)             AS apr_impact,

    wavg_gross_loss_ragu
        + wavg_gross_loss_ragu * 0.5 * wavg_recovery_multiplier
            * (wavg_recovery_multiplier / 0.58 - 1.0)
        + (1.59 / NULLIF(wavg_ltv, 0) - 1.0) * (17.0 / 0.65)
        + (0.25 - wavg_apr) / 0.01 * (0.7 / 0.65)       AS ragu_score

FROM weighted_avgs
ORDER BY app_month, hurdle;
