# Armure APIM Sentinel — Build Plan

> Granular task list for building the production Frappe app from the React/Express prototype.
> Reference: `implementation-plan.md` in the parent directory for full design details.

---

## Legend

- `[ ]` — pending
- `[x]` — completed
- `[~]` — in progress
- `[!]` — blocked

---

## Phase 0 Learnings (Consolidated)

These are the corrections discovered during Phase 0 execution. All future phases should follow these conventions.

### 0L.1 Docker Container Behavior

| Expectation | Reality | Correction |
|---|---|---|
| `bench init` needed to create a new bench | `frappe/bench:latest` ships with bench 5.29.1 + Python 3.14 pre-installed | No `bench init` — the bench is already at `/workspace/development/armure-apim/` |
| `requirements.txt` for Python deps | Frappe v16 apps use `pyproject.toml` | Add to `[project] dependencies = ["opensearch-py"]` |
| `localhost:8000` works directly | Site is `apim.localhost`, not `localhost` | Use `curl -H "Host: apim.localhost" http://localhost:8000/...` |
| Server with `--development` flag needed | `bench serve --port 8000` is sufficient | The `--development` flag is for live reload, not required for basic serving |

### 0L.2 bench new-app Interactive Mode

Bench 5.29.1 does NOT support silent flags (`--title`, `--description`). Use `echo -e` piping:

```bash
docker compose exec -T frappe bash -c \
  "cd /workspace/development/armure-apim && \
   echo -e 'Armure APIM Sentinel\nDescription...\nArmure Suite\ndevelopment@armure.in\nmit\nn' | \
   bench new-app armure_apim_sentinel"
```

**Prompt order:** Title → Description → Publisher → Email → License → GitHub Actions (y/N)
- License must be lowercase: `mit` not `MIT`
- GitHub Actions: `n`

### 0L.3 OpenSearch 3.x

- Tag `opensearchproject/opensearch:2.18` does NOT exist. Use `:3` (latest 3.x) or `:2` (latest 2.x).
- Version 2.12+ requires `OPENSEARCH_INITIAL_ADMIN_PASSWORD` env var.
- `DISABLE_SECURITY_PLUGIN=true` makes OpenSearch serve on HTTP (not HTTPS).

### 0L.4 Working Commands Reference

```bash
# Start everything
docker compose up -d

# Open shell
docker compose exec frappe bash

# Run single command (non-TTY for pipes)
docker compose exec -T frappe bash -c "<command>"

# Start dev server (background)
docker compose exec -d frappe bash -c "cd /workspace/development/armure-apim && bench serve --port 8000"

# Test site
curl -s -H "Host: apim.localhost" http://localhost:8000/login

# Install app on site
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench --site apim.localhost install-app armure_apim_sentinel"

# Build assets
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench build"

# Set default site
docker compose exec frappe bash -c "cd /workspace/development/armure-apim && bench use apim.localhost"

# Add Python dependency — edit pyproject.toml (not requirements.txt)
# Then in container: bench pip install -e /workspace/development/armure-apim/apps/armure_apim_sentinel
```

### 0L.5 App Directory Structure

```
/workspace/development/armure-apim/apps/armure_apim_sentinel/
├── armure_apim_sentinel/      # Main Python package
│   ├── __init__.py            # Version: 0.0.1
│   ├── ...
│   ├── api/                   # API modules (create in Phase 1)
│   └── fixtures/              # Seed data JSON (create in Phase 1)
├── frontend/                  # Vue 3 SPA (create in Phase 6)
├── pyproject.toml             # Python deps here, not requirements.txt
├── README.md
└── license.txt
```

---

## Phase 0 — Docker Environment Setup

### 0.1 Create `.env` file

```bash
cat > /home/prolinux/dev/armure-apim-governance/armure-apim-sentinel/.env << 'EOF'
MYSQL_ROOT_PASSWORD=123
MARIADB_PORT=3306
BENCH_NAME=armure-apim
SITE_NAME=apim.localhost
ADMIN_PASSWORD=admin
FRAPPE_BRANCH=version-16
DB_TYPE=mariadb
BENCH_WEB_PORT=8000
BENCH_SOCKETIO_PORT=9000
OPENSEARCH_PORT=9200
EOF
```

- [x] **0.1.1** Create `.env` file at `/home/prolinux/dev/armure-apim-governance/armure-apim-sentinel/.env`

### 0.2 Add OpenSearch to docker-compose.yml

Insert an `opensearch` service (single-node, no security plugin) alongside `mariadb`, `redis-cache`, `redis-queue`, and `frappe`.

```yaml
opensearch:
  image: docker.io/opensearchproject/opensearch:3
  environment:
    - discovery.type=single-node
    - DISABLE_SECURITY_PLUGIN=true
    - DISABLE_INSTALL_DEMO_CONFIG=true
    - OPENSEARCH_INITIAL_ADMIN_PASSWORD=${OPENSEARCH_INITIAL_ADMIN_PASSWORD:-admin}
    - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
  ports:
    - "${OPENSEARCH_PORT:-9200}:9200"
    - "9600:9600"
  volumes:
    - opensearch-data:/usr/share/opensearch/data
  healthcheck:
    test: curl -s http://localhost:9200 >/dev/null || exit 1
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 60s
  restart: unless-stopped
```

Add `opensearch-data` volume to the `volumes:` block.

Add `opensearch:` to `frappe.depends_on`.

