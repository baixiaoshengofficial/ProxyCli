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

  set_proxy --address "127.0.0.1:7890" >/dev/null
  if set_proxy 127.0.0.1:7890 >/dev/null 2>&1 || set_proxy --auto >/dev/null 2>&1; then
    echo "FAIL: old pset syntax should be rejected" >&2
    exit 1
  fi
  assert_equals "$original_http" "$http_proxy" "setting an address does not start the shell proxy"
  start_proxy >/dev/null
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

  start_proxy >/dev/null
  assert_equals "http://127.0.0.1:7890" "$http_proxy" "manual proxy survives restart"

  detect_proxy() {
    PROXY_ADDRESS="http://127.0.0.1:9000"
    SOCKS_ADDRESS="socks5://127.0.0.1:9000"
    _PROXYCLI_AUTO_READY=1
  }
  set_proxy --address auto >/dev/null 2>&1
  assert_equals "0" "$PROXYCLI_MANUAL_PROXY" "automatic detection is restored"
  assert_equals "http://127.0.0.1:7890" "$http_proxy" "auto setting preserves the active shell proxy"
  assert_equals "1" "$_PROXYCLI_SETTINGS_PENDING" "auto address change waits for application"
  start_proxy >/dev/null
  assert_equals "http://127.0.0.1:9000" "$http_proxy" "auto mode refreshes the detected HTTP proxy"
  assert_equals "0" "$_PROXYCLI_SETTINGS_PENDING" "start applies pending settings"
  stop_proxy >/dev/null

  set_proxy --address auto >/dev/null
  assert_equals "0" "$PROXYCLI_MANUAL_PROXY" "inactive auto setting keeps automatic mode"
  assert_equals "$original_http" "$http_proxy" "inactive auto setting leaves the shell proxy unchanged"

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

  _PROXYCLI_SCAN_PORTS="9001 7001 invalid 70000 0 07001 9002"
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
  assert_equals "socks5h://127.0.0.1:9002" "$SOCKS_ADDRESS" "SOCKS protocol is detected independently"
  assert_equals "7001" "$PROXYCLI_LAST_HTTP_PORT" "successful HTTP port is cached"

  assert_equals \
    $'7001\n9002\n9001\n6001\n8001' \
    "$(_proxycli_candidate_ports)" \
    "successful ports are checked first on the next scan"
)

test_scan_port_configuration() (
  alias pports='set_scan_ports'
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  if alias pports >/dev/null 2>&1; then
    echo "FAIL: the old pports alias should be removed" >&2
    exit 1
  fi

  set_proxy --ports 9001 1080 9001 >/dev/null
  assert_equals "9001 1080" "$_PROXYCLI_SCAN_PORTS" "scan ports are updated and deduplicated"

  if set_scan_ports 70000 >/dev/null 2>&1; then
    echo "FAIL: out-of-range scan port should be rejected" >&2
    exit 1
  fi
  assert_equals "9001 1080" "$_PROXYCLI_SCAN_PORTS" "invalid input does not change scan ports"

  if set_proxy --ports --reset >/dev/null 2>&1 ||
     set_proxy --ports auto 7890 >/dev/null 2>&1 ||
     set_proxy --ports 7890 auto >/dev/null 2>&1; then
    echo "FAIL: old reset syntax and mixed auto/port arguments should be rejected" >&2
    exit 1
  fi
  assert_equals "9001 1080" "$_PROXYCLI_SCAN_PORTS" "rejected auto arguments do not change scan ports"

  PROXYCLI_LAST_HTTP_PORT=9001
  PROXYCLI_LAST_SOCKS_PORT=1080
  _PROXYCLI_AUTO_READY=1
  set_proxy --ports auto >/dev/null
  assert_equals "$_PROXYCLI_DEFAULT_PORTS" "$_PROXYCLI_SCAN_PORTS" "default scan ports are restored"
  [ -z "${PROXYCLI_LAST_HTTP_PORT+x}" ] || {
    echo "FAIL: changing scan ports should clear cached results" >&2
    exit 1
  }
  assert_equals "0" "$_PROXYCLI_AUTO_READY" "changing scan ports invalidates the detected proxy"
  [ -z "${PROXYCLI_LAST_SOCKS_PORT+x}" ] || {
    echo "FAIL: restoring scan ports should clear cached SOCKS results" >&2
    exit 1
  }
  set_proxy --ports auto >/dev/null
  assert_equals "$_PROXYCLI_DEFAULT_PORTS" "$_PROXYCLI_SCAN_PORTS" "repeated auto restores are harmless"
)

