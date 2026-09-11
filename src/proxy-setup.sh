#!/usr/bin/env bash
# ProxyCli runtime commands for Bash and Zsh.

# The endpoint is configurable for users in restricted networks.
PROXYCLI_TEST_URL="${PROXYCLI_TEST_URL:-https://example.com/}"
_PROXYCLI_DEFAULT_PORTS="7890 7891 7892 7893 7897 8888 8080"
_PROXYCLI_SCAN_PORTS="$_PROXYCLI_DEFAULT_PORTS"
_PROXYCLI_AUTO_READY=0
PROXYCLI_MANUAL_PROXY="${PROXYCLI_MANUAL_PROXY:-0}"
_PROXYCLI_DYNAMIC_PORT_LIMIT=20
_PROXYCLI_SCAN_TIME_LIMIT=15
_PROXYCLI_PROCESS_PATTERN='clash|mihomo|sing[-_]?box|xray|v2ray|hysteria|trojan|ss-local|sslocal|shadowsocks|tuic'

_proxycli_redact_url() {
  case "$1" in
    *://*@*)
      printf '%s://***@%s' "${1%%://*}" "${1#*@}"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

_proxycli_listeners() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP -sTCP:LISTEN -F cPn 2>/dev/null | awk -v proxy_processes="$_PROXYCLI_PROCESS_PATTERN" '
      /^c/ { command = tolower(substr($0, 2)); next }
      /^n/ {
        port = substr($0, 2)
        sub(/.*:/, "", port)
        if (port ~ /^[0-9]+$/) {
          priority = command ~ proxy_processes ? 0 : 1
          print priority, port, command
        }
      }
    '
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -ltnpH 2>/dev/null | awk -v proxy_processes="$_PROXYCLI_PROCESS_PATTERN" '
      {
        port = $4
        sub(/.*:/, "", port)
        if (port ~ /^[0-9]+$/) {
          line = tolower($0)
          count = split(line, fields, "\"")
          process = count >= 2 ? fields[2] : "unknown"
          if (process ~ proxy_processes) {
            priority = 0
          } else {
            priority = 1
          }
          print priority, port, process
        }
      }
    '
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | awk '
      /LISTEN/ {
        port = $4
        sub(/.*[.:]/, "", port)
        if (port ~ /^[0-9]+$/) print 1, port, "unknown"
      }
    '
  fi
}

_proxycli_candidate_ports() {
  local listeners proxy_listeners

  listeners="$(_proxycli_listeners)"
  proxy_listeners=$(printf '%s\n' "$listeners" | awk '
    $1 == 0 && !seen[$2]++ {
      item = ($3 && $3 != "unknown" ? $3 : "proxy") ":" $2
      result = result (result ? " " : "") item
    }
    END { print result }
  ')
  if [ -n "$proxy_listeners" ]; then
    echo "[ProxyCli] Proxy process listeners: $proxy_listeners." >&2
  else
    echo "[ProxyCli] Proxy process listeners: none detected." >&2
  fi
  {
    printf '%s\n' "${PROXYCLI_LAST_HTTP_PORT:-}" "${PROXYCLI_LAST_SOCKS_PORT:-}"
    printf '%s\n' "$listeners" | awk '$1 == 0 { print $2 }'
    printf '%s\n' "$_PROXYCLI_SCAN_PORTS" | awk '{ for (i = 1; i <= NF; i++) print $i }'
    printf '%s\n' "$listeners" | awk -v limit="$_PROXYCLI_DYNAMIC_PORT_LIMIT" '
      $1 != 0 && count < limit { print $2; count++ }
    '
  } | awk '/^[0-9]+$/ && $1 <= 65535 && !seen[$1]++'
}

_proxycli_cached_proxy_available() {
  local checked=0 endpoint label listeners port

  listeners="$(_proxycli_listeners)"
  if [ -z "$listeners" ]; then
    echo "[ProxyCli] Cached check: no matching local listeners were found." >&2
    return 1
  fi

  for endpoint in "${PROXY_ADDRESS:-}" "${SOCKS_ADDRESS:-}"; do
    [ -n "$endpoint" ] || continue
    checked=1
    port="${endpoint##*:}"
    port="${port%%/*}"
    case "$endpoint" in
      socks*) label="SOCKS5" ;;
      *) label="HTTP" ;;
    esac
    echo "[ProxyCli] Cached check: ${label} on 127.0.0.1:${port}." >&2
    if ! printf '%s\n' "$listeners" | awk -v expected="$port" '$2 == expected { found = 1 } END { exit !found }'; then
      echo "[ProxyCli] Cached check: port ${port} is no longer listening." >&2
      return 1
    fi
  done
  [ "$checked" = "1" ] && echo "[ProxyCli] Cached check: all proxy ports are listening." >&2
  [ "$checked" = "1" ]
}

