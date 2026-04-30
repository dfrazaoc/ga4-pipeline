#!/usr/bin/env bash
# Bootstrap: create GCS state bucket and ensure APIs are enabled
set -euo pipefail

PROJECT_ID="${1:-askcosta}"
REGION="${2:-us-central1}"
STATE_BUCKET="${PROJECT_ID}-tf-state"

echo "==> Enabling required GCP APIs..."
gcloud services enable \
  bigquery.googleapis.com \
  run.googleapis.com \
  sql-component.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT_ID" --quiet

echo "==> Creating GCS state bucket: gs://$STATE_BUCKET"
if gcloud storage buckets describe "gs://$STATE_BUCKET" --project="$PROJECT_ID" &>/dev/null; then
  echo "    Bucket already exists — skipping."
else
  gcloud storage buckets create "gs://$STATE_BUCKET" \
    --project="$PROJECT_ID" \
    --location=US \
    --uniform-bucket-level-access
  echo "    Bucket created."
fi

echo "==> Bootstrap complete."