test_socks_only_detection() (
  local tested_socks_url=""
  # shellcheck source=/dev/null
  source "$repo_root/src/proxy-setup.sh" >/dev/null

  _proxycli_candidate_ports() { printf '%s\n' 1080; }
  _proxycli_probe_http_url() { return 1; }
  _proxycli_probe_socks_url() { tested_socks_url=$1; return 0; }

  detect_proxy >/dev/null 2>&1
  assert_equals "" "$PROXY_ADDRESS" "SOCKS-only detection leaves HTTP unset"
  assert_equals "socks5h://127.0.0.1:1080" "$SOCKS_ADDRESS" "SOCKS-only proxy is accepted"
  assert_equals "$tested_socks_url" "$SOCKS_ADDRESS" "detection keeps the verified SOCKS URL"

  curl() { return 0; }
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY
  PROXYCLI_MANUAL_PROXY=1
  start_proxy >/dev/null
  [ -z "${http_proxy+x}" ] || {
    echo "FAIL: SOCKS-only mode should not set HTTP proxy variables" >&2
    exit 1
  }
  assert_equals "$SOCKS_ADDRESS" "$all_proxy" "SOCKS-only mode exports all_proxy"
  assert_equals "$tested_socks_url" "$all_proxy" "start exports the verified SOCKS URL"
  proxy_status >/dev/null
  assert_equals "$all_proxy" "$tested_socks_url" "status checks the same SOCKS URL as detection and activation"
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
  http_proxy="http://actual.example:8080"
  all_proxy="socks5h://actual.example:1081"

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
  assert_equals "$http_proxy" "$checked_http_url" "status checks the actual HTTP proxy URL"
  assert_equals "$all_proxy" "$checked_socks_url" "status checks the actual SOCKS proxy URL"
  unset PROXYCLI_ENV_SAVED
  proxy_status >/dev/null
  assert_equals "$http_proxy" "$checked_http_url" "status also checks externally configured proxy variables"
)

test_http_only_and_failed_scan() (
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  curl() { return 0; }
  _proxycli_candidate_ports() { printf '%s\n' 7890; }
  _proxycli_probe_http_url() { return 0; }
  _proxycli_probe_socks_url() { return 1; }
  scan_proxy >/dev/null 2>&1
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "HTTP-only activation succeeds"
  [ -z "${all_proxy+x}" ] || { echo 'FAIL: HTTP-only activation must unset SOCKS variables' >&2; exit 1; }
  _proxycli_probe_http_url() { return 1; }
  if scan_proxy >/dev/null 2>&1; then
    echo 'FAIL: unavailable ports must fail detection' >&2
    exit 1
  fi
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "failed scan preserves the active environment"
  assert_equals 'http://127.0.0.1:7890' "$PROXY_ADDRESS" "failed scan preserves the selected address"
  assert_equals '1' "$_PROXYCLI_AUTO_READY" "failed scan preserves the previous detection state"
  stop_proxy >/dev/null
  _proxycli_probe_socks_url() { return 0; }
  detect_proxy >/dev/null 2>&1
  [ -z "${PROXYCLI_LAST_HTTP_PORT+x}" ] || { echo 'FAIL: SOCKS-only scan must clear the old HTTP port' >&2; exit 1; }
)

test_existing_environment_restart() (
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  export HTTPS_PROXY='http://external.example:3128'
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  _PROXYCLI_AUTO_READY=0
  PROXYCLI_MANUAL_PROXY=0
  detect_proxy() { echo 'FAIL: an existing environment should not trigger a scan' >&2; exit 1; }
  start_proxy >/dev/null 2>&1
  start_proxy >/dev/null 2>&1
  assert_equals 'http://external.example:3128' "$http_proxy" "repeated start reuses an existing HTTP proxy"
  stop_proxy >/dev/null
  assert_equals 'http://external.example:3128' "$HTTPS_PROXY" "stop restores the external proxy"
  [ -z "${http_proxy+x}" ] || { echo 'FAIL: stop should restore originally unset lowercase variables' >&2; exit 1; }
)