- [x] **0.2.1** Add OpenSearch service definition
- [x] **0.2.2** Add `opensearch-data` volume
- [x] **0.2.3** Add `opensearch` to frappe service `depends_on`

### 0.3 Start Docker services

```bash
cd /home/prolinux/dev/armure-apim-governance/armure-apim-sentinel
docker compose up -d
```

- [x] **0.3.1** Run `docker compose up -d`
- [x] **0.3.2** Verify all 5 containers are healthy: `docker compose ps`

### 0.4 Initialize Frappe Bench

The `frappe/bench:latest` image already has bench CLI pre-installed. No separate `bench init` is needed.
The bench is created under `/workspace/development/armure-apim/` with:
- Frappe framework cloned into `apps/frappe`
- Site `apim.localhost` created and configured
- Developer mode enabled
- Redis/MariaDB/OpenSearch connections configured via `common_site_config.json`

```bash
# Verify bench is ready
docker compose exec frappe bash -c "ls /workspace/development/armure-apim/apps/ && bench --version"
```

- [x] **0.4.1** Bench is pre-configured in the frappe/bench:latest container
- [x] **0.4.2** Verify bench structure exists at `/workspace/development/armure-apim/`

### 0.5 Create the custom app

```bash
# bench 5.x uses interactive prompts — pass values via echo:
docker compose exec -T frappe bash -c "cd /workspace/development/armure-apim && echo -e 'Armure APIM Sentinel\nReal-time API threat auditing and governance with OpenSearch and WebSockets\nArmure Suite\ndevelopment@armure.in\nmit\nn' | bench new-app armure_apim_sentinel"
```

> **Note:** Newer bench versions (6+) support silent mode flags:
> ```bash
> bench new-app armure_apim_sentinel \
>   --title "Armure APIM Sentinel" \
>   --description "Real-time API threat auditing and governance with OpenSearch and WebSockets" \
>   --publisher "Armure Suite" \
>   --icon "octicon octicon-shield" \
>   --color "blue" \
>   --email "development@armure.in" \
>   --license "mit"
> ```

- [x] **0.5.1** Create app via `bench new-app armure_apim_sentinel`
- [x] **0.5.2** Install on site: `bench --site apim.localhost install-app armure_apim_sentinel`

### 0.6 Start dev server & verify

```bash
# Start server in background
docker compose exec -d frappe bash -c "cd /workspace/development/armure-apim && bench serve --port 8000"

# Test with correct Host header (site is apim.localhost)
curl -s -H "Host: apim.localhost" http://localhost:8000/login
```

- [x] **0.6.1** Start bench web server in background
- [x] **0.6.2** Verify 200 response on login page with Host header `apim.localhost`
- [ ] **0.6.3** Confirm `armure_apim_sentinel` appears in App Switcher (requires authenticated login)

### 0.7 Install OpenSearch Python client

Add `opensearch-py` to `dependencies` in `pyproject.toml` (apps use pyproject.toml, not requirements.txt):

```toml
dependencies = [
    "opensearch-py",
    # "frappe~=16.0.0"
]
```

- [x] **0.7.1** Add `opensearch-py` to `pyproject.toml` dependencies

### 0.8 Create workspace files (reference docs)

Copy walkthrough and reference documents into the app directory for easy access during development.

- [x] **0.8.1** Copy `implementation-plan.md`, `frappe-ui-walkthrough.md`, `frappe-insights-walkthrough.md` into `development/armure-apim/apps/armure_apim_sentinel/`

---

## Phase 1 — App Scaffolding (Frappe)

> Reference: `implementation-plan.md` §3.1 Directory Layout, §9 Phase 1

### 1.1 Create directory structure

Create the Python module directories inside the app.

```bash
docker compose exec frappe bash -c "cd /workspace/development/armure-apim/apps/armure_apim_sentinel && mkdir -p armure_apim_sentinel/api armure_apim_sentinel/fixtures armure_apim_sentinel/public/js"
```

- [ ] **1.1.1** Create `api/` subdirectory with `__init__.py`
- [ ] **1.1.2** Create `fixtures/` subdirectory
- [ ] **1.1.3** Create `public/js/` subdirectory

### 1.2 Create `hooks.py` — metadata + hooks

Write the initial `hooks.py` with all configuration entries per `implementation-plan.md` §3.2: app metadata, permission hooks, website route rules, doctype JS, scheduler, lifecycle hooks, app screen visibility.

- [ ] **1.2.1** Write `hooks.py` (permission hooks, scheduler, website_route_rules, after_migrate, add_to_apps_screen)

### 1.3 Create `__init__.py`

App package init — keep minimal, just docstring and version.

- [ ] **1.3.1** Write `armure_apim_sentinel/__init__.py`

### 1.4 Create `install.py` (after_migrate seed function)

Write the idempotent seed function that creates:
- 4 Log Ingest Adapters (Auth Service, Billing Gateway, Catalog Engine, Data Collector)
- 3 Security Alert Rules (latency spike, high HTTP error, rate limit exhaustion)
- API Security App Settings singleton

- [ ] **1.4.1** Write `install.py` with `after_migrate()` function

### 1.5 Create `uninstall.py`

Cleanup hook for `before_uninstall`.

- [ ] **1.5.1** Write `uninstall.py` stub

### 1.6 Create `doc_events.py`

Rule `on_update` → invalidate Redis cache.

