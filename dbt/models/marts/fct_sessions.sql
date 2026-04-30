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
        cluster_by           = ['event_date', 'device_category']
    )
}}

WITH session_events AS (
    SELECT
        PARSE_DATE('%Y%m%d', event_date)  AS event_date,
        user_pseudo_id,
        ga_session_id,
        ga_session_number,
        event_name,
        engagement_time_msec,
        session_engaged,
        country,
        device_category,
        traffic_source,
        traffic_medium,
        event_timestamp
    FROM {{ ref('stg_ga4_events') }}
    WHERE ga_session_id IS NOT NULL
    {% if is_incremental() %}
      AND PARSE_DATE('%Y%m%d', event_date) >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
    {% endif %}
),

session_agg AS (
    SELECT
        event_date,
        user_pseudo_id,
        ga_session_id,
        MAX(ga_session_number)                                                      AS ga_session_number,
        COUNT(DISTINCT event_name)                                                  AS unique_event_types,
        COUNT(*)                                                                    AS total_events,
        MAX(engagement_time_msec)                                                   AS max_engagement_time_msec,
        MAX(CASE WHEN session_engaged IN ('1') THEN 1 ELSE 0 END)                  AS is_engaged,
        MAX(country)                                                                AS country,
        MAX(device_category)                                                        AS device_category,
        MAX(traffic_source)                                                         AS traffic_source,
        MAX(traffic_medium)                                                         AS traffic_medium,
        MIN(event_timestamp)                                                        AS session_start_ts,

        -- Bounced: session never progressed beyond session_start
        MAX(CASE WHEN event_name != 'session_start' THEN 1 ELSE 0 END) = 0        AS is_bounced,

        -- Has purchase
        MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) = 1              AS has_purchase
    FROM session_events
    GROUP BY 1, 2, 3
)

SELECT * FROM session_agg
