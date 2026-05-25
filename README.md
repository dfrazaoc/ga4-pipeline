# GA4 Analytics Pipeline

End-to-end data pipeline that transforms raw Google Analytics 4 events into a Metabase dashboard on Google Cloud Platform.

## Architecture

```
BigQuery (GA4 raw events)
        │
        ▼
  dbt (staging → marts)
        │
        ▼
  BigQuery (ga4_analytics dataset)
        │
        ▼
  Metabase on Cloud Run
```

**Stack:** dbt + BigQuery · Metabase (Cloud Run) · Terraform · GitHub Actions

## dbt Models

| Layer | Model | Description |
|-------|-------|-------------|
| Staging | `stg_ga4_events` | View over the raw GA4 public ecommerce dataset |
| Marts | `fct_sessions` | One row per session with bounce and purchase flags |
| Marts | `fct_transactions` | One row per purchase transaction |
| Marts | `fct_items` | One row per item within each transaction |
| Marts | `fct_funnel` | Funnel step flags per session (session_start → purchase) |
| Marts | `fct_daily_metrics` | Daily rollup: sessions, revenue, conversions, bounce rate |

Staging models are materialized as **views**; mart models are **incremental**.

## Metabase Dashboard

The dashboard (`GA4 E-Commerce Analytics`) is provisioned automatically via `metabase/provision_dashboard.py` and includes:

- KPI scalars: Total Revenue · Items Purchased · Conversion Rate · Avg Order Value · Bounced Sessions
- Top 10 Most Purchased Items (bar chart)
- Purchase Funnel (funnel chart)
- Revenue by Date, Total Visits by Date, Conversion Rate by Date (line charts)

## Infrastructure (Terraform)

Managed resources in `terraform/`:

- `google_bigquery_dataset.ga4_analytics` — output dataset for dbt models
- `google_service_account.metabase_runner` — Metabase Cloud Run service account
- IAM bindings: `bigquery.dataViewer`, `bigquery.jobUser`, `cloudsql.client`, `secretmanager.secretAccessor`

Terraform state is stored in GCS (`askcosta-tf-state`).

## CI/CD Workflows

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| `deploy.yml` | Push to `main` | Terraform init → plan → apply |
| `dbt_daily.yml` | Daily at 06:00 UTC | `dbt run` + `dbt test` + provision Metabase dashboard |

`dbt_daily.yml` also accepts a `workflow_dispatch` input (`full_refresh: true/false`) for manual runs.

## Setup

### Prerequisites

- GCP project with billing enabled
- `gcloud` CLI authenticated
- GitHub repository secrets:
  - `GCP_SA_KEY` — service account key JSON with BigQuery, Cloud Run, and Secret Manager permissions
  - `METABASE_URL` — Cloud Run URL output from the first Terraform apply

### 1. Bootstrap GCP

```bash
bash scripts/bootstrap.sh <PROJECT_ID> <REGION>
```

This enables required APIs and creates the Terraform state bucket.

### 2. Deploy infrastructure

Push to `main` or trigger `Deploy Infrastructure` manually in GitHub Actions. The Terraform apply outputs the Metabase URL — set it as the `METABASE_URL` secret.

### 3. Run dbt locally

```bash
pip install -r requirements.txt
cd dbt
export GCP_PROJECT_ID=<project>
export GCP_KEYFILE_PATH=<path-to-key.json>
dbt deps
dbt run --profiles-dir .
dbt test --profiles-dir .
```

### 4. Provision the dashboard manually

```bash
export METABASE_URL=https://...
export METABASE_ADMIN_EMAIL=<email>
export METABASE_ADMIN_PASSWORD=<password>
export GCP_PROJECT_ID=<project>
export GCP_SA_KEY_JSON=$(cat path/to/key.json)
export BQ_DATASET=ga4_analytics
python metabase/provision_dashboard.py
```

## Project Structure

```
ga4-pipeline/
├── dbt/
│   ├── models/
│   │   ├── staging/        # stg_ga4_events
│   │   └── marts/          # fct_sessions, fct_transactions, fct_items, fct_funnel, fct_daily_metrics
│   ├── dbt_project.yml
│   └── profiles.yml
├── metabase/
│   └── provision_dashboard.py
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── providers.tf
├── scripts/
│   └── bootstrap.sh
├── .github/
│   └── workflows/
│       ├── deploy.yml
│       └── dbt_daily.yml
└── requirements.txt
```