_proxycli_probe_http_url() {
  curl -sS --connect-timeout 1 --max-time 3 \
    --noproxy "" --proxy "$1" "$PROXYCLI_TEST_URL" >/dev/null 2>&1
}

_proxycli_probe_socks_url() {
  curl -sS --connect-timeout 1 --max-time 3 \
    --noproxy "" --proxy "$1" "$PROXYCLI_TEST_URL" >/dev/null 2>&1
}

_proxycli_use_existing_proxy() {
  local existing_http existing_socks

  existing_http="${http_proxy:-${HTTP_PROXY:-${https_proxy:-${HTTPS_PROXY:-}}}}"
  existing_socks="${all_proxy:-${ALL_PROXY:-}}"

  [ -n "$existing_http" ] || [ -n "$existing_socks" ] || return 1

  PROXY_ADDRESS="$existing_http"
  SOCKS_ADDRESS="$existing_socks"
  return 0
}

_proxycli_save_environment() {
  [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ] && return

  if [ "${http_proxy+x}" = "x" ]; then PROXYCLI_SAVED_http_proxy_SET=1; fi
  if [ "${HTTP_PROXY+x}" = "x" ]; then PROXYCLI_SAVED_HTTP_PROXY_SET=1; fi
  if [ "${https_proxy+x}" = "x" ]; then PROXYCLI_SAVED_https_proxy_SET=1; fi
  if [ "${HTTPS_PROXY+x}" = "x" ]; then PROXYCLI_SAVED_HTTPS_PROXY_SET=1; fi
  if [ "${all_proxy+x}" = "x" ]; then PROXYCLI_SAVED_all_proxy_SET=1; fi
  if [ "${ALL_PROXY+x}" = "x" ]; then PROXYCLI_SAVED_ALL_PROXY_SET=1; fi
  if [ "${no_proxy+x}" = "x" ]; then PROXYCLI_SAVED_no_proxy_SET=1; fi
  if [ "${NO_PROXY+x}" = "x" ]; then PROXYCLI_SAVED_NO_PROXY_SET=1; fi

  PROXYCLI_SAVED_http_proxy="${http_proxy-}"
  PROXYCLI_SAVED_HTTP_PROXY="${HTTP_PROXY-}"
  PROXYCLI_SAVED_https_proxy="${https_proxy-}"
  PROXYCLI_SAVED_HTTPS_PROXY="${HTTPS_PROXY-}"
  PROXYCLI_SAVED_all_proxy="${all_proxy-}"
  PROXYCLI_SAVED_ALL_PROXY="${ALL_PROXY-}"
  PROXYCLI_SAVED_no_proxy="${no_proxy-}"
  PROXYCLI_SAVED_NO_PROXY="${NO_PROXY-}"
  PROXYCLI_ENV_SAVED=1
}

