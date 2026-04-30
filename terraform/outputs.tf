output "metabase_url" {
  description = "Metabase Cloud Run URL"
  value       = google_cloud_run_v2_service.metabase.uri
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name for the proxy"
  value       = google_sql_database_instance.metabase.connection_name
}

output "bq_dataset" {
  description = "BigQuery dataset for dbt models"
  value       = google_bigquery_dataset.ga4_analytics.dataset_id
}
