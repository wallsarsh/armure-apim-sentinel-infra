#!/bin/bash
#
# Frappe Bench Initialization Script
# Run this script INSIDE the frappe container to initialize the bench
#
# Usage: docker exec -it <container_name> bash -c "cd /workspace/development && bash init.sh"

set -e

BENCH_NAME="${BENCH_NAME:-armure-apim}"
SITE_NAME="${SITE_NAME:-apim.localhost}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
APPS_JSON="${APPS_JSON:-apps.json}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"
DB_TYPE="${DB_TYPE:-mariadb}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"

echo "=========================================="
echo "  Frappe Bench Initialization"
echo "=========================================="

# Check if bench already exists
if [ -d "$BENCH_NAME" ]; then
    echo "[✓] Bench '$BENCH_NAME' already exists."
    echo "    Skipping bench init. Only site will be created if needed."
else
    echo "[1/5] Initializing Frappe Bench..."
    echo "      Branch: $FRAPPE_BRANCH"
    echo "      Apps:   $APPS_JSON"

    bench init \
        --skip-redis-config-generation \
        --frappe-branch="$FRAPPE_BRANCH" \
	"$BENCH_NAME"
#        --apps_path="$APPS_JSON" \
#        --verbose \
#        "$BENCH_NAME"

    echo "[✓] Bench initialized successfully."
fi

cd "$BENCH_NAME"

echo "[2/5] Configuring database connection..."
bench set-config -g db_host "$DB_TYPE"
bench set-config -g db_type "$DB_TYPE"

echo "[3/5] Configuring Redis connections..."
bench set-config -g redis_cache "redis://redis-cache:6379"
bench set-config -g redis_queue "redis://redis-queue:6379"
bench set-config -g redis_socketio "redis://redis-queue:6379"

echo "[4/5] Setting developer mode..."
bench set-config -gp developer_mode 1

# Check if site already exists
if [ -d "sites/$SITE_NAME" ]; then
    echo "[✓] Site '$SITE_NAME' already exists. Skipping site creation."
else
    echo "[5/5] Creating development site '$SITE_NAME'..."
    bench new-site \
        --db-root-username=root \
        --db-host="$DB_TYPE" \
        --db-type="$DB_TYPE" \
        --mariadb-user-host-login-scope=% \
        --db-root-password="$MYSQL_ROOT_PASSWORD" \
        --admin-password="$ADMIN_PASSWORD" \
        "$SITE_NAME"

    echo "[✓] Site created successfully."
fi

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "  Bench:     /workspace/development/$BENCH_NAME"
echo "  Site:      $SITE_NAME"
echo "  Admin PW:  $ADMIN_PASSWORD"
echo ""
echo "  Start the development server:"
echo "    docker exec -it <container> bash -c 'cd /workspace/development/$BENCH_NAME && bench start'"
echo ""
echo "  Or start just the web server:"
echo "    docker exec -it <container> bash -c 'cd /workspace/development/$BENCH_NAME && bench serve --port 8000'"
echo ""
echo "  Then visit: http://localhost:8000"
echo "  Login:      Administrator / $ADMIN_PASSWORD"
echo "=========================================="
