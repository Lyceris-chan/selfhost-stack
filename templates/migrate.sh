#!/bin/sh
SERVICE=$1
ACTION=$2
BACKUP=${3:-yes}
CONTAINER_PREFIX="__CONTAINER_PREFIX__"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/app/data/backups"
DATA_DIR="/app/data"

log() { echo "[MIGRATE] $1"; }
mkdir -p "$BACKUP_DIR"

if [ "$SERVICE" = "invidious" ]; then

            if [ "$ACTION" = "clear" ]; then
            log "CLEARING Invidious database (resetting to defaults)..."
            if [ "$BACKUP" != "no" ]; then
                log "Creating safety backup..."
                docker exec ${CONTAINER_PREFIX}invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_BEFORE_CLEAR_$TIMESTAMP.sql"
            fi
            # Drop and recreate
            docker exec ${CONTAINER_PREFIX}invidious-db dropdb -U kemal invidious
            docker exec ${CONTAINER_PREFIX}invidious-db createdb -U kemal invidious
            docker exec ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh
            log "Invidious database cleared."
        elif [ "$ACTION" = "migrate" ]; then
            log "Starting Invidious migration..."
            # 1. Backup existing data
            if [ "$BACKUP" != "no" ] && [ -d "$DATA_DIR/postgres" ]; then
                log "Backing up Invidious database..."
                docker exec ${CONTAINER_PREFIX}invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_$TIMESTAMP.sql"
            fi
            # 2. Run migrations
            log "Applying schema updates..."
            docker exec ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh 2>&1 | grep -v "already exists" || true
            log "Invidious migration complete."
        elif [ "$ACTION" = "vacuum" ]; then
             log "Invidious (Postgres) handles vacuuming automatically. Skipping."
        fi
    elif [ "$SERVICE" = "adguard" ]; then
        if [ "$ACTION" = "clear-logs" ]; then
            log "Clearing AdGuard Home query logs..."
            find "$DATA_DIR/adguard-work" -name "querylog.json" -exec truncate -s 0 {} + 
            log "AdGuard logs cleared."
        fi
    elif [ "$SERVICE" = "memos" ]; then
        if [ "$ACTION" = "vacuum" ]; then
            log "Optimizing Memos database (VACUUM)..."
            docker exec ${CONTAINER_PREFIX}memos sqlite3 /var/opt/memos/memos_prod.db "VACUUM;" 2>/dev/null || log "Memos container not ready or sqlite3 missing."
            log "Memos database optimized."
        fi
    else
        if [ "$ACTION" = "vacuum" ]; then
            log "Vacuum not required/supported for $SERVICE."
        else
            log "No custom migration logic defined for $SERVICE."
        fi
    fi
