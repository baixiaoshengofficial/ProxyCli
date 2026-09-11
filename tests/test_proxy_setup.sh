#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

assert_equals() {
  local expected=$1 actual=$2 label=$3
  if [ "$expected" != "$actual" ]; then
    printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

test_runtime() (
  local original_http="http://previous-proxy:3128"
  local original_socks="socks5://previous-proxy:1080"

  curl() { return 0; }
  export http_proxy="$original_http" all_proxy="$original_socks"
  unset HTTP_PROXY https_proxy HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY

  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  set_proxy "127.0.0.1:7890" >/dev/null
  assert_equals "http://127.0.0.1:7890" "$http_proxy" "manual HTTP proxy is enabled"
  assert_equals "socks5://127.0.0.1:7890" "$all_proxy" "manual SOCKS proxy is enabled"
  assert_equals "1" "$PROXYCLI_ENV_SAVED" "original environment is saved"

  stop_proxy >/dev/null
  assert_equals "$original_http" "$http_proxy" "HTTP proxy is restored"
  assert_equals "$original_socks" "$all_proxy" "SOCKS proxy is restored"
  [ -z "${no_proxy+x}" ] || {
    echo "FAIL: no_proxy should be restored to unset" >&2
    exit 1
  }

  start_proxy --skip-detect >/dev/null
  assert_equals "http://127.0.0.1:7890" "$http_proxy" "manual proxy survives restart"

  detect_proxy() {
    PROXY_ADDRESS="http://127.0.0.1:9000"
    SOCKS_ADDRESS="socks5://127.0.0.1:9000"
    _PROXYCLI_AUTO_READY=1
  }
  set_proxy --auto >/dev/null 2>&1
  assert_equals "0" "$PROXYCLI_MANUAL_PROXY" "automatic detection is restored"
  assert_equals "http://127.0.0.1:9000" "$http_proxy" "auto mode refreshes the detected HTTP proxy"
  stop_proxy >/dev/null

  [ -z "${PROXYCLI_SAVED_http_proxy+x}" ] || {
    echo "FAIL: saved proxy values should be cleared after stopping" >&2
    exit 1
  }
)

test_fast_restart() (
  local cached_valid=1 detect_calls=0 status_calls=0

  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY

  detect_proxy() {
    detect_calls=$((detect_calls + 1))
    PROXY_ADDRESS="http://127.0.0.1:7890"
    SOCKS_ADDRESS="socks5://127.0.0.1:7890"
    _PROXYCLI_AUTO_READY=1
  }
  proxy_status() {
    status_calls=$((status_calls + 1))
  }
  _proxycli_cached_proxy_available() {
    [ "$cached_valid" = "1" ]
  }

  start_proxy >/dev/null
  assert_equals "1" "$detect_calls" "first start detects the proxy"
  assert_equals "0" "$status_calls" "start does not run full connectivity checks"

  start_proxy >/dev/null 2>&1
  assert_equals "1" "$detect_calls" "active proxy reuses a valid cached listener"

  stop_proxy >/dev/null
  start_proxy >/dev/null 2>&1
  assert_equals "1" "$detect_calls" "restart reuses the detected proxy"

  stop_proxy >/dev/null
  cached_valid=0
  start_proxy >/dev/null 2>&1
  assert_equals "2" "$detect_calls" "invalid cached proxy triggers a passive scan"

  scan_proxy >/dev/null
  assert_equals "3" "$detect_calls" "pscan always forces proxy detection"
  assert_equals "0" "$status_calls" "start and scan do not run full connectivity checks"
  stop_proxy >/dev/null
)

test_cached_listener_check() (
  local cached_output

  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  PROXY_ADDRESS="http://127.0.0.1:7890"
  SOCKS_ADDRESS=""
  _proxycli_listeners() { printf '%s\n' '0 7890' '1 8080'; }
  cached_output=$(_proxycli_cached_proxy_available 2>&1)
  case "$cached_output" in
    *"Cached check: HTTP on 127.0.0.1:7890."*"all proxy ports are listening."*) ;;
    *)
      echo "FAIL: passive cache check should describe its endpoint and result" >&2
      exit 1
      ;;
  esac

  SOCKS_ADDRESS="socks5://127.0.0.1:1080"
  if _proxycli_cached_proxy_available >/dev/null 2>&1; then
    echo "FAIL: all cached proxy endpoints must still be listening" >&2
    exit 1
  fi

  PROXY_ADDRESS="http://127.0.0.1:9000"
  SOCKS_ADDRESS=""
  if _proxycli_cached_proxy_available >/dev/null 2>&1; then
    echo "FAIL: a missing cached listener should be unavailable" >&2
    exit 1
  fi
)