_proxycli_restore_environment() {
  [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ] || return

  [ "${PROXYCLI_SAVED_http_proxy_SET:-0}" = "1" ] && export http_proxy="$PROXYCLI_SAVED_http_proxy" || unset http_proxy
  [ "${PROXYCLI_SAVED_HTTP_PROXY_SET:-0}" = "1" ] && export HTTP_PROXY="$PROXYCLI_SAVED_HTTP_PROXY" || unset HTTP_PROXY
  [ "${PROXYCLI_SAVED_https_proxy_SET:-0}" = "1" ] && export https_proxy="$PROXYCLI_SAVED_https_proxy" || unset https_proxy
  [ "${PROXYCLI_SAVED_HTTPS_PROXY_SET:-0}" = "1" ] && export HTTPS_PROXY="$PROXYCLI_SAVED_HTTPS_PROXY" || unset HTTPS_PROXY
  [ "${PROXYCLI_SAVED_all_proxy_SET:-0}" = "1" ] && export all_proxy="$PROXYCLI_SAVED_all_proxy" || unset all_proxy
  [ "${PROXYCLI_SAVED_ALL_PROXY_SET:-0}" = "1" ] && export ALL_PROXY="$PROXYCLI_SAVED_ALL_PROXY" || unset ALL_PROXY
  [ "${PROXYCLI_SAVED_no_proxy_SET:-0}" = "1" ] && export no_proxy="$PROXYCLI_SAVED_no_proxy" || unset no_proxy
  [ "${PROXYCLI_SAVED_NO_PROXY_SET:-0}" = "1" ] && export NO_PROXY="$PROXYCLI_SAVED_NO_PROXY" || unset NO_PROXY

  unset PROXYCLI_ENV_SAVED PROXYCLI_SAVED_http_proxy_SET PROXYCLI_SAVED_HTTP_PROXY_SET
  unset PROXYCLI_SAVED_https_proxy_SET PROXYCLI_SAVED_HTTPS_PROXY_SET
  unset PROXYCLI_SAVED_all_proxy_SET PROXYCLI_SAVED_ALL_PROXY_SET
  unset PROXYCLI_SAVED_no_proxy_SET PROXYCLI_SAVED_NO_PROXY_SET
  unset PROXYCLI_SAVED_http_proxy PROXYCLI_SAVED_HTTP_PROXY
  unset PROXYCLI_SAVED_https_proxy PROXYCLI_SAVED_HTTPS_PROXY
  unset PROXYCLI_SAVED_all_proxy PROXYCLI_SAVED_ALL_PROXY
  unset PROXYCLI_SAVED_no_proxy PROXYCLI_SAVED_NO_PROXY
}

_proxycli_add_local_no_proxy() {
  no_proxy="localhost,127.0.0.1,::1${no_proxy:+,$no_proxy}"
  NO_PROXY="localhost,127.0.0.1,::1${NO_PROXY:+,$NO_PROXY}"
  export no_proxy NO_PROXY
}

# Detect HTTP and SOCKS5 listeners independently. Cached and proxy-process
# ports are tried first, followed by configured and other listening ports.
detect_proxy() {
  local candidate_ports pending port scan_now scan_started http_port="" socks_port=""

  _PROXYCLI_AUTO_READY=0

  if ! command -v curl >/dev/null 2>&1; then
    echo "[ProxyCli] curl is required for proxy detection." >&2
    return 1
  fi

  candidate_ports="$(_proxycli_candidate_ports)"
  if [ -z "$candidate_ports" ]; then
    echo "[ProxyCli] Scan: no candidate ports were found." >&2
    return 1
  fi

  echo "[ProxyCli] Scan candidates: $(printf '%s\n' "$candidate_ports" | awk '{ ports = ports (ports ? " " : "") $1 } END { print ports }')." >&2
  scan_started=${SECONDS:-0}
  for port in $candidate_ports; do
    pending=""
    [ -z "$http_port" ] && pending="HTTP"
    [ -z "$socks_port" ] && pending="${pending:+$pending, }SOCKS5"
    echo "[ProxyCli] Scanning 127.0.0.1:${port} for ${pending}." >&2
    if [ -z "$http_port" ] && _proxycli_probe_http_url "http://127.0.0.1:$port"; then
      http_port="$port"
      echo "[ProxyCli] Found HTTP proxy on port ${port}." >&2
    fi
    if [ -z "$socks_port" ] && _proxycli_probe_socks_url "socks5h://127.0.0.1:$port"; then
      socks_port="$port"
      echo "[ProxyCli] Found SOCKS5 proxy on port ${port}." >&2
    fi
    [ -n "$http_port" ] && [ -n "$socks_port" ] && break
    scan_now=${SECONDS:-0}
    if [ "$((scan_now - scan_started))" -ge "$_PROXYCLI_SCAN_TIME_LIMIT" ]; then
      break
    fi
  done

  if [ -z "$http_port" ] && [ -z "$socks_port" ]; then
    echo "[ProxyCli] No working local proxy was detected." >&2
    return 1
  fi

  PROXY_ADDRESS=""
  SOCKS_ADDRESS=""
  if [ -n "$http_port" ]; then
    PROXY_ADDRESS="http://127.0.0.1:$http_port"
    PROXYCLI_LAST_HTTP_PORT="$http_port"
  fi
  if [ -n "$socks_port" ]; then
    SOCKS_ADDRESS="socks5://127.0.0.1:$socks_port"
    PROXYCLI_LAST_SOCKS_PORT="$socks_port"
  else
    unset PROXYCLI_LAST_SOCKS_PORT
  fi
  _PROXYCLI_AUTO_READY=1
  echo "[ProxyCli] Detected${http_port:+ HTTP on port $http_port}${socks_port:+ SOCKS5 on port $socks_port}." >&2
}

