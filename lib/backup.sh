#!/usr/bin/env bash

# --- SECTION 17: BACKUP & SLOT MANAGEMENT ---

perform_backup() {
    local tag="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="backup_${tag}_${timestamp}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    log_info "Creating system backup: $backup_name..."
    
    # Backup secrets, config and dynamic state
    # We exclude large source directories and data volumes to keep it fast
    tar -czf "$BACKUP_DIR/$backup_name" \
        -C "$BASE_DIR" .secrets .active_slot config env \
        --exclude="sources" --exclude="data" 2>/dev/null
    
    log_info "Backup created successfully at $BACKUP_DIR/$backup_name"
    
    # Keep only last 5 backups
    ls -t "$BACKUP_DIR"/backup_* | tail -n +6 | xargs rm -f 2>/dev/null || true
}

swap_slots() {
    local old_slot="$CURRENT_SLOT"
    local new_slot="a"
    if [ "$old_slot" = "a" ]; then new_slot="b"; fi
    
    log_info "ORCHESTRATING SLOT SWAP: $old_slot -> $new_slot"
    
    # 1. Perform safety backup
    perform_backup "pre_swap"
    
    # 2. Update state for the rest of the script
    echo "$new_slot" > "$ACTIVE_SLOT_FILE"
    export CURRENT_SLOT="$new_slot"
    export CONTAINER_PREFIX="dhi-${new_slot}-"
    
    log_info "Standby slot ($new_slot) initialized. Preparing deployment..."
    
    # The rest of the main script (zima.sh) will now use the new prefix
    # when calling generate_compose and deploy_stack.
}

stop_inactive_slots() {
    local active_slot="$CURRENT_SLOT"
    local inactive_slot="a"
    if [ "$active_slot" = "a" ]; then inactive_slot="b"; fi
    
    local inactive_prefix="dhi-${inactive_slot}-"
    
    log_info "Cleaning up inactive slot ($inactive_slot) containers..."
    
    # Find all containers with the inactive prefix and stop/remove them
    local containers=$($DOCKER_CMD ps -a --format '{{.Names}}' | grep "^${inactive_prefix}" || true)
    if [ -n "$containers" ]; then
        $DOCKER_CMD rm -f $containers >/dev/null 2>&1 || true
        log_info "Inactive slot containers removed."
    fi
}
