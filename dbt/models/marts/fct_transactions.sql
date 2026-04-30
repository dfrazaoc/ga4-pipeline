{{
    config(
        materialized         = 'incremental',
        incremental_strategy = 'merge',
        unique_key           = ['event_date', 'transaction_id'],
        partition_by         = {
            'field'       : 'event_date',
            'data_type'   : 'date',
            'granularity' : 'day'
        },
        cluster_by           = ['event_date']
    )
}}

SELECT
    PARSE_DATE('%Y%m%d', event_date)  AS event_date,
    transaction_id,
    user_pseudo_id,
    ga_session_id,
    revenue_usd,
    total_item_quantity,
    country,
    device_category,
    traffic_source,
    traffic_medium
FROM {{ ref('stg_ga4_events') }}
WHERE event_name = 'purchase'
  AND transaction_id IS NOT NULL
  AND revenue_usd IS NOT NULL
{% if is_incremental() %}
  AND PARSE_DATE('%Y%m%d', event_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
{% endif %}