test_validation_and_reload() (
  local invalid settings_before command_name output
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  set_proxy --address localhost:7890 >/dev/null
  set_proxy --ports 07890 7890 01080 >/dev/null
  assert_equals '7890 1080' "$_PROXYCLI_SCAN_PORTS" "leading zero ports are normalized and deduplicated"
  settings_before=$(set_proxy)
  for invalid in '' --bad host host:0 host:65536 host:abc host:7890/path \
    'http://host:7890?x=1' 'socks5://host:7890' 'ftp://host:7890' '::1:7890' 'http://:7890' 'http://host name:7890'; do
    if set_proxy --address "$invalid" >/dev/null 2>&1; then
      printf 'FAIL: invalid address accepted: %s\n' "$invalid" >&2
      exit 1
    fi
    assert_equals "$settings_before" "$(set_proxy)" "invalid address leaves settings unchanged"
  done
  if set_proxy --address localhost:7890 '' >/dev/null 2>&1 ||
     set_proxy --address localhost:7890 --bad >/dev/null 2>&1 ||
     set_proxy --ports '' >/dev/null 2>&1; then
    echo 'FAIL: empty or invalid additional arguments should be rejected' >&2
    exit 1
  fi
  for command_name in start_proxy scan_proxy stop_proxy toggle_proxy proxy_status show_help; do
    if "$command_name" --bad >/dev/null 2>&1; then
      printf 'FAIL: %s should reject unexpected arguments\n' "$command_name" >&2
      exit 1
    fi
  done
  assert_equals "$settings_before" "$(set_proxy)" "rejected arguments leave settings unchanged"
  set_proxy --address 'https://user:secret@proxy.example:03128' 'socks5h://[::1]:01080' >/dev/null
  assert_equals 'https://user:secret@proxy.example:3128' "$PROXY_ADDRESS" "HTTP scheme and credentials are preserved"
  assert_equals 'socks5h://[::1]:1080' "$SOCKS_ADDRESS" "IPv6 and SOCKS DNS mode are preserved"
  assert_equals 'http://***@proxy.example:3128' "$(_proxycli_redact_url 'http://user:secret@part@proxy.example:3128')" "redaction hides all user information"
  start_proxy >/dev/null
  settings_before=$(set_proxy)
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  assert_equals "$settings_before" "$(set_proxy)" "reload preserves address and scan-port settings"
  assert_equals '1' "$PROXYCLI_ENV_SAVED" "reload preserves the saved environment"
  stop_proxy >/dev/null
  [ -z "${http_proxy+x}" ] || { echo 'FAIL: stop after reload must restore the original environment' >&2; exit 1; }
  _PROXYCLI_AUTO_READY=1
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  assert_equals '1' "$_PROXYCLI_AUTO_READY" "reload preserves detection readiness"
  output=$(bash --noprofile --norc -c 'source "$1/src/proxy-setup.sh"' _ "$repo_root")
  assert_equals '' "$output" "noninteractive loading does not print a banner"
)