- [ ] **1.6.1** Write `doc_events.py`

### 1.7 Run bench migrate

Apply DocType schema changes (empty for now, Fixture phase creates the actual DocTypes).

- [ ] **1.7.1** Run `bench migrate` to verify hooks are valid

---

## Phase 2 — DocType Definitions

> Reference: `implementation-plan.md` §2 Data Model, §9 Phase 2

### 2.1 Create API Security App Settings (Singleton)

DocType with fields: `opensearch_host`, `opensearch_port`, `opensearch_user`, `opensearch_password`, `enable_live_simulation`, `simulation_interval_ms`.

- [ ] **2.1.1** Create DocType via Frappe UI or via JSON file
- [ ] **2.1.2** Set as Singleton

### 2.2 Create Log Ingest Adapter

DocType with fields: `channel_name`, `protocol_type` (Select), `secret_token` (Password), `status` (Select: Active/Inactive), `total_logs_received` (Int, read-only).

- [ ] **2.2.1** Create DocType with fields
- [ ] **2.2.2** Set `channel_name` as unique + mandatory

### 2.3 Create Security Alert Rule

DocType with fields: `rule_name`, `metric` (Select: latency/status_code/rate_limit), `condition` (Select: gt/lt/eq), `threshold` (Int), `duration` (Int), `severity` (Select: info/warning/critical), `is_active` (Check).

- [ ] **2.3.1** Create DocType with fields

### 2.4 Create Alert Instance

DocType with fields: `rule` (Link → Security Alert Rule), `alert_message` (Text), `severity` (Select), `alert_type` (Select: System/AI), `resolved` (Check), `details` (Code), `timestamp` (Datetime, default Now).

- [ ] **2.4.1** Create DocType with fields

### 2.5 Create AI Audit Assessment

DocType with fields: `scan_time` (Datetime, default Now), `anomaly_score` (Float 0-100), `generated_summary` (Text Editor), `triggered_alerts_count` (Int).

- [ ] **2.5.1** Create DocType with fields

### 2.6 Create fixture JSON files

Create seed data JSON files in `fixtures/` for default Log Ingest Adapters and Security Alert Rules.

- [ ] **2.6.1** Create `fixtures/log_ingest_adapter.json` — 4 seed sources
- [ ] **2.6.2** Create `fixtures/security_alert_rule.json` — 3 default rules

### 2.7 Run bench migrate

- [ ] **2.7.1** Run `bench migrate` to apply all 5 DocTypes

### 2.8 Verify DocTypes

- [ ] **2.8.1** `bench console` → `frappe.get_single("API Security App Settings")` returns singleton
- [ ] **2.8.2** Verify all 5 DocType tables exist in database

---

## Phase 3 — Backend Python Modules

> Reference: `implementation-plan.md` §3 Backend Architecture, §4 API Endpoint Mapping, §9 Phase 3

### 3.1 Create `decorators.py`

Custom `@whitelist(role, allow_guest, methods)` decorator combining `@frappe.whitelist` + role check + 403 response. Include `@validate_type` helper.

- [ ] **3.1.1** Write `decorators.py` with `whitelist()` and `validate_type()`

### 3.2 Create `permissions.py`

DocType-level permission hooks: `get_permission_query_conditions` and `has_permission` for all 4 doctypes (Log Ingest Adapter, Security Alert Rule, Alert Instance, AI Audit Assessment).

- [ ] **3.2.1** Write `permissions.py` with permission query conditions and has_permission for System Manager role

### 3.3 Create `opensearch_client.py`

OpenSearch connection client:
- `get_client()` — returns OpenSearch client from App Settings
- `ensure_index()` — creates daily index with mapping if not exists
- `index_log()` — indexes a single log document
- `bulk_index()` — indexes multiple log documents
- `search_logs()` — query logs with filters
- `aggregate_dashboard()` — dashboard summary/charts/breakdown aggregations

- [ ] **3.3.1** Write `opensearch_client.py` — client setup + ensure_index + index_log
- [ ] **3.3.2** Add `search_logs()` with filter support (search, source, status, method, latency, time range)
- [ ] **3.3.3** Add `aggregate_dashboard()` — summary, charts, breakdown

Index mapping per `implementation-plan.md` §2.6.

### 3.4 Create `realtime.py`

Realtime publish helpers:
- `publish_alert(alert_data)` — publishes `security_anomaly_triggered`
- `publish_scan_complete(report_data)` — publishes `security_scan_complete`

- [ ] **3.4.1** Write `realtime.py`

### 3.5 Create `utils.py`

Rule evaluation engine + Redis caching:
- `evaluate_rules_for_log(log_payload)` — ported from `server.ts` `evaluateRulesForLog()`
- Redis cache helpers: `get_cached(key)`, `set_cached(key, value, ttl)`, `invalidate(prefix)`
- Category helpers: `get_severity_theme(severity)`, `format_latency(ms)`, etc.

- [ ] **3.5.1** Write rule evaluation engine in `utils.py`
- [ ] **3.5.2** Write Redis cache helpers in `utils.py`

### 3.6 Create `api/dashboard.py`

Three endpoints:
- `get_summary(period=24)` — aggregate KPIs (totalRequests, avgLatency, successRate, errorCount, rateLimitCount, activeAlerts)
- `get_charts(period=24)` — date histogram with dynamic bucket sizing
- `get_breakdown(period=24)` — per-source, per-status-code, per-endpoint breakdown

