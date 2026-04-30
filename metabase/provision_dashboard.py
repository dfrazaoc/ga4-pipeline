#!/usr/bin/env python3
"""Provision the GA4 analytics Metabase dashboard via API.

Skills.md rules applied:
- PUT /api/dashboard/:id/cards  (POST was removed in v0.52)
- Unique negative IDs: enumerate(CARDS, start=1) → "id": -tmp_id
"""

import json
import os
import sys
import time

import requests

# ── Config from env ──────────────────────────────────────────────────────────
METABASE_URL          = os.environ["METABASE_URL"].rstrip("/")
ADMIN_EMAIL           = os.environ["METABASE_ADMIN_EMAIL"]
ADMIN_PASSWORD        = os.environ["METABASE_ADMIN_PASSWORD"]
GCP_PROJECT_ID        = os.environ["GCP_PROJECT_ID"]
GCP_SA_KEY_JSON       = os.environ["GCP_SA_KEY_JSON"]
BQ_DATASET            = os.environ.get("BQ_DATASET", "ga4_analytics")

SESSION_TOKEN: str = ""

# ── Helpers ──────────────────────────────────────────────────────────────────

def headers() -> dict:
    return {"Content-Type": "application/json", "X-Metabase-Session": SESSION_TOKEN}


def wait_for_metabase(max_wait: int = 600) -> None:
    print("Waiting for Metabase to be healthy…", flush=True)
    deadline = time.time() + max_wait
    while time.time() < deadline:
        try:
            r = requests.get(f"{METABASE_URL}/api/health", timeout=10)
            if r.status_code == 200 and r.json().get("status") == "ok":
                print("Metabase is healthy.", flush=True)
                return
        except Exception:
            pass
        time.sleep(15)
    raise RuntimeError("Metabase did not become healthy within the wait window.")


