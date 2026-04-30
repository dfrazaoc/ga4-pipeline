# ── BigQuery dataset ────────────────────────────────────────────────────────
resource "google_bigquery_dataset" "ga4_analytics" {
  dataset_id  = var.bq_dataset
  project     = var.project_id
  location    = "US"
  description = "GA4 analytics models produced by dbt"

  delete_contents_on_destroy = false
}

# ── Service accounts ─────────────────────────────────────────────────────────
resource "google_service_account" "metabase_runner" {
  account_id   = "metabase-cloudrun"
  display_name = "Metabase Cloud Run SA"
  project      = var.project_id
}

# IAM for Cloud Run SA
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

# ── Secret Manager ───────────────────────────────────────────────────────────
resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "postgres_password" {
  secret_id = "postgres-password"
  project   = var.project_id

  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = random_password.postgres.result
}

resource "google_secret_manager_secret" "metabase_admin_password" {
  secret_id = "metabase-admin-password"
  project   = var.project_id

  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "metabase_admin_password" {
  secret      = google_secret_manager_secret.metabase_admin_password.id
  secret_data = "AskCostaData2026!"
}

# ── Cloud SQL ────────────────────────────────────────────────────────────────
resource "google_sql_database_instance" "metabase" {
  name             = var.cloud_sql_instance_name
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_15"

  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

resource "google_sql_database" "metabase" {
  name     = "metabase"
  instance = google_sql_database_instance.metabase.name
  project  = var.project_id
}

resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.metabase.name
  project  = var.project_id
  password = random_password.postgres.result
}

# ── Cloud Run v2 — Metabase + Cloud SQL proxy ────────────────────────────────
locals {
  sql_connection = "${var.project_id}:${var.region}:${var.cloud_sql_instance_name}"
}

resource "google_cloud_run_v2_service" "metabase" {
  name     = var.cloud_run_service_name
  project  = var.project_id
  location = var.region

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.metabase_runner.email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.11"

      args = [
        "--structured-logs",
        "--address=0.0.0.0",
        "--port=5432",
        local.sql_connection
      ]

      resources {
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }

      startup_probe {
        tcp_socket {
          port = 5432
        }
        initial_delay_seconds = 10
        period_seconds        = 10
        failure_threshold     = 6
        timeout_seconds       = 5
      }
    }

    containers {
      name  = "metabase"
      image = "metabase/metabase:v0.52.9"

      depends_on = ["cloud-sql-proxy"]

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      env {
        name  = "MB_DB_TYPE"
        value = "postgres"
      }
      env {
        name  = "MB_DB_HOST"
        value = "127.0.0.1"
      }
      env {
        name  = "MB_DB_PORT"
        value = "5432"
      }
      env {
        name  = "MB_DB_DBNAME"
        value = "metabase"
      }
      env {
        name  = "MB_DB_USER"
        value = "postgres"
      }
      env {
        name = "MB_DB_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.postgres_password.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "MB_SITE_URL"
        value = "https://${var.cloud_run_service_name}-${data.google_project.project.number}.${var.region}.run.app"
      }
      env {
        name  = "JAVA_OPTS"
        value = "-Xmx1500m"
      }

      startup_probe {
        http_get {
          path = "/api/health"
          port = 3000
        }
        initial_delay_seconds = 90
        period_seconds        = 15
        failure_threshold     = 24
        timeout_seconds       = 5
      }

      liveness_probe {
        http_get {
          path = "/api/health"
          port = 3000
        }
        initial_delay_seconds = 0
        period_seconds        = 30
        failure_threshold     = 3
        timeout_seconds       = 5
      }
    }
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

# Allow unauthenticated access to Metabase
resource "google_cloud_run_v2_service_iam_member" "metabase_public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.metabase.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
