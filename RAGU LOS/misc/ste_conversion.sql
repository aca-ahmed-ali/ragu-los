
with decision as (select app.source_document_id as sfs_application_number,
                         DATE_TRUNC('month', application_received_date) as app_month,
                         case
                             when status_name != 'Declined' and dec.cash_down_amt <= req.cash_down_amt + 250
                                 then 'Straight Approval'
                             when status_name != 'Declined' then 'Conditional Approval'
                             when status_name = 'Declined' then 'Declined'
                             else null end      as approval_type
                  from (select loan_id,
                               application_received_date,
                               deal_detail_id,
                               model_score_version,
                               source_document_id,
                               row_number() over (
                                   partition by source_document_id
                                   order by
                                       application_received_date desc
                                   ) rn
                        from odsnpi.sfs_deal_detail_scd
                        where current_version_flag = 1
                          and aspect = 'application') app
                           left join odsnpi.sfs_deal_scenario_scd req
                                     on app.deal_detail_id = req.deal_detail_id and
                                        req.scenario_type = 'Adjusted' and
                                        req.current_version_flag = 1
                           left join odsnpi.sfs_deal_scenario_scd dec
                                     on app.deal_detail_id = dec.deal_detail_id and
                                        dec.scenario_type = 'Application' and dec.active_flag = 1 and
                                        dec.current_version_flag = 1
                           left join (select *,
                                             row_number() over (partition by deal_detail_id order by created_dtm desc) as index
                                      from odsnpi.sfs_deal_status_scd) stat
                                     on app.deal_detail_id = stat.deal_detail_id and
                                        stat.index = 1
                  where app.rn = 1
                    and application_received_date >= '2025-10-07')
select app_month,
       count(distinct decision.sfs_application_number) as total_apps,
       count(distinct case when approval_type = 'Straight Approval'
                           then decision.sfs_application_number end) as straight_approved,
       count(distinct case when approval_type = 'Straight Approval' and book_date is not null
                           then decision.sfs_application_number end) as booked_straight,
       straight_approved * 1.0 / nullif(total_apps, 0) as straight_approval_rate,
       booked_straight * 1.0 / nullif(straight_approved, 0) as conversion_rate
from decision
         left join odsnpi.sfs_booked_contracts_scd cd
                   on decision.sfs_application_number = cd.sfs_application_number and cd.current_version_flag = 1
group by app_month
order by app_month;