test_scan_progress() (
  local output

  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  _proxycli_candidate_ports() { printf '%s\n' 7890; }
  _proxycli_probe_http_url() { return 0; }
  _proxycli_probe_socks_url() { return 1; }

  output=$(detect_proxy 2>&1)
  case "$output" in
    *"Scan candidates: 7890."*"Scanning 127.0.0.1:7890 for HTTP, SOCKS5."*"Found HTTP proxy on port 7890."*) ;;
    *)
      echo "FAIL: scan progress should show candidates, port, protocols, and result" >&2
      exit 1
      ;;
  esac
)

test_detection_order() (
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  _PROXYCLI_SCAN_PORTS="9001 7001 invalid 70000 9002"
  unset PROXYCLI_LAST_HTTP_PORT PROXYCLI_LAST_SOCKS_PORT
  _proxycli_listeners() {
    printf '%s\n' '1 6001' '0 7001' '0 7001' '1 8001'
  }

  assert_equals \
    $'7001\n9001\n9002\n6001\n8001' \
    "$(_proxycli_candidate_ports)" \
    "proxy process ports are checked before configured and other ports"

  _proxycli_probe_http_url() {
    [ "$1" = "http://127.0.0.1:7001" ]
  }
  _proxycli_probe_socks_url() {
    [ "$1" = "socks5h://127.0.0.1:9002" ]
  }

  detect_proxy >/dev/null 2>&1
  assert_equals "http://127.0.0.1:7001" "$PROXY_ADDRESS" "HTTP proxy process port is selected"
  assert_equals "socks5://127.0.0.1:9002" "$SOCKS_ADDRESS" "SOCKS protocol is detected independently"
  assert_equals "7001" "$PROXYCLI_LAST_HTTP_PORT" "successful HTTP port is cached"

  assert_equals \
    $'7001\n9002\n9001\n6001\n8001' \
    "$(_proxycli_candidate_ports)" \
    "successful ports are checked first on the next scan"
)

test_scan_port_configuration() (
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  set_scan_ports 9001 1080 9001 >/dev/null
  assert_equals "9001 1080" "$_PROXYCLI_SCAN_PORTS" "scan ports are updated and deduplicated"

  if set_scan_ports 70000 >/dev/null 2>&1; then
    echo "FAIL: out-of-range scan port should be rejected" >&2
    exit 1
  fi
  assert_equals "9001 1080" "$_PROXYCLI_SCAN_PORTS" "invalid input does not change scan ports"

  PROXYCLI_LAST_HTTP_PORT=9001
  _PROXYCLI_AUTO_READY=1
  set_scan_ports --reset >/dev/null
  assert_equals "$_PROXYCLI_DEFAULT_PORTS" "$_PROXYCLI_SCAN_PORTS" "default scan ports are restored"
  [ -z "${PROXYCLI_LAST_HTTP_PORT+x}" ] || {
    echo "FAIL: changing scan ports should clear cached results" >&2
    exit 1
  }
  assert_equals "0" "$_PROXYCLI_AUTO_READY" "changing scan ports invalidates the detected proxy"
)

test_socks_only_detection() (
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  _proxycli_candidate_ports() { printf '%s\n' 1080; }
  _proxycli_probe_http_url() { return 1; }
  _proxycli_probe_socks_url() { return 0; }

  detect_proxy >/dev/null 2>&1
  assert_equals "" "$PROXY_ADDRESS" "SOCKS-only detection leaves HTTP unset"
  assert_equals "socks5://127.0.0.1:1080" "$SOCKS_ADDRESS" "SOCKS-only proxy is accepted"

  curl() { return 0; }
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY
  start_proxy --skip-detect >/dev/null
  [ -z "${http_proxy+x}" ] || {
    echo "FAIL: SOCKS-only mode should not set HTTP proxy variables" >&2
    exit 1
  }
  assert_equals "$SOCKS_ADDRESS" "$all_proxy" "SOCKS-only mode exports all_proxy"
  stop_proxy >/dev/null
)

