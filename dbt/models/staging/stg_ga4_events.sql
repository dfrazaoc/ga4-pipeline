-- Staging view — NO partition_by (wildcard source + CTAS + PARTITION BY = silent 0 rows)
{{ config(materialized='view') }}

SELECT
    event_date,
    TIMESTAMP_MICROS(event_timestamp)                                                          AS event_timestamp,
    event_name,
    user_pseudo_id,

    -- Session identifiers
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')          AS ga_session_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number')      AS ga_session_number,

    -- Engagement signals
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'engagement_time_msec')  AS engagement_time_msec,
    (SELECT
        COALESCE(value.string_value, CAST(value.int_value AS STRING))
     FROM UNNEST(event_params) WHERE key = 'session_engaged')                                  AS session_engaged,

    -- Page / content
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')         AS page_location,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title')            AS page_title,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer')         AS page_referrer,

    -- Item interaction (for item-level events)
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id')               AS param_item_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name')             AS param_item_name,

    -- Ecommerce
    ecommerce.transaction_id,
    ecommerce.purchase_revenue_in_usd                                                          AS revenue_usd,
    ecommerce.total_item_quantity,

    -- Items array (for purchase events)
    items,

    -- Dimensions
    device.category                                                                            AS device_category,
    device.operating_system,
    device.browser,
    geo.country,
    geo.city,
    traffic_source.source                                                                      AS traffic_source,
    traffic_source.medium                                                                      AS traffic_medium,
    traffic_source.name                                                                        AS traffic_campaign

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