def login() -> None:
    global SESSION_TOKEN
    r = requests.post(
        f"{METABASE_URL}/api/session",
        json={"username": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
        timeout=30,
    )
    r.raise_for_status()
    SESSION_TOKEN = r.json()["id"]
    print("Logged in to Metabase.", flush=True)


def setup_if_needed() -> None:
    """Run /api/setup only if Metabase has not been set up yet."""
    r = requests.get(f"{METABASE_URL}/api/session/properties", timeout=30)
    props = r.json()
    if props.get("setup-token") is None:
        print("Metabase already configured — skipping setup.", flush=True)
        return
    setup_token = props["setup-token"]
    payload = {
        "token": setup_token,
        "user": {
            "first_name": "Ask",
            "last_name": "Costa",
            "email": ADMIN_EMAIL,
            "password": ADMIN_PASSWORD,
            "password_confirm": ADMIN_PASSWORD,
            "site_name": "GA4 Analytics",
        },
        "prefs": {
            "site_name": "GA4 Analytics",
            "allow_tracking": False,
        },
    }
    r = requests.post(f"{METABASE_URL}/api/setup", json=payload, timeout=60)
    r.raise_for_status()
    print("Metabase setup complete.", flush=True)


def get_or_create_database() -> int:
    """Connect Metabase to the ga4_analytics BigQuery dataset."""
    r = requests.get(f"{METABASE_URL}/api/database", headers=headers(), timeout=30)
    r.raise_for_status()
    for db in r.json().get("data", []):
        if db.get("engine") == "bigquery-cloud-sdk" and db.get("name") == "GA4 Analytics":
            print(f"BigQuery database already exists: id={db['id']}", flush=True)
            return db["id"]

    sa_key = json.loads(GCP_SA_KEY_JSON)
    payload = {
        "engine": "bigquery-cloud-sdk",
        "name": "GA4 Analytics",
        "details": {
            "project-id": GCP_PROJECT_ID,
            "dataset-filters-type": "inclusion",
            "dataset-filters-patterns": BQ_DATASET,
            "service-account-json": json.dumps(sa_key),
        },
        "auto_run_queries": True,
        "is_full_sync": True,
    }
    r = requests.post(f"{METABASE_URL}/api/database", headers=headers(), json=payload, timeout=60)
    r.raise_for_status()
    db_id = r.json()["id"]
    print(f"BigQuery database created: id={db_id}", flush=True)

    # Trigger a sync so tables appear
    requests.post(f"{METABASE_URL}/api/database/{db_id}/sync_schema", headers=headers(), timeout=30)
    print("Schema sync triggered — waiting 30 s…", flush=True)
    time.sleep(30)
    return db_id


def get_table_id(db_id: int, table_name: str) -> int | None:
    r = requests.get(f"{METABASE_URL}/api/database/{db_id}/metadata", headers=headers(), timeout=60)
    r.raise_for_status()
    for t in r.json().get("tables", []):
        if t["name"].lower() == table_name.lower():
            return t["id"]
    return None


def wait_for_tables(db_id: int, needed: list[str], max_wait: int = 180) -> dict[str, int]:
    """Poll until all required tables are visible in Metabase metadata."""
    deadline = time.time() + max_wait
    while time.time() < deadline:
        table_map: dict[str, int] = {}
        r = requests.get(f"{METABASE_URL}/api/database/{db_id}/metadata", headers=headers(), timeout=60)
        r.raise_for_status()
        for t in r.json().get("tables", []):
            table_map[t["name"].lower()] = t["id"]
        if all(n.lower() in table_map for n in needed):
            return {n: table_map[n.lower()] for n in needed}
        missing = [n for n in needed if n.lower() not in table_map]
        print(f"Tables not yet visible: {missing} — waiting…", flush=True)
        time.sleep(20)
    raise RuntimeError(f"Tables never appeared in Metabase: {needed}")


def create_native_question(db_id: int, name: str, sql: str, display: str = "table") -> int:
    """Create a native SQL question and return its card id."""
    # Check if it already exists
    r = requests.get(f"{METABASE_URL}/api/card", headers=headers(), timeout=30)
    r.raise_for_status()
    for card in r.json():
        if card.get("name") == name:
            print(f"Card already exists: '{name}' id={card['id']}", flush=True)
            return card["id"]

    payload = {
        "name": name,
        "display": display,
        "dataset_query": {
            "type": "native",
            "database": db_id,
            "native": {"query": sql},
        },
        "visualization_settings": {},
    }
    r = requests.post(f"{METABASE_URL}/api/card", headers=headers(), json=payload, timeout=30)
    r.raise_for_status()
    card_id = r.json()["id"]
    print(f"Created card '{name}': id={card_id}", flush=True)
    return card_id


def get_or_create_dashboard(name: str) -> int:
    r = requests.get(f"{METABASE_URL}/api/dashboard", headers=headers(), timeout=30)
    r.raise_for_status()
    for d in r.json():
        if d.get("name") == name:
            print(f"Dashboard already exists: id={d['id']}", flush=True)
            return d["id"]
    r = requests.post(
        f"{METABASE_URL}/api/dashboard",
        headers=headers(),
        json={"name": name, "description": "GA4 e-commerce analytics"},
        timeout=30,
    )
    r.raise_for_status()
    dash_id = r.json()["id"]
    print(f"Created dashboard '{name}': id={dash_id}", flush=True)
    return dash_id


def place_cards_on_dashboard(dash_id: int, card_specs: list[dict]) -> None:
    """PUT /api/dashboard/:id/cards with unique negative IDs per skills.md."""
    cards_payload = []
    for tmp_id, spec in enumerate(card_specs, start=1):
        cards_payload.append({
            "id": -tmp_id,
            "card_id": spec["card_id"],
            "row": spec["row"],
            "col": spec["col"],
            "size_x": spec.get("size_x", 6),
            "size_y": spec.get("size_y", 4),
            "series": [],
            "visualization_settings": spec.get("viz_settings", {}),
            "parameter_mappings": [],
        })
    r = requests.put(
        f"{METABASE_URL}/api/dashboard/{dash_id}/cards",
        headers=headers(),
        json={"cards": cards_payload},
        timeout=60,
    )
    if not r.ok:
        print(f"Error placing cards: {r.status_code} {r.text}", flush=True)
        r.raise_for_status()
    print(f"Placed {len(cards_payload)} cards on dashboard {dash_id}.", flush=True)


# ── SQL definitions ───────────────────────────────────────────────────────────

def sql_kpi_revenue(dataset: str) -> str:
    return f"""
SELECT ROUND(SUM(total_revenue_usd), 2) AS total_revenue_usd
FROM `{dataset}.fct_daily_metrics`
"""

def sql_kpi_items(dataset: str) -> str:
    return f"""
SELECT SUM(total_items_purchased) AS total_items_purchased
FROM `{dataset}.fct_daily_metrics`
"""

def sql_kpi_conversion(dataset: str) -> str:
    return f"""
SELECT ROUND(
  SAFE_DIVIDE(SUM(total_purchases), SUM(total_sessions)) * 100, 2
) AS conversion_rate_pct
FROM `{dataset}.fct_daily_metrics`
"""

def sql_kpi_avg_check(dataset: str) -> str:
    return f"""
SELECT ROUND(
  SAFE_DIVIDE(SUM(total_revenue_usd), NULLIF(SUM(total_purchases), 0)), 2
) AS avg_order_value_usd
FROM `{dataset}.fct_daily_metrics`
"""

def sql_kpi_bounced(dataset: str) -> str:
    return f"""
SELECT SUM(bounced_sessions) AS total_bounced_sessions
FROM `{dataset}.fct_daily_metrics`
"""

def sql_top_items(dataset: str) -> str:
    return f"""
SELECT
  item_name,
  SUM(quantity)               AS total_quantity_purchased,
  SUM(item_revenue_in_usd)    AS total_item_revenue_usd,
  COUNT(DISTINCT transaction_id) AS purchase_count
FROM `{dataset}.fct_items`
WHERE item_name IS NOT NULL
GROUP BY 1
ORDER BY total_quantity_purchased DESC
LIMIT 10
"""

def sql_funnel(dataset: str) -> str:
    return f"""
SELECT
  'session_start'    AS funnel_step, 1 AS step_order, COUNTIF(step_session_start)    AS sessions FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'view_item',        2, COUNTIF(step_view_item)        FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'select_item',      3, COUNTIF(step_select_item)      FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'add_to_cart',      4, COUNTIF(step_add_to_cart)      FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'begin_checkout',   5, COUNTIF(step_begin_checkout)   FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'add_payment_info', 6, COUNTIF(step_add_payment_info) FROM `{dataset}.fct_funnel`
UNION ALL
SELECT 'purchase',         7, COUNTIF(step_purchase)         FROM `{dataset}.fct_funnel`
ORDER BY step_order
"""

def sql_revenue_by_date(dataset: str) -> str:
    return f"""
SELECT
  event_date,
  total_revenue_usd,
  total_purchases,
  avg_order_value
FROM `{dataset}.fct_daily_metrics`
ORDER BY event_date
"""

def sql_visits_by_date(dataset: str) -> str:
    return f"""
SELECT
  event_date,
  total_sessions AS total_visits,
  bounced_sessions
FROM `{dataset}.fct_daily_metrics`
ORDER BY event_date
"""

def sql_conversion_by_date(dataset: str) -> str:
    return f"""
SELECT
  event_date,
  ROUND(conversion_rate * 100, 2) AS conversion_rate_pct
FROM `{dataset}.fct_daily_metrics`
ORDER BY event_date
"""


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    wait_for_metabase()
    setup_if_needed()
    login()

    db_id = get_or_create_database()

    # Build fully-qualified dataset reference
    fq_dataset = f"{GCP_PROJECT_ID}.{BQ_DATASET}"

    # Create questions
    card_revenue     = create_native_question(db_id, "KPI: Total Revenue",             sql_kpi_revenue(fq_dataset),     "scalar")
    card_items       = create_native_question(db_id, "KPI: Total Items Purchased",     sql_kpi_items(fq_dataset),       "scalar")
    card_conv        = create_native_question(db_id, "KPI: Conversion Rate (%)",       sql_kpi_conversion(fq_dataset),  "scalar")
    card_avg         = create_native_question(db_id, "KPI: Average Check (USD)",       sql_kpi_avg_check(fq_dataset),   "scalar")
    card_bounced     = create_native_question(db_id, "KPI: Total Bounced Sessions",    sql_kpi_bounced(fq_dataset),     "scalar")
    card_top_items   = create_native_question(db_id, "Top 10 Most Purchased Items",    sql_top_items(fq_dataset),       "bar")
    card_funnel      = create_native_question(db_id, "Purchase Funnel",                sql_funnel(fq_dataset),          "funnel")
    card_rev_date    = create_native_question(db_id, "Revenue by Date",                sql_revenue_by_date(fq_dataset), "line")
    card_visits_date = create_native_question(db_id, "Total Visits by Date",           sql_visits_by_date(fq_dataset),  "line")
    card_conv_date   = create_native_question(db_id, "Conversion Rate by Date",        sql_conversion_by_date(fq_dataset), "line")

    # Create dashboard
    dash_id = get_or_create_dashboard("GA4 E-Commerce Analytics")

    # Layout: 24-column grid, rows of 4 height each
    # Row 0: 5 KPI scalars (each 4-wide, 2-tall)
    # Row 2: Top Items (12-wide, 6-tall) | Funnel (12-wide, 6-tall)
    # Row 8: Revenue by Date (24-wide, 5-tall)
    # Row 13: Visits by Date (12-wide, 5-tall) | Conv Rate by Date (12-wide, 5-tall)
    card_specs = [
        # KPI row
        {"card_id": card_revenue,     "row": 0,  "col": 0,  "size_x": 4, "size_y": 2},
        {"card_id": card_items,       "row": 0,  "col": 4,  "size_x": 4, "size_y": 2},
        {"card_id": card_conv,        "row": 0,  "col": 8,  "size_x": 4, "size_y": 2},
        {"card_id": card_avg,         "row": 0,  "col": 12, "size_x": 4, "size_y": 2},
        {"card_id": card_bounced,     "row": 0,  "col": 16, "size_x": 4, "size_y": 2},
        # Charts row
        {"card_id": card_top_items,   "row": 2,  "col": 0,  "size_x": 12, "size_y": 6},
        {"card_id": card_funnel,      "row": 2,  "col": 12, "size_x": 12, "size_y": 6},
        # Time-series
        {"card_id": card_rev_date,    "row": 8,  "col": 0,  "size_x": 24, "size_y": 5},
        {"card_id": card_visits_date, "row": 13, "col": 0,  "size_x": 12, "size_y": 5},
        {"card_id": card_conv_date,   "row": 13, "col": 12, "size_x": 12, "size_y": 5},
    ]

    place_cards_on_dashboard(dash_id, card_specs)

    dashboard_url = f"{METABASE_URL}/dashboard/{dash_id}"
    print(f"\n{'='*60}", flush=True)
    print(f"Dashboard live: {dashboard_url}", flush=True)
    print(f"{'='*60}\n", flush=True)

    # Surface in GitHub Actions summary if running in CI
    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with open(summary_file, "a") as f:
            f.write(f"\n### Dashboard\n[Open dashboard]({dashboard_url})\n")


if __name__ == "__main__":
    main()