test_settings_queries_and_application() (
  local settings_before address_before ports_before detected_calls=0 status_output no_proxy_before
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  curl() { return 0; }
  detect_proxy() {
    detected_calls=$((detected_calls + 1))
    PROXY_ADDRESS="http://127.0.0.1:${_PROXYCLI_SCAN_PORTS%% *}"
    SOCKS_ADDRESS="socks5h://127.0.0.1:${_PROXYCLI_SCAN_PORTS%% *}"
    _PROXYCLI_AUTO_READY=1
  }
  _proxycli_cached_proxy_available() { return 0; }

  set_proxy --address auto >/dev/null
  assert_equals '0' "$detected_calls" "selecting auto does not detect or activate"
  assert_equals '  Address: automatic detection' "$(set_proxy --address)" "address without a value shows auto setting"
  assert_equals '1' "$_PROXYCLI_SETTINGS_PENDING" "querying an address preserves pending settings"
  set_proxy --address 'http://user:secret@localhost:7890' 'socks5h://localhost:1080' >/dev/null
  address_before=$(set_proxy --address)
  assert_equals $'  HTTP:  http://***@localhost:7890\n  SOCKS: socks5h://localhost:1080' "$address_before" "address query hides credentials and shows both settings"
  [ -z "${http_proxy+x}" ] && [ -z "${PROXYCLI_ENV_SAVED+x}" ] || {
    echo 'FAIL: setting or querying must not enable the shell proxy' >&2
    exit 1
  }
  start_proxy >/dev/null
  no_proxy_before=$no_proxy
  set_proxy --address localhost:9000 >/dev/null
  assert_equals 'http://user:secret@localhost:7890' "$http_proxy" "manual address changes leave an active environment untouched"
  assert_equals '' "$PROXYCLI_SAVED_http_proxy" "setting an address preserves the original backup"
  assert_equals '0' "$detected_calls" "manual settings do not trigger detection"
  start_proxy >/dev/null
  assert_equals 'http://localhost:9000' "$http_proxy" "start applies the new manual address"
  assert_equals "$no_proxy_before" "$no_proxy" "applying new settings does not duplicate no_proxy entries"
  stop_proxy >/dev/null
  [ -z "${http_proxy+x}" ] || { echo 'FAIL: stopping restores the original unset environment' >&2; exit 1; }

  export HTTPS_PROXY='http://external.example:3128'
  set_proxy --address auto >/dev/null
  start_proxy >/dev/null 2>&1
  assert_equals '1' "$detected_calls" "an explicit auto setting scans instead of reusing external variables"
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "auto settings select a detected proxy"
  set_proxy --ports 9001 1080 >/dev/null
  assert_equals '1' "$detected_calls" "changing scan ports does not trigger detection"
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "changing scan ports preserves the active environment"
  settings_before=$(set_proxy)
  address_before=$(set_proxy --address)
  ports_before=$(set_proxy --ports)
  assert_equals "$settings_before" "$(set_proxy)" "settings queries do not change configuration"
  assert_equals '  Address: automatic detection' "$address_before" "address query shows the chosen mode"
  assert_equals '[ProxyCli] Scan ports: 9001 1080' "$ports_before" "ports query shows the configured candidates"
  assert_equals '1' "$_PROXYCLI_SETTINGS_PENDING" "queries keep pending settings intact"
  status_output=$(proxy_status)
  case "$status_output" in
    *'http://127.0.0.1:7890'*'Settings pending; run pstart to apply.'*) ;;
    *) echo 'FAIL: status should show the active proxy and the pending settings hint' >&2; exit 1 ;;
  esac
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  assert_equals '1' "$_PROXYCLI_SETTINGS_PENDING" "reload preserves pending settings"
  # Reload replaced the mocks, so restore them before applying settings.
  detect_proxy() {
    detected_calls=$((detected_calls + 1))
    PROXY_ADDRESS="http://127.0.0.1:${_PROXYCLI_SCAN_PORTS%% *}"
    SOCKS_ADDRESS="socks5h://127.0.0.1:${_PROXYCLI_SCAN_PORTS%% *}"
    _PROXYCLI_AUTO_READY=1
  }
  start_proxy >/dev/null
  assert_equals '2' "$detected_calls" "start scans with changed ports instead of reusing the active environment"
  assert_equals 'http://127.0.0.1:9001' "$http_proxy" "start applies the new scan result"
  assert_equals '0' "$_PROXYCLI_SETTINGS_PENDING" "applying scan ports clears pending state"
  assert_equals 'http://external.example:3128' "$PROXYCLI_SAVED_HTTPS_PROXY" "reconfiguration keeps the original external proxy backup"

  set_proxy --ports auto >/dev/null
  assert_equals 'http://127.0.0.1:9001' "$http_proxy" "restoring default ports also waits for application"
  start_proxy >/dev/null
  assert_equals '3' "$detected_calls" "start rescans after restoring default ports"
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "default ports apply on start"

  set_proxy --address auto >/dev/null
  assert_equals '3' "$detected_calls" "selecting auto while active does not scan"
  detect_proxy() { return 1; }
  if start_proxy >/dev/null 2>&1; then
    echo 'FAIL: failed application should return failure' >&2
    exit 1
  fi
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "failed application preserves the active environment"
  assert_equals '1' "$_PROXYCLI_SETTINGS_PENDING" "failed application keeps settings pending"
  assert_equals '1' "$PROXYCLI_ENV_SAVED" "failed application keeps the original backup"
  set_proxy --address localhost:9009 >/dev/null
  start_proxy >/dev/null
  assert_equals 'http://localhost:9009' "$http_proxy" "manual settings can recover from failed auto detection"

  detect_proxy() {
    detected_calls=$((detected_calls + 1))
    PROXY_ADDRESS='http://127.0.0.1:7890'
    SOCKS_ADDRESS='socks5h://127.0.0.1:7890'
    _PROXYCLI_AUTO_READY=1
  }
  set_proxy --address localhost:9010 >/dev/null
  scan_proxy >/dev/null 2>&1
  assert_equals '0' "$PROXYCLI_MANUAL_PROXY" "scan explicitly switches the configured address to auto"
  assert_equals '0' "$_PROXYCLI_SETTINGS_PENDING" "scan applies its result and clears pending settings"
  assert_equals 'http://127.0.0.1:7890' "$http_proxy" "scan applies the detected proxy"
  stop_proxy >/dev/null
  assert_equals 'http://external.example:3128' "$HTTPS_PROXY" "stop restores the external environment after all setting changes"
  [ -z "${http_proxy+x}" ] || { echo 'FAIL: stop should restore originally unset HTTP variables' >&2; exit 1; }
)

