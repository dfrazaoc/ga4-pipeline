# ── BigQuery dataset ──────────────────────────────────────────────────────────
resource "google_bigquery_dataset" "ga4_analytics" {
  dataset_id  = var.bq_dataset
  project     = var.project_id
  location    = "US"
  description = "GA4 analytics models produced by dbt"

  delete_contents_on_destroy = false
}

# ── Service account (already exists — imported) ───────────────────────────────
resource "google_service_account" "metabase_runner" {
  account_id   = "metabase-cloudrun"
  display_name = "Metabase Cloud Run SA"
  project      = var.project_id
}

# IAM: let Metabase SA query BigQuery
resource "google_project_iam_member" "metabase_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.metabase_runner.email}"
}

resource "google_project_iam_member" "metabase_bq_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.metabase_runner.email}"
}

resource "google_project_iam_member" "metabase_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.metabase_runner.email}"
}

resource "google_project_iam_member" "metabase_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.metabase_runner.email}"
}