test_lsof_process_priority() (
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  lsof() {
    printf '%s\n' \
      'p100' 'cnode' 'PTCP' 'n127.0.0.1:8001' \
      'p200' 'cmihomo' 'PTCP' 'n*:7001'
  }
  ss() { return 0; }
  netstat() { return 0; }

  assert_equals \
    $'1 8001 node\n0 7001 mihomo' \
    "$(_proxycli_listeners)" \
    "lsof listeners include proxy-process priority"
)

test_listener_tool_fallback() (
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  lsof() { return 0; }
  ss() {
    printf '%s\n' 'LISTEN 0 4096 0.0.0.0:7897 0.0.0.0:* users:(("verge-mihomo",pid=200,fd=8))'
  }
  netstat() { return 0; }

  assert_equals \
    "0 7897 verge-mihomo" \
    "$(_proxycli_listeners)" \
    "ss is used when lsof returns no listeners"
)

test_status_uses_full_proxy_url() (
  local checked_http_url="" checked_socks_url=""

  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  PROXYCLI_ENV_SAVED=1
  PROXY_ADDRESS="http://proxy.example:3128"
  SOCKS_ADDRESS="socks5://proxy.example:1080"
  http_proxy="$PROXY_ADDRESS"
  all_proxy="$SOCKS_ADDRESS"

  curl() { return 0; }
  _proxycli_probe_http_url() {
    checked_http_url=$1
    return 0
  }
  _proxycli_probe_socks_url() {
    checked_socks_url=$1
    return 0
  }

  proxy_status >/dev/null
  assert_equals "$PROXY_ADDRESS" "$checked_http_url" "status checks the configured HTTP proxy URL"
  assert_equals "$SOCKS_ADDRESS" "$checked_socks_url" "status checks the configured SOCKS proxy URL"
)

test_installer_configuration() {
  local temp_home config_file install_output marker_count

  temp_home=$(mktemp -d)
  config_file="$temp_home/.bashrc"
  printf '%s\n' \
    'keep-before' \
    '# Proxy Manager Configuration' \
    '[ -f "/tmp/legacy" ] && source "/tmp/legacy"' \
    'keep-after' > "$config_file"

  (
    HOME="$temp_home"
    SHELL=/bin/bash
    set -- help
    # shellcheck source=/dev/null
    source "$repo_root/install.sh" >/dev/null
    assert_equals "baixiaoshengofficial/ProxyCli" "$REPO_SLUG" "installer uses the current GitHub repository"

    configure_shell "$config_file"
    configure_shell "$config_file"
    marker_count=$(grep -cF "$MARKER_BEGIN" "$config_file")
    assert_equals "1" "$marker_count" "installer writes one configuration block"

    mkdir -p "${INSTALL_DIR}/src"
    printf '%s\n' 'old runtime' > "$SOURCE_FILE"
    curl() {
      local output_file=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -o)
            output_file=$2
            shift 2
            ;;
          *) shift ;;
        esac
      done
      cp "$repo_root/src/proxy-setup.sh" "$output_file"
    }

    install_output=$(install_proxycli)
    case "$install_output" in
      *"Updated runtime: $SOURCE_FILE"*) ;;
      *)
        echo "FAIL: reinstall should report that the runtime was updated" >&2
        exit 1
        ;;
    esac
    grep -q "alias pscan=" "$SOURCE_FILE" || {
      echo "FAIL: reinstall should overwrite the old runtime" >&2
      exit 1
    }

    remove_config_block "$config_file"
    assert_equals $'keep-before\nkeep-after' "$(cat "$config_file")" "installer removes only its configuration"
  )
  rm -rf "$temp_home"
}

bash -n "$repo_root/install.sh"
bash -n "$repo_root/src/proxy-setup.sh"
SHELL=/bin/bash bash "$repo_root/install.sh" --help >/dev/null
if HOME=/ SHELL=/bin/bash bash "$repo_root/install.sh" --help >/dev/null 2>&1; then
  echo "FAIL: installer should reject HOME=/" >&2
  exit 1
fi
test_runtime
test_fast_restart
test_cached_listener_check
test_scan_progress
test_detection_order
test_scan_port_configuration
test_socks_only_detection
test_lsof_process_priority
test_listener_tool_fallback
test_status_uses_full_proxy_url
test_installer_configuration

echo "ProxyCli shell tests passed."