Use `@whitelist(role="System Manager")` on all three.

- [ ] **3.6.1** Write `get_summary()`
- [ ] **3.6.2** Write `get_charts()`
- [ ] **3.6.3** Write `get_breakdown()`

### 3.7 Create `api/logs.py`

Two endpoints:
- `query_logs(search=None, source=None, status=None, method=None, min_latency=None, max_latency=None, start=None, end=None, page=1, page_size=50)` — filtered log query from OpenSearch
- `ingest_logs()` — POST handler with X-Ingest-Token validation, enqueues to RQ worker

- [ ] **3.7.1** Write `query_logs()` with 8 filter params + pagination
- [ ] **3.7.2** Write `ingest_logs()` with token validation + bulk enqueue

### 3.8 Create `api/sources.py`

CRUD endpoints for Log Ingest Adapter:
- `create_source()` — creates adapter, auto-generates secret_token
- `toggle_source(name)` — flips active/inactive
- `delete_source(name)` — deletes adapter

- [ ] **3.8.1** Write `create_source()`
- [ ] **3.8.2** Write `toggle_source()`
- [ ] **3.8.3** Write `delete_source()`

### 3.9 Create `api/rules.py`

CRUD endpoints for Security Alert Rule:
- `create_rule()` — creates new rule
- `update_rule(name)` — update fields or toggle enabled
- `delete_rule(name)` — deletes rule

- [ ] **3.9.1** Write `create_rule()`
- [ ] **3.9.2** Write `update_rule()`
- [ ] **3.9.3** Write `delete_rule()`

### 3.10 Create `api/alerts.py`

Alert management:
- `resolve_all()` — resolves all unresolved alerts
- `resolve_one(name)` — resolves specific alert

- [ ] **3.10.1** Write `resolve_all()`
- [ ] **3.10.2** Write `resolve_one()`

### 3.11 Create `api/simulation.py`

Simulation config management:
- `update_config()` — updates App Settings singleton (enable/disable, interval)

- [ ] **3.11.1** Write `update_config()`

### 3.12 Create `api/ai_gemini.py`

Gemini AI integration endpoints:

```python
@whitelist(role="System Manager")
def explain_error(log_id):
    """Fetch log from OpenSearch by id, send to Gemini, return markdown."""
```

```python
@whitelist(role="System Manager")
def run_anomaly_scan():
    """Fetch last 85 logs from OpenSearch, aggregate, send to Gemini,
    create AI Audit Assessment + Alert Instance if score > 40,
    publish realtime event."""
```

```python
@whitelist(role="System Manager")
def get_scan_history():
    """Return list of AI Audit Assessment DocTypes."""
```

- [ ] **3.12.1** Write `explain_error()`
- [ ] **3.12.2** Write `run_anomaly_scan()`
- [ ] **3.12.3** Write `get_scan_history()`

### 3.13 Create `tasks.py`

Background task for simulation:

```python
def generate_simulated_logs():
    """Port of feedSingleLiveLog() from server.ts.
    - Read App Settings (enable_live_simulation gate)
    - Generate log with same path/method templates
    - Inject anomaly patterns (auth outage at hour 14,
      rate-limit every 25th, random 4-8% error noise)
    - Index to OpenSearch
    - Run rule evaluation"""
```

- [ ] **3.13.1** Write `generate_simulated_logs()` in `tasks.py`

### 3.14 Update `hooks.py` (finalize)

Ensure `hooks.py` has:
- `scheduler_events` → cron `*/1 * * * *` calling `tasks.generate_simulated_logs`
- `website_route_rules` → `/api-security-monitor/<path:app_path>` → page handler
- All permission hooks registered
- `after_migrate` pointing to `install.after_migrate`

- [ ] **3.14.1** Finalize `hooks.py` with all entries

### 3.15 Test all API endpoints

- [ ] **3.15.1** Test dashboard endpoints return correct structure (even with empty OpenSearch)
- [ ] **3.15.2** Test log query with empty cluster returns graceful zero-state
- [ ] **3.15.3** Test source CRUD via Frappe API
- [ ] **3.15.4** Test alert resolve via API
- [ ] **3.15.5** Test `@whitelist` returns 403 for non-System-Manager

---

## Phase 4 — Rule Evaluation + Redis Caching

> Reference: `implementation-plan.md` §9 Phase 4

### 4.1 Cache active rules in Redis

- [ ] **4.1.1** On rule create/update/delete, invalidate `active_rules` cache
- [ ] **4.1.2** In `evaluate_rules_for_log()`, fetch active rules from Redis (30min TTL) instead of DB

### 4.2 Cache dashboard aggregates in Redis

- [ ] **4.2.1** In dashboard endpoints, check Redis cache first (5s TTL) before querying OpenSearch
- [ ] **4.2.2** After OpenSearch query, store result in Redis with 5s TTL

### 4.3 Invalidation on rule changes

- [ ] **4.3.1** Wire `doc_events.py` → `on_update` for Security Alert Rule → invalidate active rules cache

### 4.4 Test caching

- [ ] **4.4.1** Verify dashboard returns stale data within 5s window, refreshes after
- [ ] **4.4.2** Verify rule changes take effect within 30s (max cache TTL)

---

## Phase 5 — Simulation Engine

> Reference: `implementation-plan.md` §7, §9 Phase 5

### 5.1 Implement log generation logic