test_shell_scope_and_help() (
  local settings_before help_output child_output status_output

  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  curl() { return 0; }
  set_proxy --address 127.0.0.1:7890 >/dev/null
  settings_before=$(set_proxy)
  if set_proxy --system on >/dev/null 2>&1 || set_proxy --system off >/dev/null 2>&1; then
    echo "FAIL: removed system setting should be rejected" >&2
    exit 1
  fi
  assert_equals "$settings_before" "$(set_proxy)" "rejected settings preserve the configured address"
  help_output=$(show_help)
  case "$help_output" in
    *--system*) echo "FAIL: help should omit the removed system setting" >&2; exit 1 ;;
  esac
  case "$help_output" in
    *"pset --address auto"*"pset --ports auto"*) ;;
    *) echo "FAIL: help should use auto for both address and scan ports" >&2; exit 1 ;;
  esac
  case "$help_output" in
    *--reset*) echo "FAIL: help should omit the old reset syntax" >&2; exit 1 ;;
  esac

  status_output=$(proxy_status)
  case "$status_output" in
    *"INACTIVE (current shell)"*) ;;
    *) echo "FAIL: status should report an inactive shell" >&2; exit 1 ;;
  esac
  start_proxy >/dev/null
  assert_equals "http://127.0.0.1:7890" "$(printenv http_proxy)" "CLI children inherit the current shell proxy"
  assert_equals "socks5://127.0.0.1:7890" "$(printenv all_proxy)" "CLI children inherit the SOCKS proxy"
  status_output=$(proxy_status)
  case "$status_output" in
    *"ACTIVE (current shell)"*) ;;
    *) echo "FAIL: status should report an active shell" >&2; exit 1 ;;
  esac
  child_output=$(env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
    bash --noprofile --norc -c 'source "$1/src/proxy-setup.sh" >/dev/null; printf "%s|%s" "${http_proxy-unset}" "${PROXYCLI_ENV_SAVED:-0}"' _ "$repo_root")
  assert_equals 'unset|0' "$child_output" "independent shells do not automatically enable a proxy"
  toggle_proxy >/dev/null
  [ -z "${http_proxy+x}" ] || { echo "FAIL: toggle should restore an unset shell proxy" >&2; exit 1; }
  toggle_proxy >/dev/null
  assert_equals "http://127.0.0.1:7890" "$http_proxy" "toggle restarts the configured proxy"
  stop_proxy >/dev/null
)

