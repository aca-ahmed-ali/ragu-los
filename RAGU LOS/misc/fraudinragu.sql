drop table if exists acaedw.sandbox.fraud_data_gs;
SELECT loan_id,
       ldcf.account_number,
       --pd.value                                                                                        as Dealer_Loss_Bucket,
        dru.riskdealergroup,
       ldcf.dealer_pricing_hurdle,
       ldcf.book_date,
       date_trunc('MONTH', contract_signed_dtm)::date                                                  as book_month,
       --apppdsm.modelvalue::int                                                                         as aca_model_score,
       --ldcf.con_apr,
       --ldcf.con_term,
       --re.base_model_score,
       fd.pb_sentilink_first_party_synthetic_score as sentilink_score,
       case when (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then fd.afm_score else -100 end as pp_score,
--        case
--            when fd.pb_sentilink_first_party_synthetic_score between 1 and 100 then '1-100'
--            when fd.pb_sentilink_first_party_synthetic_score between 101 and 200 then '101-200'
--            when fd.pb_sentilink_first_party_synthetic_score between 201 and 300 then '201-300'
--            when fd.pb_sentilink_first_party_synthetic_score between 301 and 400 then '301-400'
--            when fd.pb_sentilink_first_party_synthetic_score between 401 and 500 then '401-500'
--            when fd.pb_sentilink_first_party_synthetic_score between 501 and 600 then '501-600'
--            when fd.pb_sentilink_first_party_synthetic_score between 601 and 700 then '601-700'
--            when fd.pb_sentilink_first_party_synthetic_score between 701 and 800 then '701-800'
--            when fd.pb_sentilink_first_party_synthetic_score between 801 and 900 then '801-900'
--            when fd.pb_sentilink_first_party_synthetic_score between 901 and 999
--                then '901-999' end                                                                      as Sentilink_Bucket,
       fd.afm_score,
--        case
--            when fd.afm_score between 1 and 100 then '1-100'
--            when fd.afm_score between 101 and 200 then '101-200'
--            when fd.afm_score between 201 and 300 then '201-300'
--            when fd.afm_score between 301 and 400 then '301-400'
--            when fd.afm_score between 401 and 500 then '401-500'
--            when fd.afm_score between 501 and 600 then '501-600'
--            when fd.afm_score between 601 and 700 then '601-700'
--            when fd.afm_score between 701 and 800 then '701-800'
--            when fd.afm_score between 801 and 900 then '801-900'
--            when fd.afm_score between 901 and 998 then '901-998'
--            when fd.afm_score = 999 then '999' end                                                      as AFM_Bucket,
       fd.reason_code_1,
       fd.reason_code_2,
       fd.reason_code_3,
       fd.dms_syntheticfraudflag,
       case
           when (fd.afm_score >= 900 and
                 (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                  reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                  reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67))) then 1
           else 0 end                                                                                  as sff_afm,
       case when fd.pb_sentilink_first_party_synthetic_score >= 840 then 1 else 0 end                  as sff_sl,
       case when fd.dms_syntheticfraudflag >= 4 then 1 else 0 end                                      as sff_internal,
       case
           when ((fd.afm_score >= 900 and
                  (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                   reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                   reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)))
               or fd.pb_sentilink_first_party_synthetic_score >= 840
               or fd.dms_syntheticfraudflag >= 4) then 1
           else 0 end                                                                                  as SFF,
       case
           when (afm_score > 700 or pb_sentilink_first_party_synthetic_score > 700) then 1
           else 0 end                                                                                  as High_Fraud_Flag,
       case
           when (afm_score > 700 or pb_sentilink_first_party_synthetic_score > 700) and not (fd.afm_score >= 900 and
                                                                                             (reason_code_1 in
                                                                                              (8, 13, 17, 31, 32, 35,
                                                                                               50, 55, 59, 60, 61, 62,
                                                                                               63, 64, 65, 66, 67) or
                                                                                              reason_code_2 in
                                                                                              (8, 13, 17, 31, 32, 35,
                                                                                               50, 55, 59, 60, 61, 62,
                                                                                               63, 64, 65, 66, 67) or
                                                                                              reason_code_3 in
                                                                                              (8, 13, 17, 31, 32, 35,
                                                                                               50, 55, 59, 60, 61, 62,
                                                                                               63, 64, 65, 66, 67))) and
                not (fd.pb_sentilink_first_party_synthetic_score >= 840) then 1
           else 0 end                                                                                  as Remaining_High_Fraud_Flag,
       case --when (pb_sentilink_first_party_synthetic_score > 750 and pb_sentilink_first_party_synthetic_score < 840) and
       --not (fd.afm_score >= 900 and (reason_code_1 in(8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or reason_code_2 in(8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or reason_code_3 in(8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)))
       --then 1 else 0 end as SFF_Expansion,
           when (fd.afm_score >= 750 and fd.afm_score < 900 and
                 (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                  reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                  reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67))) and
                not (pb_sentilink_first_party_synthetic_score > 840)
               then 1
           else 0 end                                                                                  as SFF_Expansion,
       case
           when pb_sentilink_first_party_synthetic_score between 950 and 999 then '950-999'
           when pb_sentilink_first_party_synthetic_score between 900 and 950 then '900-950'
           when pb_sentilink_first_party_synthetic_score between 840 and 900 then '840-900'
           when pb_sentilink_first_party_synthetic_score between 800 and 840 then '800-840'
           when pb_sentilink_first_party_synthetic_score between 750 and 800 then '750-800'
           when pb_sentilink_first_party_synthetic_score between 700 and 750 then '700-750'
           when pb_sentilink_first_party_synthetic_score between 650 and 700 then '650-700'
           when pb_sentilink_first_party_synthetic_score between 600 and 650 then '600-650'
           else 'err' end                                                                              as SENTpopulations,
       case
           when afm_score = 999 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '999'
           when afm_score between 950 and 998 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '950-998'
           when afm_score between 900 and 950 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '900-950'
           when afm_score between 850 and 900 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '850-900'
           when afm_score between 800 and 850 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '800-850'
           when afm_score between 750 and 800 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '750-800'
           when afm_score between 700 and 750 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '700-750'
           when afm_score between 650 and 700 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '650-700'
           when afm_score between 600 and 650 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '600-650'
           when afm_score between 550 and 600 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '550-600'
           when afm_score between 500 and 550 and
                (reason_code_1 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_2 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67) or
                 reason_code_3 in (8, 13, 17, 31, 32, 35, 50, 55, 59, 60, 61, 62, 63, 64, 65, 66, 67)) then '500-550'
           else 'err' end                                                                              as PPpopulations,
       --datediff('MONTH', ldcf.book_date, smm.snapshot_date)                                            as MOB,
       --case when smm.days_past_due_3059 > 0 then 1 else 0 end                                          as ever30DPD,
       --case when smm.days_past_due_6089 > 0 then 1 else 0 end                                          as ever60DPD,
       --case when smm.charge_off_date notnull then 1 else 0 end                                         as chargeoff_flag,
       --case when smm2.charge_off_date notnull then 1 else 0 end                                        as chargeoff_6MOB_flag,
       ldcf.con_amount_financed_back
       --smm.gross_loss_amt,
       --smm.net_loss_amt,
       --smm.never_paid_flag::int,
       --case when smm.auction_sold_date notnull then 1 else 0 end                                       as recovered,
       --smm.recovery_total_received_amt