start_proxy() {
  local mode="${1:-}" was_saved="${PROXYCLI_ENV_SAVED:-0}"

  case "$mode" in
    ''|--skip-detect) ;;
    *)
      echo "Usage: pstart" >&2
      return 1
      ;;
  esac

  if [ "$mode" != "--skip-detect" ] && [ "$PROXYCLI_MANUAL_PROXY" != "1" ]; then
    if [ "$_PROXYCLI_AUTO_READY" = "1" ] && _proxycli_cached_proxy_available; then
      echo "[ProxyCli] Reusing the last detected proxy." >&2
    elif [ "$_PROXYCLI_AUTO_READY" = "1" ]; then
      echo "[ProxyCli] Passive mode: cached proxy is unavailable; starting a new scan." >&2
      detect_proxy || return 1
    elif [ "$was_saved" != "1" ] && _proxycli_use_existing_proxy; then
      echo "[ProxyCli] Reusing existing proxy environment." >&2
    elif ! detect_proxy; then
      echo "[ProxyCli] Passive mode: no reusable proxy; automatic scan failed." >&2
      return 1
    fi
  fi

  if [ -z "${PROXY_ADDRESS:-}" ] && [ -z "${SOCKS_ADDRESS:-}" ]; then
    echo "[ProxyCli] Set a proxy with: pset host:port" >&2
    return 1
  fi

  _proxycli_save_environment
  [ "$was_saved" = "1" ] || _proxycli_add_local_no_proxy

  if [ -n "${PROXY_ADDRESS:-}" ]; then
    export http_proxy="$PROXY_ADDRESS" HTTP_PROXY="$PROXY_ADDRESS"
    export https_proxy="$PROXY_ADDRESS" HTTPS_PROXY="$PROXY_ADDRESS"
  else
    unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY
  fi
  if [ -n "${SOCKS_ADDRESS:-}" ]; then
    export all_proxy="$SOCKS_ADDRESS" ALL_PROXY="$SOCKS_ADDRESS"
  else
    unset all_proxy ALL_PROXY
  fi

  echo "[ProxyCli] Active"
  [ -n "${PROXY_ADDRESS:-}" ] && echo "  HTTP:  $(_proxycli_redact_url "$PROXY_ADDRESS")"
  [ -n "${SOCKS_ADDRESS:-}" ] && echo "  SOCKS: $(_proxycli_redact_url "$SOCKS_ADDRESS")"
}

scan_proxy() {
  echo "[ProxyCli] Active mode: scanning local ports for HTTP and SOCKS5 proxies." >&2
  if ! detect_proxy; then
    return 1
  fi

  PROXYCLI_MANUAL_PROXY=0
  start_proxy --skip-detect
}

stop_proxy() {
  if [ "${PROXYCLI_ENV_SAVED:-0}" != "1" ]; then
    echo "[ProxyCli] No ProxyCli-managed proxy environment is active."
    return 0
  fi

  _proxycli_restore_environment
  echo "[ProxyCli] Disabled; restored the previous proxy environment."
}

toggle_proxy() {
  if [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ]; then
    stop_proxy
  else
    start_proxy
  fi
}

proxy_status() {
  if [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ]; then
    echo "[ProxyCli] Current status: ACTIVE"
    [ -n "${http_proxy:-}" ] && echo "  HTTP:  $(_proxycli_redact_url "$http_proxy")"
    [ -n "${all_proxy:-}" ] && echo "  SOCKS: $(_proxycli_redact_url "$all_proxy")"
  else
    echo "[ProxyCli] Current status: INACTIVE"
    return 0
  fi

  if curl -fsSI --connect-timeout 1 --max-time 3 --noproxy '*' "$PROXYCLI_TEST_URL" >/dev/null 2>&1; then
    echo "  Direct network: available"
  else
    echo "  Direct network: unavailable"
  fi

  if [ -n "${PROXY_ADDRESS:-}" ]; then
    if _proxycli_probe_http_url "$PROXY_ADDRESS"; then
      echo "  HTTP proxy: working"
    else
      echo "  HTTP proxy: unavailable"
    fi
  fi

  if [ -n "${SOCKS_ADDRESS:-}" ]; then
    if _proxycli_probe_socks_url "$SOCKS_ADDRESS"; then
      echo "  SOCKS5 proxy: working"
    else
      echo "  SOCKS5 proxy: unavailable"
    fi
  fi
}

