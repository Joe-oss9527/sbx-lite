#!/usr/bin/env bash
# lib/backup.sh - Backup and restore functionality
# Part of sbx-lite modular architecture

# Prevent multiple sourcing
[[ -n "${_SBX_BACKUP_LOADED:-}" ]] && return 0
readonly _SBX_BACKUP_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Configuration
#==============================================================================

BACKUP_DIR="${BACKUP_DIR:-/var/backups/sbx}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

#==============================================================================
# Backup Creation
#==============================================================================

# Create comprehensive backup of sing-box configuration
backup_create() {
  local encrypt="${1:-false}"
  local backup_name="sbx-backup-$(date +%Y%m%d-%H%M%S)"
  local temp_dir
  temp_dir=$(mktemp -d) || die "Failed to create temp directory"
  local backup_root="$temp_dir/$backup_name"

  msg "Creating backup: $backup_name"

  # Create backup structure
  mkdir -p "$backup_root"/{config,certificates,binary,service}

  # Backup metadata
  cat > "$backup_root/metadata.json" <<EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "sing-box_version": "$($SB_BIN version 2>/dev/null | head -1 || echo 'unknown')",
  "backup_version": "1.0"
}
EOF

  # Backup configuration files
  if [[ -f "$SB_CONF" ]]; then
    cp "$SB_CONF" "$backup_root/config/config.json"
    success "  ✓ Backed up configuration"
  else
    warn "  ⚠ No configuration file found"
  fi

  if [[ -f "$CLIENT_INFO" ]]; then
    cp "$CLIENT_INFO" "$backup_root/config/client-info.txt"
    success "  ✓ Backed up client info"
  fi

  # Backup certificates
  local cert_found=false
  if [[ -d "$CERT_DIR_BASE" ]]; then
    for domain_dir in "$CERT_DIR_BASE"/*; do
      [[ -d "$domain_dir" ]] || continue
      local domain_name
      domain_name=$(basename "$domain_dir")

      if [[ -f "$domain_dir/fullchain.pem" && -f "$domain_dir/privkey.pem" ]]; then
        mkdir -p "$backup_root/certificates/$domain_name"
        cp "$domain_dir/fullchain.pem" "$backup_root/certificates/$domain_name/"
        cp "$domain_dir/privkey.pem" "$backup_root/certificates/$domain_name/"
        cert_found=true
        success "  ✓ Backed up certificates for $domain_name"
      fi
    done
  fi
  [[ "$cert_found" == "false" ]] && info "  ℹ No certificates to backup"

  # Backup service file
  if [[ -f "$SB_SVC" ]]; then
    cp "$SB_SVC" "$backup_root/service/sing-box.service"
    success "  ✓ Backed up systemd service"
  fi

  # Record binary version
  if [[ -f "$SB_BIN" ]]; then
    $SB_BIN version > "$backup_root/binary/sing-box-version.txt" 2>&1
    success "  ✓ Recorded binary version"
  fi

  # Create archive
  mkdir -p "$BACKUP_DIR"
  local archive_path="$BACKUP_DIR/$backup_name.tar.gz"

  tar -czf "$archive_path" -C "$temp_dir" "$backup_name" || die "Failed to create archive"

  # Encrypt if requested
  if [[ "$encrypt" == "true" ]]; then
    msg "Encrypting backup..."

    local password="${BACKUP_PASSWORD:-}"
    if [[ -z "$password" ]]; then
      password=$(openssl rand -base64 32)
      echo
      warn "SAVE THIS PASSWORD SECURELY - YOU WILL NEED IT FOR RESTORE:"
      echo -e "${B}${G}$password${N}"
      echo
    fi

    openssl enc -aes-256-cbc -salt -pbkdf2 -in "$archive_path" \
      -out "$archive_path.enc" -k "$password" || die "Encryption failed"

    rm "$archive_path"
    archive_path="$archive_path.enc"
    success "  ✓ Backup encrypted"
  fi

  # Cleanup temp directory
  rm -rf "$temp_dir"

  # Set secure permissions
  chmod 600 "$archive_path"

  success "Backup created: $archive_path"
  info "Size: $(du -h "$archive_path" | cut -f1)"

  # Cleanup old backups
  backup_cleanup

  echo "$archive_path"
}

#==============================================================================
# Backup Restoration
#==============================================================================

# Restore from backup
backup_restore() {
  local backup_file="$1"
  local password="${2:-}"

  [[ -f "$backup_file" ]] || die "Backup file not found: $backup_file"

  msg "Restoring from backup: $backup_file"

  # Confirm action
  if [[ "${FORCE:-0}" != "1" ]]; then
    warn "This will OVERWRITE current configuration!"
    read -rp "Continue? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || die "Restore cancelled"
  fi

  local temp_dir
  temp_dir=$(mktemp -d) || die "Failed to create temp directory"

  # Decrypt if encrypted
  local archive_to_extract="$backup_file"
  if [[ "$backup_file" =~ \.enc$ ]]; then
    msg "Decrypting backup..."
    [[ -n "$password" ]] || read -rsp "Enter backup password: " password
    echo

    openssl enc -aes-256-cbc -d -pbkdf2 -in "$backup_file" \
      -out "$temp_dir/decrypted.tar.gz" -k "$password" || die "Decryption failed"

    archive_to_extract="$temp_dir/decrypted.tar.gz"
    success "  ✓ Backup decrypted"
  fi

  # Extract archive
  tar -xzf "$archive_to_extract" -C "$temp_dir" || die "Failed to extract archive"

  # Find backup root directory
  local backup_root
  backup_root=$(find "$temp_dir" -maxdepth 1 -type d -name "sbx-backup-*" | head -1)
  [[ -d "$backup_root" ]] || die "Invalid backup structure"

  # Stop service before restore
  if systemctl is-active sing-box >/dev/null 2>&1; then
    msg "Stopping sing-box service..."
    systemctl stop sing-box
  fi

  # Restore configuration
  if [[ -f "$backup_root/config/config.json" ]]; then
    mkdir -p "$SB_CONF_DIR"
    cp "$backup_root/config/config.json" "$SB_CONF"
    chmod 600 "$SB_CONF"
    success "  ✓ Restored configuration"
  fi

  if [[ -f "$backup_root/config/client-info.txt" ]]; then
    cp "$backup_root/config/client-info.txt" "$CLIENT_INFO"
    chmod 600 "$CLIENT_INFO"
    success "  ✓ Restored client info"
  fi

  # Restore certificates
  if [[ -d "$backup_root/certificates" ]]; then
    for domain_dir in "$backup_root/certificates"/*; do
      [[ -d "$domain_dir" ]] || continue
      local domain_name
      domain_name=$(basename "$domain_dir")

      mkdir -p "$CERT_DIR_BASE/$domain_name"
      cp "$domain_dir"/*.pem "$CERT_DIR_BASE/$domain_name/"
      chmod 600 "$CERT_DIR_BASE/$domain_name"/*.pem
      success "  ✓ Restored certificates for $domain_name"
    done
  fi

  # Restore service file
  if [[ -f "$backup_root/service/sing-box.service" ]]; then
    cp "$backup_root/service/sing-box.service" "$SB_SVC"
    systemctl daemon-reload
    success "  ✓ Restored systemd service"
  fi

  # Validate restored configuration
  if [[ -f "$SB_BIN" && -f "$SB_CONF" ]]; then
    msg "Validating configuration..."
    $SB_BIN check -c "$SB_CONF" || warn "Configuration validation failed"
  fi

  # Cleanup
  rm -rf "$temp_dir"

  success "Restore completed successfully!"

  # Prompt to start service
  if [[ "${AUTO_START:-1}" == "1" ]]; then
    msg "Starting sing-box service..."
    systemctl start sing-box
    sleep 2
    systemctl is-active sing-box && success "  ✓ Service started" || err "  ✗ Service failed to start"
  else
    info "Start service manually with: systemctl start sing-box"
  fi
}

#==============================================================================
# Backup Management
#==============================================================================

# List available backups
backup_list() {
  [[ -d "$BACKUP_DIR" ]] || { info "No backups found"; return 0; }

  echo -e "${B}Available Backups:${N}\n"

  local count=0
  while IFS= read -r backup_file; do
    local filename
    filename=$(basename "$backup_file")
    local size
    size=$(du -h "$backup_file" | cut -f1)
    local date
    date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || stat -f %Sm "$backup_file" 2>/dev/null)
    local encrypted=""
    [[ "$filename" =~ \.enc$ ]] && encrypted=" ${Y}[encrypted]${N}"

    echo -e "  ${G}●${N} $filename"
    echo -e "    Size: $size | Date: $date$encrypted"
    ((count++))
  done < <(find "$BACKUP_DIR" -name "sbx-backup-*.tar.gz*" -type f 2>/dev/null | sort -r)

  [[ $count -eq 0 ]] && info "No backups found"
  echo
}

# Delete old backups based on retention policy
backup_cleanup() {
  [[ -d "$BACKUP_DIR" ]] || return 0

  msg "Cleaning up old backups (retention: $BACKUP_RETENTION_DAYS days)..."

  local deleted=0
  while IFS= read -r old_backup; do
    rm -f "$old_backup"
    ((deleted++))
  done < <(find "$BACKUP_DIR" -name "sbx-backup-*.tar.gz*" -type f -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null)

  [[ $deleted -gt 0 ]] && success "  ✓ Deleted $deleted old backup(s)" || info "  ℹ No old backups to clean"
}

#==============================================================================
# Export Functions
#==============================================================================

export -f backup_create backup_restore backup_list backup_cleanup