test_installer_configuration() {
  local temp_home config_file login_config install_output marker_count login_output

  temp_home=$(mktemp -d)
  config_file="$temp_home/.bashrc"
  login_config="$temp_home/.profile"
  printf '%s\n' ': keep-login' > "$login_config"
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
    assert_equals "$login_config" "$(find_bash_login_config)" "Bash SSH login uses the existing profile"

    configure_shell "$config_file"
    cp "$config_file" "$temp_home/first-config"
    configure_shell "$config_file"
    cmp -s "$temp_home/first-config" "$config_file" || {
      echo 'FAIL: repeated configuration must leave the file identical' >&2
      exit 1
    }
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
    assert_equals "1" "$(grep -cF "$MARKER_BEGIN" "$login_config")" "installer configures the Bash login profile"
    assert_equals "1" "$(grep -cF "$MARKER_BEGIN" "$config_file")" "reinstall keeps one Bash rc block"
    cmp -s "$temp_home/first-config" "$config_file" || {
      echo 'FAIL: reinstall must preserve the existing configuration exactly' >&2
      exit 1
    }

    login_output=$(env -i HOME="$temp_home" SHELL=/bin/bash PATH="$PATH" \
      bash --login -c 'alias pstart >/dev/null && printf "PROXYCLI_LOGIN_LOADED|%s" "${PROXYCLI_ENV_SAVED:-0}"')
    case "$login_output" in
      *"PROXYCLI_LOGIN_LOADED|0"*) ;;
      *) echo "FAIL: SSH-style Bash login should load commands without enabling a proxy" >&2; exit 1 ;;
    esac

    _PROXYCLI_RUNTIME_LOADED=1
    source "$login_config"
    assert_equals "1" "$_PROXYCLI_RUNTIME_LOADED" "login profile respects the runtime guard"

    remove_config_block "$config_file"
    assert_equals $'keep-before\nkeep-after' "$(cat "$config_file")" "installer removes only its configuration"
    uninstall_proxycli >/dev/null
    assert_equals ': keep-login' "$(cat "$login_config")" "uninstall removes the login profile block"
  )
  rm -rf "$temp_home"
}

test_installer_literal_paths() (
  local temp_root temp_home config_file output runtime_help
  temp_root=$(mktemp -d)
  trap 'rm -rf "$temp_root"' EXIT
  temp_home="$temp_root/home 'quoted' \$literal \`literal\`"
  mkdir -p "$temp_home"
  HOME="$temp_home"
  SHELL=/bin/bash
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  runtime_help=$(show_help)
  set -- help
  source "$repo_root/install.sh" >/dev/null
  assert_equals "$runtime_help" "$(show_help)" "installer help does not overwrite runtime help"
  mkdir -p "${INSTALL_DIR}/src"
  cp "$repo_root/src/proxy-setup.sh" "$SOURCE_FILE"
  config_file="$temp_home/.bashrc"
  configure_shell "$config_file"
  output=$(env -i HOME="$temp_home" PATH="$PATH" bash --noprofile --norc -c \
    '. "$1"; alias pstart >/dev/null; printf "%s" "$_PROXYCLI_RUNTIME_LOADED"' _ "$config_file")
  assert_equals '1' "$output" "startup loads a literal path containing shell characters"
)

test_installer_idempotence() (
  local temp_home fixture config_file
  temp_home=$(mktemp -d)
  trap 'rm -rf "$temp_home"' EXIT
  HOME="$temp_home"
  SHELL=/bin/bash
  set -- help
  source "$repo_root/install.sh" >/dev/null
  config_file="$temp_home/.bashrc"
  for fixture in '' ': no-final-newline' $': with-final-newline\n' $'\n: preserve-blank-lines\n\n\n'; do
    printf '%s' "$fixture" > "$config_file"
    configure_shell "$config_file"
    cp "$config_file" "$temp_home/first-config"
    configure_shell "$config_file"
    configure_shell "$config_file"
    cmp -s "$temp_home/first-config" "$config_file" || {
      echo 'FAIL: configuration must be identical after repeated installations' >&2
      exit 1
    }
    remove_config_block "$config_file"
    if [ -n "$fixture" ]; then
      case "$fixture" in
        *$'\n') printf '%s' "$fixture" ;;
        *) printf '%s\n' "$fixture" ;;
      esac
    fi > "$temp_home/expected-profile"
    cmp -s "$temp_home/expected-profile" "$config_file" || {
      echo 'FAIL: removing the configuration must preserve unrelated content and blank lines' >&2
      exit 1
    }
  done
)