Port from `server.ts` `feedSingleLiveLog()`:
- Random selection from 4 sources, 8 API paths, 9 IPs, 6 User-Agents
- Normal distribution: latency ~80–300ms, payload ~200–4000 bytes
- Anomaly injection:
  - Auth outage at hour 14 UTC (elevated 500s + 2000ms+ latency)
  - Rate-limit spike every 25th log (rate_limit_remaining = 0)
  - Random 4-8% error noise (503, 404, 401)

- [ ] **5.1.1** Write `generate_log()` function in `tasks.py`
- [ ] **5.1.2** Write anomaly injection logic

### 5.2 Wire to cron schedule

- [ ] **5.2.1** Ensure `hooks.py` has the `*/1 * * * *` cron entry

### 5.3 Test simulation

- [ ] **5.3.1** Wait for cron to fire, verify logs appear in OpenSearch
- [ ] **5.3.2** Turn off simulation via App Settings, verify cron skips
- [ ] **5.3.3** Verify anomaly patterns are detectable in OpenSearch queries

---

## Phase 6 — Vue 3 Frontend

> Reference: `implementation-plan.md` §5 Frontend Architecture, §9 Phase 6

### 6a. Bootstrap

#### 6a.1 Create frontend package.json

```bash
cd /workspace/development/armure-apim/apps/armure_apim_sentinel/frontend
npm init -y
npm install vue vue-router pinia frappe-ui echarts vue-echarts
npm install -D vite@^5 @vitejs/plugin-vue@^5 tailwindcss@^3.4 postcss autoprefixer unplugin-icons unplugin-auto-import unplugin-vue-components lucide-static @iconify/json
```

- [ ] **6a.1.1** Run npm init and install dependencies

#### 6a.2 Create Vite config

Write `frontend/vite.config.js` — `frappeui()` plugin, Vite 5, `optimizeDeps` exclude/include, dev server proxy to localhost:8000.

- [ ] **6a.2.1** Write `vite.config.js`

#### 6a.3 Create Tailwind + PostCSS config

- [ ] **6a.3.1** Write `postcss.config.js`
- [ ] **6a.3.2** Write `tailwind.config.js` with frappe-ui preset

#### 6a.4 Create CSS entry

- [ ] **6a.4.1** Write `src/style.css` — `@import 'frappe-ui/style.css'` + Tailwind directives

#### 6a.5 Create main.js

App bootstrap: createApp, Pinia, FrappeUI plugin, provide $dayjs and $notify, mount.

- [ ] **6a.5.1** Write `src/main.js`

#### 6a.6 Create App.vue

Root layout: FrappeUIProvider + `<Suspense>` wrapping `<router-view>` with centered Spinner fallback.

- [ ] **6a.6.1** Write `src/App.vue`

#### 6a.7 Create router.js

4 routes (Dashboard, Logs, Alerts, Sources) + `beforeEach` auth guard checking `sessionStore`.

- [ ] **6a.7.1** Write `src/router.js` with routes + auth guard

#### 6a.8 Create api/index.js

Shared `useCall` wrapper with base URL and error handling defaults.

- [ ] **6a.8.1** Write `src/api/index.js`

#### 6a.9 Create sessionStore.js

Pinia store: `user`, `isLoggedIn`, `initialized`, `init()` (calls `frappe.auth.get_logged_user`), `logout()`.

- [ ] **6a.9.1** Write `src/stores/sessionStore.js`

#### 6a.10 Create index.html

- [ ] **6a.10.1** Write `frontend/index.html`

### 6b. App Shell & Shared Components

#### 6b.1 Create SuspenseFallback.vue

- [ ] **6b.1.1** Write `src/components/layout/SuspenseFallback.vue`

#### 6b.2 Create AppSidebar.vue

Nav tabs (4), UTC clock (updating every second), live status indicator (pulsing dot), active alert badge count.

- [ ] **6b.2.1** Write `src/components/layout/AppSidebar.vue`

#### 6b.3 Create MetricsCards.vue

4 KPI cards: Total Requests, Avg Latency (color-coded), Success Rate (color-coded), Active Alerts (animated if > 0). Loading, empty, and error states.

- [ ] **6b.3.1** Write `src/components/dashboard/MetricsCards.vue`

#### 6b.4 Create shared components

- [ ] **6b.4.1** Write `EmptyState.vue` — centered icon + message + CTA button
- [ ] **6b.4.2** Write `ErrorBanner.vue` — dismissible error banner
- [ ] **6b.4.3** Write `StatusBadge.vue` — status badge with theme map

### 6c. Pinia Store

#### 6c.1 Create telemetry.js

Complete Pinia store: `logs`, `alerts`, `scanHistory`, `dashboardMetrics`, `dashboardCharts`, `dashboardBreakdown`, `sources`, `rules`, `isScanning`, `theme`, `realtimeReady`. Actions: `fetchDashboard()`, `fetchLogs()`, `fetchSources()`, `fetchRules()`, `fetchAlerts()`, `fetchScanHistory()`, `toggleTheme()`, `initRealtime()`.

- [ ] **6c.1.1** Write `src/stores/telemetry.js`

### 6d. Composables

#### 6d.1 Create useDashboard.js

Composable wrapping: `useDashboardSummary(period)`, `useDashboardCharts(period)`, `useDashboardBreakdown(period)` using `useCall` + `Object.assign(state, { methods })` pattern.

- [ ] **6d.1.1** Write `src/composables/useDashboard.js`

