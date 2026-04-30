{{
    config(
        materialized         = 'incremental',
        incremental_strategy = 'merge',
        unique_key           = ['event_date'],
        partition_by         = {
            'field'       : 'event_date',
            'data_type'   : 'date',
            'granularity' : 'day'
        }
    )
}}

WITH sessions AS (
    SELECT
        event_date,
        COUNT(*)                    AS total_sessions,
        COUNTIF(is_bounced)         AS bounced_sessions,
        COUNTIF(has_purchase)       AS converting_sessions
    FROM {{ ref('fct_sessions') }}
    {% if is_incremental() %}
    WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
    {% endif %}
    GROUP BY 1
),

revenue AS (
    SELECT
        event_date,
        COUNT(DISTINCT transaction_id)  AS total_purchases,
        SUM(revenue_usd)                AS total_revenue_usd,
        SUM(total_item_quantity)        AS total_items_purchased
    FROM {{ ref('fct_transactions') }}
    {% if is_incremental() %}
    WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
    {% endif %}
    GROUP BY 1
)

SELECT
    s.event_date,
    s.total_sessions,
    s.bounced_sessions,
    s.converting_sessions,
    SAFE_DIVIDE(s.bounced_sessions, s.total_sessions)                        AS bounce_rate,
    COALESCE(r.total_purchases, 0)                                           AS total_purchases,
    COALESCE(r.total_revenue_usd, 0)                                         AS total_revenue_usd,
    COALESCE(r.total_items_purchased, 0)                                     AS total_items_purchased,
    SAFE_DIVIDE(r.total_purchases, s.total_sessions)                         AS conversion_rate,
    SAFE_DIVIDE(r.total_revenue_usd, NULLIF(r.total_purchases, 0))           AS avg_order_value
FROM sessions s
LEFT JOIN revenue r USING (event_date)
