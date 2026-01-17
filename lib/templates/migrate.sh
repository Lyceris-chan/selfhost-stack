#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail
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
		# Humanized style for direct file logs
		printf '{"timestamp": "%s", "level": "INFO", "category": "MAINTENANCE", "source": "orchestrator", "message": "Service maintenance: %s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >>"/app/deployment.log"
	fi
}
warn() {
	echo "[MIGRATE] ⚠️  WARNING: $1"
	if [ -f "/app/deployment.log" ]; then
		printf '{"timestamp": "%s", "level": "WARN", "category": "MAINTENANCE", "source": "orchestrator", "message": "Maintenance warning: %s"}\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" >>"/app/deployment.log"
	fi
}
mkdir -p "$BACKUP_DIR"

# Helper for generic service backup
do_backup() {
	local svc=$1
	log "Initiating database backup for $svc..."
	if [ "$svc" = "invidious" ]; then
		if PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db pg_dump -U kemal invidious >"$BACKUP_DIR/invidious_$TIMESTAMP.sql" 2>/dev/null; then
			log "Invidious database backup secured."
		else
			warn "Invidious database backup failed."
		fi
	elif [ "$svc" = "memos" ]; then
		if cp -r "$DATA_DIR/memos" "$BACKUP_DIR/memos_$TIMESTAMP" 2>/dev/null; then
			log "Memos data assets archived."
		else
			warn "Memos data archival failed."
		fi
	elif [ "$svc" = "immich" ]; then
		if PGPASSWORD="__IMMICH_DB_PASSWORD__" docker exec -e PGPASSWORD="__IMMICH_DB_PASSWORD__" ${CONTAINER_PREFIX}immich-db pg_dump -U immich immich >"$BACKUP_DIR/immich_$TIMESTAMP.sql" 2>/dev/null; then
			log "Immich database backup secured."
		else
			warn "Immich database backup failed."
		fi
	else
		log "No specialized backup required for $svc."
	fi
}

# Helper for generic service restore
do_restore() {
	local svc=$1
	local file=$2
	log "Initiating data restoration for $svc from $file..."
	if [ ! -f "$file" ]; then
		warn "Restore failed: Source file $file not found."
		return 1
	fi

	if [ "$svc" = "invidious" ]; then
		if PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -i -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db psql -U kemal invidious <"$file" 2>/dev/null; then
			log "Invidious database restoration complete."
		else
			warn "Invidious database restoration failed."
		fi
	elif [ "$svc" = "memos" ]; then
		rm -rf "$DATA_DIR/memos"
		if cp -r "$file" "$DATA_DIR/memos" 2>/dev/null; then
			log "Memos data assets restored."
		else
			warn "Memos data restoration failed."
		fi
	else
		log "No specialized restore logic for $svc."
	fi
}

# Route actions
if [ "$ACTION" = "backup" ]; then
	do_backup "$SERVICE"
	exit 0
elif [ "$ACTION" = "restore" ]; then
	do_restore "$SERVICE" "$3"
	exit 0
elif [ "$ACTION" = "backup-all" ]; then
	log "Initiating full stack maintenance backup..."
	for s in invidious memos immich; do
		do_backup "$s"
	done
	log "Full stack maintenance backup completed."
	exit 0
fi

if [ "$SERVICE" = "invidious" ]; then
	if [ "$ACTION" = "clear" ]; then
		log "Resetting Invidious database to factory defaults..."
		if [ "$BACKUP" != "no" ]; then do_backup "invidious"; fi
		PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db dropdb -U kemal invidious || true
		PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db createdb -U kemal invidious
		PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh
		log "Invidious database reset successful."
	elif [ "$ACTION" = "migrate" ] || [ "$ACTION" = "migrate-no-backup" ]; then
		log "Synchronizing Invidious database schema..."
		if [ "$ACTION" = "migrate" ]; then do_backup "invidious"; fi
		PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" docker exec -e PGPASSWORD="__INVIDIOUS_DB_PASSWORD__" ${CONTAINER_PREFIX}invidious-db /bin/sh /docker-entrypoint-initdb.d/init-invidious-db.sh 2>&1 | grep -v "already exists" || true
		log "Invidious schema synchronization complete."
	fi
elif [ "$SERVICE" = "adguard" ]; then
	if [ "$ACTION" = "clear-logs" ]; then
		log "Purging AdGuard Home query telemetry..."
		find "$DATA_DIR/adguard-work" -name "querylog.json" -exec truncate -s 0 {} +
		log "AdGuard telemetry purge complete."
	fi
elif [ "$SERVICE" = "memos" ]; then
	if [ "$ACTION" = "vacuum" ]; then
		log "Optimizing Memos database storage..."
		docker exec ${CONTAINER_PREFIX}memos sqlite3 /var/opt/memos/memos_prod.db "VACUUM;" 2>/dev/null || log "Memos container busy or sqlite3 unavailable."
		log "Memos storage optimization complete."
	elif [ "$ACTION" = "clear" ]; then
		log "Resetting Memos database to factory defaults..."
		if [ "$BACKUP" != "no" ]; then do_backup "memos"; fi
		log "Resetting Memos requires manual container restart."
	fi
else
	log "Maintenance action $ACTION for $SERVICE skipped (not applicable)."
fi