#### 6d.2 Create useLogs.js

Composable wrapping: log query, CSV export, Gemini explain.

- [ ] **6d.2.1** Write `src/composables/useLogs.js`

#### 6d.3 Create useAlerts.js

Composable wrapping: alert list, resolve, rule CRUD.

- [ ] **6d.3.1** Write `src/composables/useAlerts.js`

#### 6d.4 Create useSources.js

Composable wrapping: source CRUD, simulation config, JSON/CSV ingest.

- [ ] **6d.4.1** Write `src/composables/useSources.js`

### 6e. Pages

#### 6e.1 Create DashboardPage.vue

Charts (vue-echarts: traffic volume area, latency bars, status code donut), source/status/endpoint breakdown tables, anomaly score trend line, time controls (2h / 24h / 3d + date range picker + Clear Lens), explore-to-logs navigation.

Conditional states: loading (spinners on each chart), empty ("No data yet"), error (fetch failure banner), color-coded thresholds on latency and error rate.

- [ ] **6e.1.1** Write `DashboardPage.vue`

#### 6e.2 Create LogsPage.vue

Filters bar (search input, source dropdown, status groups, method dropdown, latency min/max, datetime start/end with Reset), log table (ListView with status/method/path/source/IP/latency/timestamp), Trace Inspector (Dialog with full metadata + headers + response body), Gemini "Explain Trace Cause" button with loading/error states, CSV export with preview modal + download.

Conditional states: loading, empty ("No logs match filters"), error, disabled (export when no logs).

- [ ] **6e.2.1** Write `LogsPage.vue`

#### 6e.3 Create AlertsPage.vue

3-tab layout (TabButtons): Triggered, Rules & Policies, AI Scanner.
- Triggered tab: alert cards with severity badges (red/orange/blue), resolve buttons, empty "System Operations Normal"
- Rules tab: card layout with enable/disable switch, delete icon, create rule form (Dialog)
- AI Scanner: scan trigger button with loading spinner, score gauge (color-coded), markdown report rendering, history list

- [ ] **6e.3.1** Write `AlertsPage.vue`

#### 6e.4 Create SourcesPage.vue

Simulation controls: Active/Paused toggle, speed buttons (Slow/Medium/Extreme), state/info boxes.
Source CRUD: add form (Dialog), enable/disable toggle, delete.
JSON ingest: paste textarea with DDoS/SlowDB/DataLoad preset buttons, feedback banners.
CSV ingest: FileUploader with parsing.

- [ ] **6e.4.1** Write `SourcesPage.vue`

### 6f. Create Frappe page route for SPA

Create a page file that serves the Vue SPA:

```python
# armure_apim_sentinel/www/api_security_monitor.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Armure APIM Sentinel</title>
    {{ head }}
</head>
<body>
    <div id="app"></div>
    <script type="module" src="/assets/armure_apim_sentinel/frontend/src/main.js"></script>
</body>
</html>
```

- [ ] **6f.1** Create `www/api_security_monitor.html` page template
- [ ] **6f.2** Build frontend: `npm run build` → output to `armure_apim_sentinel/public/frontend/`
- [ ] **6f.3** Verify SPA loads at http://localhost:8000/api-security-monitor/

### 6g. Test frontend

- [ ] **6g.1** Sidebar shows 4 nav tabs, UTC clock, live indicator, alert badge
- [ ] **6g.2** MetricsCards show correct data with all conditional states
- [ ] **6g.3** Dashboard charts render, time controls work, breakdown tables populate
- [ ] **6g.4** LogViewer filters work, table renders, trace inspector opens, CSV exports
- [ ] **6g.5** AlertsPanel 3-tab switching works, resolve/CRUD/AI scan flows work
- [ ] **6g.6** SourceConfig simulation toggle, CRUD, JSON/CSV ingest all work
- [ ] **6g.7** Theme toggle persists, dark/light mode renders correctly
- [ ] **6g.8** All 73+ conditional UI states render correctly (loading spinners, empty states, error banners, disabled buttons, color thresholds, animations)

---

## Phase 7 — Realtime WebSocket Integration

> Reference: `implementation-plan.md` §6, §9 Phase 7

### 7.1 Wire publish into alert creation

- [ ] **7.1.1** In `evaluate_rules_for_log()`, call `realtime.publish_alert()` after creating Alert Instance

### 7.2 Wire publish into anomaly scan

- [ ] **7.2.1** In AI scan endpoint, call `realtime.publish_scan_complete()` after creating AI Audit Assessment

### 7.3 Frontend event listeners

In `telemetry.js` `initRealtime()`:
- `frappe.realtime.on('security_anomaly_triggered', ...)` — unshift to alerts, refresh metrics
- `frappe.realtime.on('security_scan_complete', ...)` — update scanHistory, add alert

- [ ] **7.3.1** Write `initRealtime()` in `telemetry.js`
- [ ] **7.3.2** Call `initRealtime()` in `App.vue` on mount

### 7.4 Test realtime

- [ ] **7.4.1** Trigger alert via simulation → verify realtime event received in browser
- [ ] **7.4.2** Trigger anomaly scan → verify scan completed event received

---

## Phase 8 — End-to-End Verification

> Reference: `implementation-plan.md` §10 Verification Checklist

### 8.1 Backend verification

