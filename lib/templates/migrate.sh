#!/bin/sh
SERVICE=$1
ACTION=$2
BACKUP=${3:-yes}
CONTAINER_PREFIX="__CONTAINER_PREFIX__"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/app/data/backups"
DATA_DIR="/app/data"

log() {
    echo "[MIGRATE] $1"
    if [ -f "/app/deployment.log" ]; then
        printf '{"timestamp": "%s", "level": "INFO", "category": "MAINTENANCE", "source": "orchestrator", "message": "[MIGRATE] %s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "/app/deployment.log"
    fi
}
warn() {
    echo "[MIGRATE] ⚠️  WARNING: $1"
    if [ -f "/app/deployment.log" ]; then
        printf '{"timestamp": "%s", "level": "WARN", "category": "MAINTENANCE", "source": "orchestrator", "message": "[MIGRATE] %s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >> "/app/deployment.log"
    fi
}
mkdir -p "$BACKUP_DIR"

# Display warning for destructive actions
if [ "$ACTION" = "clear" ] || [ "$ACTION" = "clear-logs" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  ⚠️  DATA DELETION WARNING                                       │"
    echo "├─────────────────────────────────────────────────────────────────┤"
    echo "│  You are about to DELETE data from: $SERVICE"
    echo "│                                                                 │"
    echo "│  This may include personal notes, subscriptions, preferences,   │"
    echo "│  photos, or other data you have stored in this service.         │"
    echo "│                                                                 │"
    echo "│  If you have not backed up your data, consider doing so now:    │"
    echo "│  Backups are stored in: $BACKUP_DIR"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    if [ "$BACKUP" = "no" ]; then
        warn "Backup is DISABLED. Your data will be permanently lost!"
    else
        log "A backup will be created before deletion."
    fi
fi

if [ "$SERVICE" = "invidious" ]; then

            if [ "$ACTION" = "clear" ]; then
            log "CLEARING Invidious database (resetting to defaults)..."
            warn "This will delete ALL your Invidious subscriptions, watch history, and preferences!"
            if [ "$BACKUP" != "no" ]; then
                log "Creating safety backup..."
                PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_BEFORE_CLEAR_$TIMESTAMP.sql"
                log "Backup saved to: $BACKUP_DIR/invidious_BEFORE_CLEAR_$TIMESTAMP.sql"
            fi
            # Drop and recreate
            PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db dropdb -U kemal invidious
            PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db createdb -U kemal invidious
            PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh
            log "Invidious database cleared."
        elif [ "$ACTION" = "migrate" ]; then
            log "Starting Invidious migration..."
            # 1. Backup existing data
            if [ "$BACKUP" != "no" ] && [ -d "$DATA_DIR/postgres" ]; then
                log "Backing up Invidious database..."
                PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db pg_dump -U kemal invidious > "$BACKUP_DIR/invidious_$TIMESTAMP.sql"
                log "Backup saved to: $BACKUP_DIR/invidious_$TIMESTAMP.sql"
            fi
            # 2. Run migrations
            log "Applying schema updates..."
            PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh 2>&1 | grep -v "already exists" || true
            log "Invidious migration complete."
        elif [ "$ACTION" = "vacuum" ]; then
             log "Invidious (Postgres) handles vacuuming automatically. Skipping."
        fi
    elif [ "$SERVICE" = "adguard" ]; then
        if [ "$ACTION" = "clear-logs" ]; then
            log "Clearing AdGuard Home query logs..."
            warn "This will delete all DNS query history!"
            find "$DATA_DIR/adguard-work" -name "querylog.json" -exec truncate -s 0 {} + 
            log "AdGuard logs cleared."
        fi
    elif [ "$SERVICE" = "memos" ]; then
        if [ "$ACTION" = "vacuum" ]; then
            log "Optimizing Memos database (VACUUM)..."
            docker exec ${CONTAINER_PREFIX}memos sqlite3 /var/opt/memos/memos_prod.db "VACUUM;" 2>/dev/null || log "Memos container not ready or sqlite3 missing."
            log "Memos database optimized."
        elif [ "$ACTION" = "clear" ]; then
            warn "This will delete ALL your Memos notes and attachments!"
            if [ "$BACKUP" != "no" ]; then
                log "Creating safety backup..."
                cp -r "$DATA_DIR/../memos" "$BACKUP_DIR/memos_BEFORE_CLEAR_$TIMESTAMP" 2>/dev/null || true
                log "Backup saved to: $BACKUP_DIR/memos_BEFORE_CLEAR_$TIMESTAMP"
            fi
            log "Clear action for Memos requires manual intervention."
        fi
    else
        if [ "$ACTION" = "vacuum" ]; then
            log "Vacuum not required/supported for $SERVICE."
        else
            log "No custom migration logic defined for $SERVICE."
        fi
    fi