test_noninteractive_prompt() (
  unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
  source "$repo_root/src/proxy-setup.sh" >/dev/null
  PS1='original> '
  PROMPT_COMMAND='original_prompt_command'
  set_proxy --address localhost:7890 >/dev/null
  start_proxy >/dev/null
  assert_equals 'original> ' "$PS1" "noninteractive start leaves PS1 unchanged"
  assert_equals 'original_prompt_command' "$PROMPT_COMMAND" "noninteractive start leaves prompt commands unchanged"
  stop_proxy >/dev/null
  assert_equals 'original> ' "$PS1" "noninteractive stop leaves PS1 unchanged"
)

test_interactive_prompt() (
  local temp_dir prompt_shell
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT
  declare -f assert_equals > "$temp_dir/prompt-test.sh"
  cat >> "$temp_dir/prompt-test.sh" <<'SHELL'
set -eu
unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
source "$1/src/proxy-setup.sh" >/dev/null
base_prompt=$'header\nuser@host:~> '
theme_prompt="$base_prompt"
theme_updates=0
PS1="$base_prompt"

run_prompt_hooks() {
  local hook_command prompt_attributes
  if [ -n "${ZSH_VERSION:-}" ]; then
    for hook_command in "${precmd_functions[@]}"; do "$hook_command"; done
  else
    prompt_attributes=$(declare -p PROMPT_COMMAND)
    prompt_attributes="${prompt_attributes#declare }"
    prompt_attributes="${prompt_attributes%% *}"
    case "$prompt_attributes" in
      *a*) for hook_command in "${PROMPT_COMMAND[@]}"; do eval "$hook_command"; done ;;
      *) eval "$PROMPT_COMMAND" ;;
    esac
  fi
}

if [ -n "${ZSH_VERSION:-}" ]; then
  theme_hook() { theme_updates=$((theme_updates + 1)); PS1="$theme_prompt"; }
  precmd_functions=(theme_hook)
  prompt_hook_variable=precmd_functions
else
  PROMPT_COMMAND='theme_updates=$((theme_updates + 1)); PS1="$theme_prompt" # keep this comment'
  original_prompt_command="$PROMPT_COMMAND"
  prompt_hook_variable=PROMPT_COMMAND
fi
assert_equals "$base_prompt" "$PS1" "loading commands leaves the prompt unchanged"
set_proxy --address localhost:7890 >/dev/null
assert_equals "$base_prompt" "$PS1" "saving settings does not add a prompt icon"
start_proxy >/dev/null
assert_equals "🚀 $base_prompt" "$PS1" "interactive start adds the rocket prefix"
registered_hooks=$(typeset -p "$prompt_hook_variable")
start_proxy >/dev/null
source "$1/src/proxy-setup.sh" >/dev/null
start_proxy >/dev/null
assert_equals "🚀 $base_prompt" "$PS1" "repeated starts and reloads do not duplicate the icon"
assert_equals "$registered_hooks" "$(typeset -p "$prompt_hook_variable")" "repeated starts and reloads do not duplicate hooks"

if [ -z "${ZSH_VERSION:-}" ]; then
  assert_equals "$original_prompt_command"$'\n_proxycli_bash_prompt' "$PROMPT_COMMAND" "Bash keeps the existing prompt command and its comment"
  set +e
  (exit 7)
  _proxycli_bash_prompt
  prompt_exit=$?
  set -e
  assert_equals '7' "$prompt_exit" "Bash prompt hook preserves exit status"
fi
theme_prompt='new theme> '
run_prompt_hooks
assert_equals '1' "$theme_updates" "existing theme hook still runs"
assert_equals '🚀 new theme> ' "$PS1" "theme updates keep the rocket prefix"
run_prompt_hooks
assert_equals '🚀 new theme> ' "$PS1" "prompt refresh does not duplicate the icon"
set_proxy --address localhost:9000 >/dev/null
assert_equals '🚀 new theme> ' "$PS1" "pending settings keep the active icon"
stop_proxy >/dev/null
assert_equals 'new theme> ' "$PS1" "stop removes the icon and preserves the current theme"
run_prompt_hooks
assert_equals 'new theme> ' "$PS1" "inactive prompt refresh does not add an icon"