into sandbox.fraud_data_gs
from acaedw.edwnpi.los_deal_current_fact as ldcf
         left join acaedw.sandbox.pos_fraud_data as fd on fd.application_id = ldcf.loan_id
         --left join acaedw.edwnpi.svc_master_monthend as smm on smm.account_number = ldcf.account_number
         --left join acaedw.edwnpi.svc_master_monthend as smm2
           --        on smm2.account_number = ldcf.account_number and smm2.number_of_months_booked = 6
         --Left Join acaedw.odsnpi.prov_deal_scenarios as pds on pds.scenarioid = ldcf.con_deal_scenario_id
         --Left Join acaedw.odsnpi.prov_deal_scoremodels as apppdsm on apppdsm.scenarioid = pds.appscenarioid
--          left join acaedw.sandbox.rehashes as re
--                    on re.dealdetailid = ldcf.los_deal_current_fact_universal_id and re.appid = ldcf.loan_id
         Left Join acaedw.odsnpi.prov_dealerattributes as pd
                   on pd.dealerid = ldcf.dealer_number and pd.attributetype = 'Dealer Level Loss Adjustment'

        LEFT JOIN edwnpi.dealer_rollup_scd_current AS dru
                   ON ldcf.dealer_number = dru.dealer_number
where aspect ilike 'Contract'
  and ldcf.data_source_id in (17, 100)
  and ldcf.contract_signed_dtm between '2018-01-01' and '2025-06-17'
  and
  --ldcf.contract_signed_dtm not between '2023-11-01' and '2024-02-01' and
    ldcf.book_date notnull
  and ldcf.account_number notnull-- and
  and deal_deleted_flag = 0
  --and lower(dealer_pricing_hurdle) != 'mroa-kmx'
  --smm.account_life_cycle not ilike 'BUYBACK'--  and aca_model_score notnull
order by loan_id;--, MOB;
--SELECT * from #Fraud_Data ;


select top 1 * from sandbox.fraud_data_gs;


47964430


SELECt top 100 * from acaedw.sandbox.pos_fraud_data
