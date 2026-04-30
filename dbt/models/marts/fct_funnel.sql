{{
    config(
        materialized         = 'incremental',
        incremental_strategy = 'merge',
        unique_key           = ['event_date', 'user_pseudo_id', 'ga_session_id'],
        partition_by         = {
            'field'       : 'event_date',
            'data_type'   : 'date',
            'granularity' : 'day'
        },
        cluster_by           = ['event_date']
    )
}}

SELECT
    PARSE_DATE('%Y%m%d', event_date)                                              AS event_date,
    user_pseudo_id,
    ga_session_id,
    MAX(CASE WHEN event_name = 'session_start'     THEN 1 ELSE 0 END) = 1        AS step_session_start,
    MAX(CASE WHEN event_name = 'view_item'         THEN 1 ELSE 0 END) = 1        AS step_view_item,
    MAX(CASE WHEN event_name = 'select_item'       THEN 1 ELSE 0 END) = 1        AS step_select_item,
    MAX(CASE WHEN event_name = 'add_to_cart'       THEN 1 ELSE 0 END) = 1        AS step_add_to_cart,
    MAX(CASE WHEN event_name = 'begin_checkout'    THEN 1 ELSE 0 END) = 1        AS step_begin_checkout,
    MAX(CASE WHEN event_name = 'add_payment_info'  THEN 1 ELSE 0 END) = 1        AS step_add_payment_info,
    MAX(CASE WHEN event_name = 'purchase'          THEN 1 ELSE 0 END) = 1        AS step_purchase
FROM {{ ref('stg_ga4_events') }}
WHERE ga_session_id IS NOT NULL
  AND event_name IN (
      'session_start', 'view_item', 'select_item',
      'add_to_cart', 'begin_checkout', 'add_payment_info', 'purchase'
  )
{% if is_incremental() %}
  AND PARSE_DATE('%Y%m%d', event_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
{% endif %}
GROUP BY 1, 2, 3
