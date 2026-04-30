variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "askcosta"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "bq_dataset" {
  description = "BigQuery dataset for dbt output"
  type        = string
  default     = "ga4_analytics"
}

variable "metabase_version" {
  description = "Metabase Docker image tag"
  type        = string
  default     = "v0.52.9"
}

variable "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  type        = string
  default     = "metabase-db"
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name"
  type        = string
  default     = "metabase"
}
