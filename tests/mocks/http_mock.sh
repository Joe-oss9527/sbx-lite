#!/usr/bin/env bash
# Mock helpers for HTTP requests and external dependencies

# Mock GitHub API responses
mock_github_api() {
    local endpoint="$1"
    local response_file="$2"
    
    # Simulate GitHub API response
    case "$endpoint" in
        */releases/latest)
            cat << 'GITHUB_LATEST'
{
  "tag_name": "v1.10.7",
  "name": "1.10.7",
  "prerelease": false,
  "created_at": "2024-10-15T10:00:00Z",
  "published_at": "2024-10-15T10:30:00Z",
  "assets": [
    {
      "name": "sing-box-1.10.7-linux-amd64.tar.gz",
      "browser_download_url": "https://github.com/SagerNet/sing-box/releases/download/v1.10.7/sing-box-1.10.7-linux-amd64.tar.gz"
    }
  ]
}
GITHUB_LATEST
            ;;
        */releases)
            cat << 'GITHUB_ALL'
[
  {
    "tag_name": "v1.11.0-beta.1",
    "prerelease": true,
    "created_at": "2024-11-01T10:00:00Z"
  },
  {
    "tag_name": "v1.10.7",
    "prerelease": false,
    "created_at": "2024-10-15T10:00:00Z"
  }
]
GITHUB_ALL
            ;;
        *)
            echo "{}" 
            ;;
    esac
}

# Mock checksum file
mock_checksum_file() {
    local version="$1"
    local arch="$2"
    
    # Generate a fake but valid SHA256 checksum
    echo "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd  sing-box-${version#v}-${arch}.tar.gz"
}

# Mock curl command
mock_curl() {
    local args=("$@")
    local url=""
    local output=""
    
    # Parse curl arguments
    for ((i=0; i<${#args[@]}; i++)); do
        case "${args[i]}" in
            -o)
                output="${args[i+1]}"
                ((i++))
                ;;
            -*)
                # Skip other flags
                ;;
            *)
                url="${args[i]}"
                ;;
        esac
    done
    
    # Simulate responses based on URL
    local response=""
    
    if [[ "$url" == *"/releases/latest" ]]; then
        response=$(mock_github_api "/releases/latest")
    elif [[ "$url" == *"/releases" ]]; then
        response=$(mock_github_api "/releases")
    elif [[ "$url" == *".sha256sum" ]]; then
        response=$(mock_checksum_file "v1.10.7" "linux-amd64")
    else
        response="Mock response for $url"
    fi
    
    # Output to file or stdout
    if [[ -n "$output" ]]; then
        echo "$response" > "$output"
    else
        echo "$response"
    fi
    
    return 0
}

# Mock sha256sum command
mock_sha256sum() {
    local file="$1"
    
    # Return a fake but consistent checksum
    echo "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd  $file"
}

# Mock shasum command
mock_shasum() {
    local algo=""
    local file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a)
                algo="$2"
                shift 2
                ;;
            *)
                file="$1"
                shift
                ;;
        esac
    done
    
    # Return fake checksum
    if [[ "$algo" == "256" ]]; then
        echo "a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd  $file"
    else
        return 1
    fi
}

# Export mock functions
export -f mock_github_api
export -f mock_checksum_file
export -f mock_curl
export -f mock_sha256sum
export -f mock_shasum