- [ ] **8.1.1** All 20 API endpoints respond correctly
- [ ] **8.1.2** Role enforcement: non-System-Manager gets 403
- [ ] **8.1.3** Guest ingest endpoint works without auth (X-Ingest-Token validation)
- [ ] **8.1.4** OpenSearch indices created, logs searchable
- [ ] **8.1.5** Redis caching returns stale data within TTL, refreshes after
- [ ] **8.1.6** Simulation task runs on cron, anomaly patterns injected

### 8.2 Frontend verification

- [ ] **8.2.1** Router guard redirects to login, SPA loads after auth
- [ ] **8.2.2** All 4 pages render, nav between them works
- [ ] **8.2.3** All 73+ conditional states render correctly
- [ ] **8.2.4** Dark/light theme toggle works, persists

### 8.3 Integration verification

- [ ] **8.3.1** Full flow: simulation → log → OpenSearch → rules → alert → realtime → frontend
- [ ] **8.3.2** Full flow: anomaly scan → OpenSearch → Gemini → DocType → realtime → frontend
- [ ] **8.3.3** Full flow: CSV ingest → parse → OpenSearch → rules → alerts
- [ ] **8.3.4** Full flow: dashboard filters → OpenSearch aggregation → charts update

### 8.4 Edge cases

- [ ] **8.4.1** Empty OpenSearch cluster — dashboard returns graceful zero-state
- [ ] **8.4.2** Gemini API key not set — endpoints return friendly message
- [ ] **8.4.3** Invalid CSV — clear error message
- [ ] **8.4.4** Empty JSON payload — clear error message
- [ ] **8.4.5** Large time range (>72h) — auto-bucket to daily
- [ ] **8.4.6** All sources disabled — simulation skips inactive
- [ ] **8.4.7** All rules disabled — no alerts generated
- [ ] **8.4.8** 2000+ logs — pagination works

---

## Tracking

---

## Phase 9 — Richer Rule Criteria Enhancement

> Reference: `implementation-plan.md` §11 Enhancements — Richer Rule Criteria
> Implements: API selection filtering (method, path, source, IP, UA, payload, status range) + count-based sliding window evaluation

### 9.1 Update Security Alert Rule DocType

Add 14 new fields to the DocType JSON:

| # | Field | Fieldtype | Options / Default | Notes |
|---|---|---|---|---|
| 1 | `filter_method` | Select | `Any\nGET\nPOST\nPUT\nDELETE\nPATCH` | default `Any` |
| 2 | `filter_path_pattern` | Data | | glob or regex, empty = any path |
| 3 | `filter_path_search_type` | Select | `glob\nregex` | default `glob` |
| 4 | `filter_source` | Link → Log Ingest Adapter | | empty = any source |
| 5 | `filter_ip_range` | Data | | comma-separated CIDRs/IPs, empty = any |
| 6 | `filter_user_agent_pattern` | Data | | glob or regex, empty = any UA |
| 7 | `filter_user_agent_search_type` | Select | `glob\nregex` | default `glob` |
| 8 | `filter_min_payload` | Int | `0` | 0 = no minimum |
| 9 | `filter_max_payload` | Int | `0` | 0 = no maximum |
| 10 | `filter_status_min` | Int | `0` | 0 = no minimum |
| 11 | `filter_status_max` | Int | `0` | 0 = no maximum |
| 12 | `count_based` | Check | `0` | enable sliding window |
| 13 | `evaluation_window` | Int | `5` | minutes |
| 14 | `min_trigger_count` | Int | `1` | alerts triggered when count >= this |
| 15 | `group_by` | Select | `none\nsource\nip\npath\nmethod` | default `none` |

- [ ] **9.1.1** Add filter_method, filter_path_pattern, filter_path_search_type, filter_source fields
- [ ] **9.1.2** Add filter_ip_range, filter_user_agent_pattern, filter_user_agent_search_type fields
- [ ] **9.1.3** Add filter_min_payload, filter_max_payload, filter_status_min, filter_status_max fields
- [ ] **9.1.4** Add count_based, evaluation_window, min_trigger_count, group_by fields
- [ ] **9.1.5** Update field_order in DocType JSON
- [ ] **9.1.6** Run `bench migrate` to apply schema changes

### 9.2 Update Rule Evaluation Engine (utils.py)

- [ ] **9.2.1** Update `get_cached_rules()` to fetch all new filter fields
- [ ] **9.2.2** Write `_matches_filters(log, rule)` — applies filter pipeline (method, path glob/regex, source, IP CIDR, UA glob/regex, payload bounds, status bounds)
- [ ] **9.2.3** Write `_match_ip_range(ip_str, ranges_str)` — parse comma-separated CIDRs via `ipaddress` module
- [ ] **9.2.4** Write `_match_path_pattern(path, pattern, search_type)` — glob via `fnmatch`, regex via `re.match`
- [ ] **9.2.5** Write `_match_user_agent_pattern(ua, pattern, search_type)` — same as path
- [ ] **9.2.6** Write `_check_count_based_rule(rule, log)` — Redis INCR/EXPIRE, dedup flag
- [ ] **9.2.7** Refactor `evaluate_rules_for_log()` — insert filter pipeline before metric check, branch to count-based when `count_based=1`
- [ ] **9.2.8** Write `_build_group_by_value(rule, log)` — extract grouping dimension from log
- [ ] **9.2.9** Write unit tests for filter matching functions (in bench console or via test script)

### 9.3 Update Seed Rules (install.py)

