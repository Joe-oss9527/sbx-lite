#!/usr/bin/env bash
# lib/ui.sh - User interface and interaction
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_UI_LOADED:-}" ]] && return 0
readonly _SBX_UI_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Logo and Banner
#==============================================================================

# Display application logo
show_logo() {
  clear
  echo
  echo -e "${BLUE}███████╗${CYAN}██████╗ ${PURPLE}██╗  ██╗    ${G}██╗     ${Y}██╗${R}████████╗${G}███████╗${N}"
  echo -e "${BLUE}██╔════╝${CYAN}██╔══██╗${PURPLE}╚██╗██╔╝    ${G}██║     ${Y}██║${R}╚══██╔══╝${G}██╔════╝${N}"
  echo -e "${BLUE}███████╗${CYAN}██████╔╝${PURPLE} ╚███╔╝ ${N}███╗${G}██║     ${Y}██║${R}   ██║   ${G}█████╗  ${N}"
  echo -e "${BLUE}╚════██║${CYAN}██╔══██╗${PURPLE} ██╔██╗ ${N}╚══╝${G}██║     ${Y}██║${R}   ██║   ${G}██╔══╝  ${N}"
  echo -e "${BLUE}███████║${CYAN}██████╔╝${PURPLE}██╔╝ ██╗    ${G}███████╗${Y}██║${R}   ██║   ${G}███████╗${N}"
  echo -e "${BLUE}╚══════╝${CYAN}╚═════╝ ${PURPLE}╚═╝  ╚═╝    ${G}╚══════╝${Y}╚═╝${R}   ╚═╝   ${G}╚══════╝${N}"
  echo
  echo -e "    ${B}${CYAN}🚀 Sing-Box Official One-Click Deployment Script${N}"
  echo -e "    ${Y}📦 Multi-Protocol: REALITY + WS-TLS + Hysteria2${N}"
  echo -e "    ${G}⚡ Version: Latest | Author: YYvanYang${N}"
  echo -e "${G}================================================================${N}"
  echo
}

# Display sbx manager logo (simplified version)
show_sbx_logo() {
  echo
  echo -e "${B}${CYAN}█▀▀ █▄▄ ▀▄▀   █▀▄▀█ ▄▀█ █▄ █ ▄▀█ █▀▀ █▀▀ █▀█${N}"
  echo -e "${B}${BLUE}▄██ █▄█  █    █ ▀ █ █▀█ █ ▀█ █▀█ █▄█ ██▄ █▀▄${N}"
  echo -e "${G}================================================${N}"
  echo
}

#==============================================================================
# Installation Menu
#==============================================================================

# Show existing installation menu and get user choice
show_existing_installation_menu() {
  local current_version="${1:-unknown}"
  local service_status="${2:-unknown}"
  local latest_version="${3:-unknown}"
  local version_status="${4:-unknown}"

  echo
  warn "Existing sing-box installation detected:"
  info "Binary: $SB_BIN (version: $current_version)"
  [[ -f "$SB_CONF" ]] && info "Config: $SB_CONF"
  [[ -f "$SB_SVC" ]] && info "Service: $SB_SVC (status: $service_status)"

  # Show version status if available
  if [[ "$current_version" != "not_installed" && "$current_version" != "unknown" ]]; then
    case "$version_status" in
      "current")
        success "You have the latest version ($current_version)"
        ;;
      "outdated")
        warn "Update available: $current_version → $latest_version"
        ;;
      "unsupported")
        err "Your version ($current_version) is too old and may not be compatible"
        warn "Strongly recommend upgrading to the latest version ($latest_version)"
        ;;
      "newer")
        info "You have a newer version than latest release ($current_version > $latest_version)"
        ;;
    esac
  fi

  echo
  echo -e "${CYAN}Available options:${N}"
  echo -e "1) ${G}Fresh install${N} (backup existing config, clean install)"
  echo -e "2) ${Y}Upgrade binary only${N} (keep existing config)"
  echo -e "3) ${Y}Reconfigure${N} (keep binary, regenerate config)"
  echo -e "4) ${R}Complete uninstall${N} (remove everything)"
  echo -e "5) ${BLUE}Show current config${N} (view and exit)"
  echo "6) Exit"
  echo
}

# Prompt user for menu choice
prompt_menu_choice() {
  local min="${1:-1}"
  local max="${2:-6}"
  local choice

  read -rp "Enter your choice [1-$max]: " choice

  # Validate choice
  if ! validate_menu_choice "$choice" "$min" "$max"; then
    err "Invalid choice. Please enter a number between $min and $max."
    return 1
  fi

  echo "$choice"
  return 0
}

#==============================================================================
# Confirmation Prompts
#==============================================================================

