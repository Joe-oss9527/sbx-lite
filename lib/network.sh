#!/usr/bin/env bash
# lib/network.sh - Network detection and port management
# Part of sbx-lite modular architecture

# Prevent multiple sourcing
[[ -n "${_SBX_NETWORK_LOADED:-}" ]] && return 0
readonly _SBX_NETWORK_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"

#==============================================================================
# IP Detection and Validation
#==============================================================================

# Auto-detect server public IP with multi-service redundancy
get_public_ip() {
  local ip="" service
  local services=(
    "https://ipv4.icanhazip.com"
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://ipinfo.io/ip"
  )

  # Try multiple IP detection services for redundancy
  for service in "${services[@]}"; do
    if have curl; then
      ip=$(timeout 5 curl -s --max-time 5 "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1)
    elif have wget; then
      ip=$(timeout 5 wget -qO- --timeout=5 "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1)
    else
      break
    fi

    # Validate the detected IP more thoroughly
    if [[ -n "$ip" ]] && validate_ip_address "$ip"; then
      echo "$ip"
      return 0
    fi
  done

  return 1
}

# Enhanced IP address validation with reserved address checks
validate_ip_address() {
  local ip="$1"

  # Basic format check
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1

  # Check each octet is in valid range (0-255)
  local IFS='.'
  local -a octets
  read -ra octets <<< "$ip"
  for octet in "${octets[@]}"; do
    # Remove leading zeros and check range
    octet=$((10#$octet))
    [[ $octet -le 255 ]] || return 1
  done

  # Check for reserved/invalid ranges (but allow private IPs for VPS environments)
  [[ ! "$ip" =~ ^0\. ]] || return 1          # 0.x.x.x
  [[ ! "$ip" =~ ^127\. ]] || return 1        # 127.x.x.x (loopback)
  [[ ! "$ip" =~ ^169\.254\. ]] || return 1   # 169.254.x.x (link-local)
  [[ ! "$ip" =~ ^22[4-9]\. ]] || return 1    # 224.x.x.x+ (multicast)
  [[ ! "$ip" =~ ^2[4-5][0-9]\. ]] || return 1 # 240.x.x.x+ (reserved)

  return 0
}

#==============================================================================
# Port Management
#==============================================================================

# Check if port is in use
port_in_use() {
  local p="$1"
  ss -lntp 2>/dev/null | grep -q ":$p " && return 0
  lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p" && return 0
  return 1
}

# Allocate port with retry logic, atomic checks, and fallback
allocate_port() {
  local port="$1"
  local fallback="$2"
  local name="$3"
  local retry_count=0
  local max_retries=3

  # Ensure lock directory exists
  mkdir -p /var/lock 2>/dev/null || true

  # Helper function: atomic port check with file lock
  try_allocate_port() {
    local p="$1"
    local lock_file="/var/lock/sbx-port-${p}.lock"

    # Use flock for atomic check (non-blocking)
    # File descriptor 200 is used for the lock
    (
      # Try to acquire exclusive lock (non-blocking)
      if ! flock -n 200; then
        # Lock held by another process - port is being allocated
        return 1
      fi

      # Lock acquired - now check if port is actually in use
      if port_in_use "$p"; then
        return 1
      fi

      # Port is free according to port_in_use check
      # Double-check with /dev/tcp test to ensure port is truly available
      # This catches race conditions and unusual port states
      timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${p}" 2>/dev/null
      local connect_result=$?

      if [[ $connect_result -eq 0 ]]; then
        # Connection succeeded - something is listening on this port
        return 1
      elif [[ $connect_result -eq 124 ]]; then
        # Timeout occurred - port may be filtered/firewalled
        # Treat as unavailable to be safe
        return 1
      fi

      # Connection refused (expected for free port) or other error
      # Port is available for use
      echo "$p"
      return 0

    ) 200>"$lock_file"

    # Return status from subshell
    return $?
  }

  # First try the preferred port with retries
  while [[ $retry_count -lt $max_retries ]]; do
    if try_allocate_port "$port"; then
      return 0
    fi

    if [[ $retry_count -eq 0 ]]; then
      msg "$name port $port in use, retrying in 2 seconds..." >&2
    fi
    sleep 2
    ((retry_count++))
  done

  # Try fallback port with same atomic check
  if try_allocate_port "$fallback"; then
    warn "$name port $port persistently in use; switching to $fallback" >&2
    return 0
  else
    die "Both $name ports $port and $fallback are in use. Please free up these ports or specify different ones."
  fi
}

# Validate port number
validate_port() {
  local port="$1"
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$port" -le 65535 ] && [ "$port" -ge 1 ]
}

#==============================================================================
# IPv6 Support Detection
#==============================================================================

# Detect IPv6 support with comprehensive checks
detect_ipv6_support() {
  local ipv6_supported=false

  # Check 1: Kernel IPv6 support
  if [[ -f /proc/net/if_inet6 ]]; then
    # Check 2: IPv6 routing table
    if ip -6 route show 2>/dev/null | grep -q "default\|::/0"; then
      # Check 3: Actual connectivity test to a reliable IPv6 DNS server
      if timeout 3 ping6 -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1; then
        ipv6_supported=true
      else
        # Fallback test: check if we can create IPv6 socket
        # Subshell automatically cleans up file descriptors on exit
        if timeout 3 bash -c 'exec 3<>/dev/tcp/[::1]/22' 2>/dev/null; then
          ipv6_supported=true
        elif [[ -n "$(ip -6 addr show scope global 2>/dev/null)" ]]; then
          # Alternative fallback: Check if any global IPv6 address exists
          ipv6_supported=true
        fi
      fi
    fi
  fi

  echo "$ipv6_supported"
}

# Choose optimal listen address based on sing-box 1.12.0 best practices
choose_listen_address() {
  local ipv6_supported="$1"

  # Always use :: for dual-stack support as per sing-box 1.12.0 standards
  # DNS strategy handles IPv4-only resolution when needed
  echo "::"
}

#==============================================================================
# Network Connectivity Tests
#==============================================================================

# Safe HTTP GET with timeout, retry protection, and HTTPS enforcement
safe_http_get() {
  local url="$1"
  local output_file="${2:-}"
  local max_retries=3
  local retry_count=0
  local timeout_seconds=30

  # Security: Enforce HTTPS for security-critical domains
  if [[ "$url" =~ github\.com|githubusercontent\.com|cloudflare\.com ]]; then
    if [[ ! "$url" =~ ^https:// ]]; then
      err "Security: Downloads from ${url%%/*} must use HTTPS"
      return 1
    fi
  fi

  while [[ $retry_count -lt $max_retries ]]; do
    if have curl; then
      # Enhanced curl options for security
      local curl_opts=(
        -fsSL
        --max-time "$timeout_seconds"
      )

      # Add SSL/TLS security options for HTTPS URLs
      if [[ "$url" =~ ^https:// ]]; then
        curl_opts+=(
          --proto '=https'        # Only allow HTTPS protocol
          --tlsv1.2               # Minimum TLS 1.2
          --ssl-reqd              # Require SSL/TLS
        )
      fi

      if [[ -n "$output_file" ]]; then
        if timeout "$timeout_seconds" curl "${curl_opts[@]}" "$url" -o "$output_file" 2>/dev/null; then
          return 0
        fi
      else
        if timeout "$timeout_seconds" curl "${curl_opts[@]}" "$url" 2>/dev/null; then
          return 0
        fi
      fi
    elif have wget; then
      # Enhanced wget options for security
      local wget_opts=(
        -q
        --timeout="$timeout_seconds"
      )

      # Add SSL/TLS security options for HTTPS URLs
      if [[ "$url" =~ ^https:// ]]; then
        wget_opts+=(
          --https-only            # Only use HTTPS
          --secure-protocol=TLSv1_2  # Minimum TLS 1.2
        )
      fi

      if [[ -n "$output_file" ]]; then
        if timeout "$timeout_seconds" wget "${wget_opts[@]}" -O "$output_file" "$url" 2>/dev/null; then
          return 0
        fi
      else
        if timeout "$timeout_seconds" wget "${wget_opts[@]}" -O- "$url" 2>/dev/null; then
          return 0
        fi
      fi
    else
      err "Neither curl nor wget is available"
      return 1
    fi

    ((retry_count++))
    if [[ $retry_count -lt $max_retries ]]; then
      warn "Download failed, retrying ($retry_count/$max_retries)..."
      sleep 2
    fi
  done

  err "Failed to download after $max_retries attempts: $url"
  return 1
}

#==============================================================================
# Export Functions
#==============================================================================

export -f get_public_ip validate_ip_address port_in_use allocate_port validate_port
export -f detect_ipv6_support choose_listen_address safe_http_get
