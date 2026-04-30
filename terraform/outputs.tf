output "metabase_url" {
  description = "Metabase Cloud Run URL"
  value       = "https://metabase-357155427260.us-central1.run.app"
}

output "bq_dataset" {
  description = "BigQuery dataset for dbt models"
  value       = google_bigquery_dataset.ga4_analytics.dataset_id
}