# Prompt for yes/no confirmation
prompt_yes_no() {
  local prompt="${1:-Continue?}"
  local default="${2:-N}"
  local response

  if [[ "$default" =~ ^[Yy]$ ]]; then
    read -rp "$prompt [Y/n]: " response
    response="${response:-Y}"
  else
    read -rp "$prompt [y/N]: " response
    response="${response:-N}"
  fi

  if validate_yes_no "$response"; then
    [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
  else
    err "Invalid input. Please enter Y or N."
    return 1
  fi
}

# Prompt for text input with validation
prompt_input() {
  local prompt="$1"
  local default="${2:-}"
  local validator="${3:-}"  # Optional validation function
  local input

  if [[ -n "$default" ]]; then
    read -rp "$prompt [$default]: " input
    input="${input:-$default}"
  else
    read -rp "$prompt: " input
  fi

  # Sanitize input
  input=$(sanitize_input "$input")

  # Validate if validator function provided
  if [[ -n "$validator" ]] && command -v "$validator" >/dev/null 2>&1; then
    if ! "$validator" "$input"; then
      err "Invalid input"
      return 1
    fi
  fi

  echo "$input"
  return 0
}

# Secure password prompt
prompt_password() {
  local prompt="${1:-Enter password}"
  local password

  read -rsp "$prompt: " password
  echo >&2  # New line after password input

  echo "$password"
  return 0
}

#==============================================================================
# Progress Indicators
#==============================================================================

# Show spinner during long operations
show_spinner() {
  local pid=$1
  local message="${2:-Processing}"
  local spinstr='|/-\'
  local i=0

  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r%s ${spinstr:$i:1}" "$message"
    sleep 0.1
  done

  printf "\r%s Done    \n" "$message"
}

# Show progress bar
show_progress() {
  local current=$1
  local total=$2
  local width=50
  local percent=$((current * 100 / total))
  local completed=$((current * width / total))
  local remaining=$((width - completed))

  printf "\r["
  printf "%${completed}s" | tr ' ' '='
  printf "%${remaining}s" | tr ' ' ' '
  printf "] %3d%%" "$percent"

  if [[ $current -eq $total ]]; then
    echo
  fi
}

#==============================================================================
# Information Display
#==============================================================================

# Display configuration summary
show_config_summary() {
  local domain="${1:-N/A}"
  local reality_port="${2:-443}"
  local ws_port="${3:-}"
  local hy2_port="${4:-}"
  local has_certs="${5:-false}"

  echo
  echo -e "${B}=== Configuration Summary ===${N}"
  echo "Domain/IP     : $domain"
  echo "Reality Port  : $reality_port"

  if [[ "$has_certs" == "true" && -n "$ws_port" && -n "$hy2_port" ]]; then
    echo "WS-TLS Port   : $ws_port"
    echo "Hysteria2 Port: $hy2_port"
    echo "Certificates  : Configured"
  else
    echo "Mode          : Reality-only (no certificates)"
  fi
  echo
}

# Display installation summary
show_installation_summary() {
  local domain="${1:-N/A}"
  local protocols="${2:-Reality}"
  local qr_available="${3:-false}"

  echo
  echo -e "${B}${G}=== Installation Complete ===${N}"
  echo
  echo -e "${G}✓${N} sing-box installed and running"
  echo -e "${G}✓${N} Configuration: $SB_CONF"
  echo -e "${G}✓${N} Service: systemctl status sing-box"
  echo
  echo -e "${CYAN}Enabled Protocols:${N} $protocols"
  echo -e "${CYAN}Server:${N} $domain"
  echo
  echo -e "${Y}Management Commands:${N}"
  echo "  sbx info      - Show configuration and URIs"
  echo "  sbx status    - Check service status"
  echo "  sbx restart   - Restart service"
  echo "  sbx log       - View live logs"

  if [[ "$qr_available" == "true" ]]; then
    echo "  sbx qr        - Display QR codes"
  fi

  echo
  echo -e "${G}For detailed info, run: ${B}sbx info${N}"
  echo
}

#==============================================================================
# Error Display
#==============================================================================

# Display error with context
show_error() {
  local error_msg="$1"
  local context="${2:-}"
  local suggestion="${3:-}"

  echo
  err "Error: $error_msg"

  if [[ -n "$context" ]]; then
    info "Context: $context"
  fi

  if [[ -n "$suggestion" ]]; then
    echo -e "${Y}Suggestion:${N} $suggestion"
  fi

  echo
}

#==============================================================================
# Export Functions
#==============================================================================

export -f show_logo show_sbx_logo show_existing_installation_menu
export -f prompt_menu_choice prompt_yes_no prompt_input prompt_password
export -f show_spinner show_progress show_config_summary
export -f show_installation_summary show_error