toggle_proxy >/dev/null
assert_equals '🚀 new theme> ' "$PS1" "toggle on adds the icon"
toggle_proxy >/dev/null
assert_equals 'new theme> ' "$PS1" "toggle off removes the icon"
start_proxy >/dev/null
PS1='user override> '
stop_proxy >/dev/null
assert_equals 'user override> ' "$PS1" "stop preserves a prompt replaced by the user"

PS1=''
start_proxy >/dev/null
assert_equals '🚀 ' "$PS1" "an empty prompt gets an icon"
stop_proxy >/dev/null
assert_equals 'x' "${PS1+x}" "stop preserves an explicitly empty PS1"
assert_equals '' "$PS1" "stop restores the empty prompt"
unset PS1
start_proxy >/dev/null
stop_proxy >/dev/null
assert_equals '' "${PS1+x}" "stop restores an unset PS1"

PS1='failure test> '
set_proxy --address auto >/dev/null
detect_proxy() { return 1; }
if start_proxy >/dev/null 2>&1 || scan_proxy >/dev/null 2>&1; then
  echo 'FAIL: detection failure should fail activation' >&2
  exit 1
fi
assert_equals 'failure test> ' "$PS1" "failed activation does not add an icon"
detect_proxy() {
  PROXY_ADDRESS='http://localhost:7890'
  SOCKS_ADDRESS='socks5h://localhost:7890'
  _PROXYCLI_AUTO_READY=1
}
scan_proxy >/dev/null 2>&1
assert_equals '🚀 failure test> ' "$PS1" "successful scan also enables the icon"
stop_proxy >/dev/null

if [ -z "${ZSH_VERSION:-}" ]; then
  unset PROMPT_COMMAND
  PROMPT_COMMAND=()
  PROMPT_COMMAND[2]='theme_updates=$((theme_updates + 1))'
  PROMPT_COMMAND[5]='PS1="$theme_prompt"'
  export PROMPT_COMMAND
  theme_updates=0
  theme_prompt='array theme> '
  set_proxy --address localhost:7890 >/dev/null
  start_proxy >/dev/null
  assert_equals '3' "${#PROMPT_COMMAND[@]}" "Bash array gains one hook"
  assert_equals 'theme_updates=$((theme_updates + 1))' "${PROMPT_COMMAND[2]}" "existing sparse array index is preserved"
  assert_equals 'PS1="$theme_prompt"' "${PROMPT_COMMAND[5]}" "existing array theme command is preserved"
  run_prompt_hooks
  assert_equals '1' "$theme_updates" "array theme hooks still execute"
  assert_equals '🚀 array theme> ' "$PS1" "array prompt hooks preserve the icon"
  start_proxy >/dev/null
  assert_equals '3' "${#PROMPT_COMMAND[@]}" "repeated starts do not duplicate an array hook"
  stop_proxy >/dev/null
  assert_equals 'array theme> ' "$PS1" "array theme survives stop"
fi
SHELL
  for prompt_shell in bash "${PROXYCLI_TEST_ZSH:-zsh}"; do
    command -v "$prompt_shell" >/dev/null 2>&1 || continue
    if [ "$prompt_shell" = bash ]; then
      bash --noprofile --norc -i "$temp_dir/prompt-test.sh" "$repo_root" 2> "$temp_dir/stderr" || {
        cat "$temp_dir/stderr" >&2
        exit 1
      }
    else
      "$prompt_shell" -f -i "$temp_dir/prompt-test.sh" "$repo_root" 2> "$temp_dir/stderr" || {
        cat "$temp_dir/stderr" >&2
        exit 1
      }
    fi
  done
)

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
test_http_only_and_failed_scan
test_existing_environment_restart
test_validation_and_reload
test_settings_queries_and_application
test_shell_scope_and_help
test_installer_configuration
test_installer_literal_paths
test_installer_idempotence
test_noninteractive_prompt
test_interactive_prompt

echo "ProxyCli shell tests passed."