set_proxy() {
  local http_input socks_input address

  if [ "${1:-}" = "--auto" ]; then
    if [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ]; then
      stop_proxy >/dev/null
    fi
    PROXYCLI_MANUAL_PROXY=0
    _PROXYCLI_AUTO_READY=0
    unset PROXY_ADDRESS SOCKS_ADDRESS
    scan_proxy
    return
  fi

  http_input="${1:-}"
  socks_input="${2:-$http_input}"
  if [ -z "$http_input" ] || [[ "$http_input" = *[[:space:]]* ]] || [[ "$socks_input" = *[[:space:]]* ]]; then
    echo "Usage: pset [http://]host:port [socks5://host:port]" >&2
    echo "       pset --auto" >&2
    return 1
  fi

  case "$http_input" in
    http://*|https://*) PROXY_ADDRESS="$http_input" ;;
    *) PROXY_ADDRESS="http://$http_input" ;;
  esac
  case "$socks_input" in
    socks5://*|socks5h://*) SOCKS_ADDRESS="$socks_input" ;;
    http://*) SOCKS_ADDRESS="socks5://${socks_input#http://}" ;;
    https://*) SOCKS_ADDRESS="socks5://${socks_input#https://}" ;;
    *) SOCKS_ADDRESS="socks5://$socks_input" ;;
  esac

  address="$(_proxycli_redact_url "$PROXY_ADDRESS")"
  PROXYCLI_MANUAL_PROXY=1
  _PROXYCLI_AUTO_READY=0
  echo "[ProxyCli] Manual HTTP proxy set to: $address"
  start_proxy --skip-detect
}

set_scan_ports() {
  local port ports=""

  case "${1:-}" in
    '')
      echo "[ProxyCli] Scan ports: $_PROXYCLI_SCAN_PORTS"
      return 0
      ;;
    --reset)
      if [ "$#" -ne 1 ]; then
        echo "Usage: pports [port ...|--reset]" >&2
        return 1
      fi
      _PROXYCLI_SCAN_PORTS="$_PROXYCLI_DEFAULT_PORTS"
      _PROXYCLI_AUTO_READY=0
      unset PROXYCLI_LAST_HTTP_PORT PROXYCLI_LAST_SOCKS_PORT
      echo "[ProxyCli] Scan ports reset: $_PROXYCLI_SCAN_PORTS"
      return 0
      ;;
  esac

  for port in "$@"; do
    case "$port" in
      ''|*[!0-9]*)
        echo "[ProxyCli] Invalid port: $port" >&2
        return 1
        ;;
    esac
    if [ "${#port}" -gt 5 ] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      echo "[ProxyCli] Invalid port: $port" >&2
      return 1
    fi
    case " $ports " in
      *" $port "*) ;;
      *) ports="${ports:+$ports }$port" ;;
    esac
  done

  _PROXYCLI_SCAN_PORTS="$ports"
  _PROXYCLI_AUTO_READY=0
  unset PROXYCLI_LAST_HTTP_PORT PROXYCLI_LAST_SOCKS_PORT
  echo "[ProxyCli] Scan ports set: $_PROXYCLI_SCAN_PORTS"
}

show_help() {
  cat <<'EOF'
ProxyCli commands:
  pstart                 Reuse a valid proxy or scan when unavailable
  pscan                  Force proxy detection and enable the result
  pstop                  Disable ProxyCli and restore prior proxy variables
  ptoggle                Toggle ProxyCli proxy settings
  pstatus                Show current ProxyCli proxy status
  pset host:port         Set one HTTP/SOCKS5 endpoint manually
  pset http://h:p socks5://h:p
                         Set HTTP and SOCKS5 endpoints separately
  pset --auto            Return to automatic detection
  pports                 Show automatic scan ports
  pports port ...        Replace the automatic scan ports
  pports --reset         Restore the default scan ports
  phelp                  Show this help
EOF
}

alias pstart='start_proxy'
alias pscan='scan_proxy'
alias pstop='stop_proxy'
alias ptoggle='toggle_proxy'
alias pstatus='proxy_status'
alias pset='set_proxy'
alias pports='set_scan_ports'
alias phelp='show_help'

echo "[ProxyCli] Loaded. Type 'phelp' for commands."