- [ ] **9.3.1** Update existing 3 seed rules to include new filter fields (empty/defaults)
- [ ] **9.3.2** Add new seed rule: `"Suspicious POST Pattern"` — filter_method=POST, filter_path_pattern=`/api/v1/users/*`, count_based=1, evaluation_window=2, min_trigger_count=10, group_by=ip

### 9.4 Update API Endpoints

- [ ] **9.4.1** Update `api/alerts.py` `create_rule()` — accept all 15 new fields in request body
- [ ] **9.4.2** Update `api/alerts.py` `list_rules()` — include all new fields in response
- [ ] **9.4.3** Update `api/alerts.py` `toggle_rule()` — accept update for new fields (optional)

### 9.5 Update Frontend Rule Form (AlertsPage.vue)

- [ ] **9.5.1** Add collapsible "Advanced API Selection" section between metric and threshold fields
- [ ] **9.5.2** Add method select (Any/GET/POST/PUT/DELETE/PATCH) with `newRule.filterMethod`
- [ ] **9.5.3** Add path pattern input + search type toggle (glob/regex) with `newRule.filterPathPattern`/`newRule.filterPathSearchType`
- [ ] **9.5.4** Add source select (populated from `telemetry.sources`) with `newRule.filterSource`
- [ ] **9.5.5** Add IP range input (comma-separated CIDR) with `newRule.filterIpRange`
- [ ] **9.5.6** Add user-agent pattern input + search type toggle with `newRule.filterUserAgentPattern`/`newRule.filterUserAgentSearchType`
- [ ] **9.5.7** Add payload min/max inputs with `newRule.filterMinPayload`/`newRule.filterMaxPayload`
- [ ] **9.5.8** Add status min/max inputs with `newRule.filterStatusMin`/`newRule.filterStatusMax`
- [ ] **9.5.9** Add "Count-Based Evaluation" switch + evaluation window/min trigger count/group by fields
- [ ] **9.5.10** Update `newRule` defaults object with all new fields
- [ ] **9.5.11** Update `createRule()` to POST all new fields

### 9.6 Update Frontend Rule Display Card

- [ ] **9.6.1** Show active filter criteria as small badges below metric threshold in rule card (e.g., "POST", "/api/v1/users/*", "IP: 10.0.0.0/8")
- [ ] **9.6.2** Show count-based config when applicable ("Window: 5min, Min: 10 by IP")
- [ ] **9.6.3** Add empty/default state text when no filters active ("All traffic evaluated")

### 9.7 Test the Enhancement

- [ ] **9.7.1** Create rule with filter_method=POST, verify only POST logs trigger it
- [ ] **9.7.2** Create rule with filter_path_pattern=`/api/v1/billing/*`, verify only billing paths trigger
- [ ] **9.7.3** Create rule with filter_ip_range=`10.0.0.0/8`, verify only matching IPs trigger
- [ ] **9.7.4** Create rule with filter_user_agent_pattern=`*curl*`, verify only curl UAs trigger
- [ ] **9.7.5** Create rule with payload bounds, verify matching payload sizes trigger
- [ ] **9.7.6** Create rule with status bounds, verify matching status codes trigger
- [ ] **9.7.7** Create count-based rule, verify rolling window logic works (fast 5+ identical logs)
- [ ] **9.7.8** Create count-based rule with group_by=ip, verify separate counters per IP
- [ ] **9.7.9** Verify deduplication: same window doesn't create duplicate alerts
- [ ] **9.7.10** Verify existing rules (no filters) continue to work identically
- [ ] **9.7.11** Verify rule card displays filter criteria badges correctly
- [ ] **9.7.12** Verify rule form inputs all POST and persist correctly

---

## Tracking

| Phase | Total Tasks | Completed | Notes |
|-------|------------|-----------|-------|
| Phase 0 — Docker Setup | 18 | 16 | ✅ Complete |
| Phase 1 — App Scaffolding | 9 | 0 | |
| Phase 2 — DocTypes | 15 | 0 | |
| Phase 3 — Backend Python | 35 | 0 | Largest phase |
| Phase 4 — Rule Evaluation + Caching | 6 | 0 | |
| Phase 5 — Simulation Engine | 5 | 0 | |
| Phase 6 — Vue 3 Frontend | 40 | 0 | Second largest |
| Phase 7 — Realtime | 6 | 0 | |
| Phase 8 — Verification | 25 | 0 | |
| Phase 9 — Richer Rule Criteria | 51 | 0 | |
| **Total** | **210** | **16** | **7.6% complete** |

---

## Quick Reference

```bash
# Enter container
docker compose exec frappe bash
docker compose exec -T frappe bash  # non-TTY (for piping input)

# Navigate to bench
cd /workspace/development/armure-apim

# Bench commands
bench --site apim.localhost console
bench --site apim.localhost migrate
bench --site apim.localhost install-app armure_apim_sentinel

# Start dev server
bench serve --port 8000

# Test via curl (must use Host header since site is apim.localhost)
curl -s -H "Host: apim.localhost" http://localhost:8000/login

# Add Python dependency (edit pyproject.toml, not requirements.txt)
# apps use [project] dependencies in pyproject.toml

# Restart services
docker compose restart frappe

# App code location
cd /workspace/development/armure-apim/apps/armure_apim_sentinel

# Frontend dev
cd /workspace/development/armure-apim/apps/armure_apim_sentinel/frontend
npm run dev
```
