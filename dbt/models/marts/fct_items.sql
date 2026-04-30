{{
    config(
        materialized         = 'incremental',
        incremental_strategy = 'merge',
        unique_key           = ['event_date', 'transaction_id', 'item_id'],
        partition_by         = {
            'field'       : 'event_date',
            'data_type'   : 'date',
            'granularity' : 'day'
        },
        cluster_by           = ['event_date', 'item_name']
    )
}}

SELECT
    PARSE_DATE('%Y%m%d', event_date)  AS event_date,
    transaction_id,
    user_pseudo_id,
    ga_session_id,
    item.item_id,
    item.item_name,
    item.item_category,
    item.item_brand,
    item.price_in_usd,
    item.quantity,
    item.item_revenue_in_usd
FROM {{ ref('stg_ga4_events') }},
     UNNEST(items) AS item
WHERE event_name = 'purchase'
  AND transaction_id IS NOT NULL
  AND ARRAY_LENGTH(items) > 0
{% if is_incremental() %}
  AND PARSE_DATE('%Y%m%d', event_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
{% endif %}
