#!/usr/bin/env bash
# ProxyCli runtime commands for Bash and Zsh.

# The endpoint is configurable for users in restricted networks.
PROXYCLI_TEST_URL="${PROXYCLI_TEST_URL:-https://example.com/}"
_PROXYCLI_DEFAULT_PORTS="7890 7891 7892 7893 7897 8888 8080"
_PROXYCLI_SCAN_PORTS="${_PROXYCLI_SCAN_PORTS:-$_PROXYCLI_DEFAULT_PORTS}"
_PROXYCLI_AUTO_READY="${_PROXYCLI_AUTO_READY:-0}"
_PROXYCLI_SETTINGS_PENDING="${_PROXYCLI_SETTINGS_PENDING:-0}"
_PROXYCLI_DEFAULT_INDICATOR="🚀"
_PROXYCLI_INDICATOR="${_PROXYCLI_INDICATOR:-$_PROXYCLI_DEFAULT_INDICATOR}"
_PROXYCLI_ACTIVE_INDICATOR="${_PROXYCLI_ACTIVE_INDICATOR:-$_PROXYCLI_DEFAULT_INDICATOR}"
PROXYCLI_MANUAL_PROXY="${PROXYCLI_MANUAL_PROXY:-0}"
_PROXYCLI_DYNAMIC_PORT_LIMIT=20
_PROXYCLI_SCAN_TIME_LIMIT=15
_PROXYCLI_PROCESS_PATTERN='clash|mihomo|sing[-_]?box|xray|v2ray|hysteria|trojan|ss-local|sslocal|shadowsocks|tuic'

_proxycli_redact_url() {
  case "$1" in
    *://*@*)
      printf '%s://***@%s' "${1%%://*}" "${1##*@}"
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
  } | awk '/^[0-9]+$/ && $1 >= 1 && $1 <= 65535 { port = $1 + 0; if (!seen[port]++) print port }'
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

_proxycli_probe_url() {
  curl -sS --connect-timeout 1 --max-time 3 \
    --noproxy "" --proxy "$1" "$PROXYCLI_TEST_URL" >/dev/null 2>&1
}

_proxycli_mark_settings_changed() {
  _PROXYCLI_AUTO_READY=0
  unset PROXYCLI_LAST_HTTP_PORT PROXYCLI_LAST_SOCKS_PORT
  _PROXYCLI_SETTINGS_PENDING=1
}

_proxycli_show_address_setting() {
  if [ "$PROXYCLI_MANUAL_PROXY" = "1" ]; then
    _proxycli_print_endpoints "${PROXY_ADDRESS:-}" "${SOCKS_ADDRESS:-}"
  else
    echo "  Address: automatic detection"
  fi
}

_proxycli_print_endpoints() {
  [ -z "${1:-}" ] || printf '  HTTP:  %s\n' "$(_proxycli_redact_url "$1")"
  [ -z "${2:-}" ] || printf '  SOCKS: %s\n' "$(_proxycli_redact_url "$2")"
  return 0
}

_proxycli_no_arguments() {
  if [ "$#" -ne 1 ]; then
    printf 'Usage: %s\n' "$1" >&2
    return 1
  fi
  return 0
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
  [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ] || return 0

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
  # Read one port per line without relying on Bash's implicit word splitting.
  while IFS= read -r port; do
    pending=""
    [ -z "$http_port" ] && pending="HTTP"
    [ -z "$socks_port" ] && pending="${pending:+$pending, }SOCKS5"
    echo "[ProxyCli] Scanning 127.0.0.1:${port} for ${pending}." >&2
    if [ -z "$http_port" ] && _proxycli_probe_url "http://127.0.0.1:$port"; then
      http_port="$port"
      echo "[ProxyCli] Found HTTP proxy on port ${port}." >&2
    fi
    if [ -z "$socks_port" ] && _proxycli_probe_url "socks5h://127.0.0.1:$port"; then
      socks_port="$port"
      echo "[ProxyCli] Found SOCKS5 proxy on port ${port}." >&2
    fi
    [ -n "$http_port" ] && [ -n "$socks_port" ] && break
    scan_now=${SECONDS:-0}
    if [ "$((scan_now - scan_started))" -ge "$_PROXYCLI_SCAN_TIME_LIMIT" ]; then
      break
    fi
  done <<EOF
$candidate_ports
EOF

  if [ -z "$http_port" ] && [ -z "$socks_port" ]; then
    echo "[ProxyCli] No working local proxy was detected." >&2
    return 1
  fi

  PROXY_ADDRESS=""
  SOCKS_ADDRESS=""
  if [ -n "$http_port" ]; then
    PROXY_ADDRESS="http://127.0.0.1:$http_port"
    PROXYCLI_LAST_HTTP_PORT="$http_port"
  else
    unset PROXYCLI_LAST_HTTP_PORT
  fi
  if [ -n "$socks_port" ]; then
    SOCKS_ADDRESS="socks5h://127.0.0.1:$socks_port"
    PROXYCLI_LAST_SOCKS_PORT="$socks_port"
  else
    unset PROXYCLI_LAST_SOCKS_PORT
  fi
  _PROXYCLI_AUTO_READY=1
  echo "[ProxyCli] Detected${http_port:+ HTTP on port $http_port}${socks_port:+ SOCKS5 on port $socks_port}." >&2
}

_proxycli_proxy_active() {
  [ "${PROXYCLI_ENV_SAVED:-0}" = "1" ]
}

# Add only our own prefix, preserving prompt content supplied by the shell/theme.
_proxycli_refresh_prompt() {
  local prompt_text="${PS1-}" prefix="$_PROXYCLI_ACTIVE_INDICATOR " has_prefix=0
  local previous_prefix="${_PROXYCLI_PROMPT_PREFIX:-${_PROXYCLI_DEFAULT_INDICATOR} }"

  case "$-" in *i*) ;; *) return 0 ;; esac
  if [ "${_PROXYCLI_PROMPT_PREFIX_ADDED:-0}" = "1" ]; then
    case "$prompt_text" in
      "$previous_prefix"*) prompt_text="${prompt_text#"$previous_prefix"}"; has_prefix=1 ;;
    esac
  fi

  if _proxycli_proxy_active; then
    if [ "$has_prefix" = "0" ]; then
      _PROXYCLI_PROMPT_WAS_SET="${PS1+x}"
    fi
    PS1="${prefix}${prompt_text}"
    _PROXYCLI_PROMPT_PREFIX="$prefix"
    _PROXYCLI_PROMPT_PREFIX_ADDED=1
  else
    if [ "$has_prefix" = "1" ]; then
      if [ "${_PROXYCLI_PROMPT_WAS_SET:-}" = x ] || [ -n "$prompt_text" ]; then
        PS1="$prompt_text"
      else
        unset PS1
      fi
    fi
    unset _PROXYCLI_PROMPT_PREFIX_ADDED _PROXYCLI_PROMPT_WAS_SET _PROXYCLI_PROMPT_PREFIX
  fi
  return 0
}

# Bash prompt commands share the previous command's exit status.
_proxycli_bash_prompt() {
  local previous_exit=$?
  _proxycli_refresh_prompt
  return "$previous_exit"
}

_proxycli_enable_prompt() {
  local hook installed=0 declaration

  case "$-" in *i*) ;; *) return 0 ;; esac
  if [ -n "${ZSH_VERSION:-}" ]; then
    for hook in "${precmd_functions[@]-}"; do
      [ "$hook" != _proxycli_refresh_prompt ] || installed=1
    done
    [ "$installed" = "1" ] || precmd_functions+=(_proxycli_refresh_prompt)
  else
    declaration=$(declare -p PROMPT_COMMAND 2>/dev/null) || declaration=""
    declaration="${declaration#declare }"
    declaration="${declaration%% *}"
    case "$declaration" in
      *a*)
        for hook in "${PROMPT_COMMAND[@]-}"; do
          [ "$hook" != _proxycli_bash_prompt ] || installed=1
        done
        [ "$installed" = "1" ] || PROMPT_COMMAND+=(_proxycli_bash_prompt)
        ;;
      *)
        # A newline also supports existing commands ending in a shell comment.
        case $'\n'"${PROMPT_COMMAND-}"$'\n' in
          *$'\n_proxycli_bash_prompt\n'*) ;;
          *) PROMPT_COMMAND="${PROMPT_COMMAND-}"$'\n_proxycli_bash_prompt' ;;
        esac
        ;;
    esac
  fi
  _proxycli_refresh_prompt
}

_proxycli_apply_environment() {
  local was_saved="${PROXYCLI_ENV_SAVED:-0}"

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
}

_proxycli_activate_proxy() {
  if [ -z "${PROXY_ADDRESS:-}" ] && [ -z "${SOCKS_ADDRESS:-}" ]; then
    echo "[ProxyCli] Set a proxy with: pset --address host:port" >&2
    return 1
  fi

  _proxycli_apply_environment || return 1
  _PROXYCLI_SETTINGS_PENDING=0
  _PROXYCLI_ACTIVE_INDICATOR="$_PROXYCLI_INDICATOR"
  _proxycli_enable_prompt
  echo "[ProxyCli] Proxy variables enabled (current shell)."
  _proxycli_print_endpoints "${PROXY_ADDRESS:-}" "${SOCKS_ADDRESS:-}"
}

start_proxy() {
  _proxycli_no_arguments pstart "$@" || return 1

  if [ "$PROXYCLI_MANUAL_PROXY" != "1" ]; then
    if [ "$_PROXYCLI_SETTINGS_PENDING" = "1" ]; then
      detect_proxy || return 1
    elif [ "$_PROXYCLI_AUTO_READY" = "1" ]; then
      if _proxycli_cached_proxy_available; then
        echo "[ProxyCli] Reusing the last detected proxy." >&2
      else
        echo "[ProxyCli] Cached proxy unavailable; rescanning." >&2
        detect_proxy || return 1
      fi
    elif _proxycli_use_existing_proxy; then
      echo "[ProxyCli] Reusing existing proxy environment." >&2
    elif ! detect_proxy; then
      echo "[ProxyCli] Try pset --address host:port, then pstart." >&2
      return 1
    fi
  fi

  _proxycli_activate_proxy
}

scan_proxy() {
  _proxycli_no_arguments pscan "$@" || return 1
  echo "[ProxyCli] Scanning local HTTP and SOCKS5 proxies." >&2
  detect_proxy || return 1

  PROXYCLI_MANUAL_PROXY=0
  _proxycli_activate_proxy
}

stop_proxy() {
  _proxycli_no_arguments pstop "$@" || return 1
  if ! _proxycli_proxy_active; then
    echo "[ProxyCli] Inactive; environment unchanged."
    return 0
  fi

  _proxycli_restore_environment
  _proxycli_refresh_prompt
  echo "[ProxyCli] Stopped; previous proxy environment restored."
}

toggle_proxy() {
  _proxycli_no_arguments ptoggle "$@" || return 1
  if _proxycli_proxy_active; then
    stop_proxy
  else
    start_proxy
  fi
}

proxy_status() {
  local current_http current_socks
  _proxycli_no_arguments pstatus "$@" || return 1
  current_http="${http_proxy:-${HTTP_PROXY:-${https_proxy:-${HTTPS_PROXY:-}}}}"
  current_socks="${all_proxy:-${ALL_PROXY:-}}"
  if _proxycli_proxy_active; then
    echo "[ProxyCli] Status: ACTIVE (current shell)"
  else
    echo "[ProxyCli] Status: INACTIVE (current shell)"
  fi
  _proxycli_print_endpoints "$current_http" "$current_socks"
  if [ "$_PROXYCLI_SETTINGS_PENDING" = "1" ] ||
     [ "$_PROXYCLI_INDICATOR" != "$_PROXYCLI_ACTIVE_INDICATOR" ]; then
    echo "[ProxyCli] Settings pending; run pstart to apply."
  fi
  [ -n "$current_http" ] || [ -n "$current_socks" ] || return 0

  command -v curl >/dev/null 2>&1 || {
    echo "[ProxyCli] curl is required for connectivity checks." >&2
    return 1
  }

  if curl -sS --connect-timeout 1 --max-time 3 --noproxy '*' --proxy '' "$PROXYCLI_TEST_URL" >/dev/null 2>&1; then
    echo "  Direct network: available"
  else
    echo "  Direct network: unavailable"
  fi

  if [ -n "$current_http" ]; then
    if _proxycli_probe_url "$current_http"; then
      echo "  HTTP proxy: working"
    else
      echo "  HTTP proxy: unavailable"
    fi
  fi

  if [ -n "$current_socks" ]; then
    if _proxycli_probe_url "$current_socks"; then
      echo "  SOCKS5 proxy: working"
    else
      echo "  SOCKS5 proxy: unavailable"
    fi
  fi
}

_proxycli_normalize_port() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 5 ] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ] || return 1
  printf '%s' "$((10#$1))"
}

# Normalize a host:port or proxy URL before changing session state.
_proxycli_normalize_address() {
  local input=$1 protocol=$2 authority host port ipv6 userinfo=""
  case "$input" in
    ''|-*|*[[:space:]]*) return 1 ;;
  esac
  case "$input" in
    http://*|https://*)
      [ "$protocol" != http ] || protocol="${input%%://*}"
      authority="${input#*://}"
      ;;
    socks5://*|socks5h://*)
      [ "$protocol" = socks5 ] || return 1
      protocol="${input%%://*}"
      authority="${input#*://}"
      ;;
    *://*) return 1 ;;
    *) authority="$input" ;;
  esac
  case "$authority" in
    ''|-*|*[[:space:]/?\#]*) return 1 ;;
  esac
  case "$authority" in
    *@*)
      userinfo="${authority%@*}"
      case "$userinfo" in ''|*@*) return 1 ;; esac
      authority="${authority##*@}"
      userinfo="${userinfo}@"
      ;;
  esac
  port="${authority##*:}"
  host="${authority%:*}"
  [ "$host" != "$authority" ] || return 1
  case "$host" in
    \[*\])
      ipv6="${host#\[}"
      ipv6="${ipv6%\]}"
      case "$ipv6" in ''|*[![:alnum:]:.%_-]*) return 1 ;; esac
      case "$ipv6" in *:*) ;; *) return 1 ;; esac
      ;;
    ''|-*|*[![:alnum:]._-]*) return 1 ;;
  esac
  port=$(_proxycli_normalize_port "$port") || return 1
  printf '%s://%s%s:%s' "$protocol" "$userinfo" "$host" "$port"
}

set_proxy() {
  local option

  if [ "$#" -eq 0 ]; then
    echo "[ProxyCli] Current settings:"
    _proxycli_show_address_setting
    echo "  Scan ports: $_PROXYCLI_SCAN_PORTS"
    printf '  Indicator: %s\n' "$_PROXYCLI_INDICATOR"
    return 0
  fi

  option="$1"
  shift
  case "$option" in
    --address) _proxycli_set_address "$@" ;;
    --ports) _proxycli_set_scan_ports "$@" ;;
    --indicator) _proxycli_set_indicator "$@" ;;
    *)
      printf '[ProxyCli] Unknown setting: %s. Run phelp for usage.\n' "$option" >&2
      return 1
      ;;
  esac
}

_proxycli_set_address() {
  local http_input socks_input new_http new_socks

  if [ "$#" -eq 0 ]; then
    _proxycli_show_address_setting
    return 0
  fi

  if [ "${1:-}" = auto ]; then
    if [ "$#" -ne 1 ]; then
      echo "Usage: pset --address auto" >&2
      return 1
    fi
    PROXYCLI_MANUAL_PROXY=0
    _proxycli_mark_settings_changed
    unset PROXY_ADDRESS SOCKS_ADDRESS
    echo "[ProxyCli] Address: automatic detection. Run pstart to apply."
    return 0
  fi

  http_input="${1:-}"
  socks_input="${2-$http_input}"
  if [ "$#" -gt 2 ]; then
    echo "Usage: pset --address [http://]host:port [socks5://host:port]" >&2
    echo "       pset --address auto" >&2
    return 1
  fi

  if ! new_http=$(_proxycli_normalize_address "$http_input" http) ||
     ! new_socks=$(_proxycli_normalize_address "$socks_input" socks5); then
    echo "[ProxyCli] Invalid address. Use host:port (port 1-65535); bracket IPv6 hosts." >&2
    echo "Usage: pset --address [http://]host:port [socks5://host:port]" >&2
    return 1
  fi

  PROXY_ADDRESS="$new_http"
  SOCKS_ADDRESS="$new_socks"

  PROXYCLI_MANUAL_PROXY=1
  _proxycli_mark_settings_changed
  echo "[ProxyCli] Address saved. Run pstart to apply."
  _proxycli_show_address_setting
}

_proxycli_set_indicator() {
  local indicator="${1:-}"

  if [ "$#" -eq 0 ]; then
    printf '[ProxyCli] Indicator: %s\n' "$_PROXYCLI_INDICATOR"
    return 0
  fi
  if [ "$#" -ne 1 ]; then
    echo "Usage: pset --indicator [emoji|auto]" >&2
    return 1
  fi
  [ "$indicator" != auto ] || indicator="$_PROXYCLI_DEFAULT_INDICATOR"
  # Prompt strings interpret shell escapes, so accept only literal symbols.
  case "$indicator" in
    ''|-*|*[[:space:][:cntrl:]]*|*'$'*|*'`'*|*'\'*|*'%'*|*'!'*)
      echo "[ProxyCli] Invalid indicator. Use one emoji or symbol without spaces or prompt escapes." >&2
      return 1
      ;;
  esac
  _PROXYCLI_INDICATOR="$indicator"
  printf '[ProxyCli] Indicator saved: %s. Run pstart to apply.\n' "$_PROXYCLI_INDICATOR"
}

_proxycli_set_scan_ports() {
  local input port ports=""

  if [ "$#" -eq 0 ]; then
    echo "[ProxyCli] Scan ports: $_PROXYCLI_SCAN_PORTS"
    return 0
  fi
  if [ "$1" = auto ]; then
    if [ "$#" -ne 1 ]; then
      echo "Usage: pset --ports [port ...|auto]" >&2
      return 1
    fi
    ports="$_PROXYCLI_DEFAULT_PORTS"
  else
    for input in "$@"; do
      if ! port=$(_proxycli_normalize_port "$input"); then
        printf '[ProxyCli] Invalid port: %s. Use an integer from 1 to 65535.\n' "$input" >&2
        return 1
      fi
      case " $ports " in
        *" $port "*) ;;
        *) ports="${ports:+$ports }$port" ;;
      esac
    done
  fi

  _PROXYCLI_SCAN_PORTS="$ports"
  _proxycli_mark_settings_changed
  echo "[ProxyCli] Scan ports saved: $_PROXYCLI_SCAN_PORTS. Run pstart to apply."
}

show_help() {
  _proxycli_no_arguments phelp "$@" || return 1
  cat <<'EOF'
ProxyCli commands:
  pstart                 Enable this shell's proxy
  pscan                  Rescan local proxies and enable the result
  pstop                  Restore the previous proxy environment
  ptoggle                Start or stop ProxyCli
  pstatus                Show proxy state and check connectivity
  pset                   Show all settings
  phelp                  Show this help

Settings (current session; run pstart to apply):
  pset --address host:port         Set HTTP and SOCKS5 address
  pset --ports 7890 1080           Set scan ports
  pset --indicator 🌐             Set prompt icon (default: 🚀)

Restore defaults:
  pset --address auto              Use automatic detection
  pset --ports auto                Restore default scan ports
  pset --indicator auto            Restore 🚀

View one setting: pset --address, pset --ports, or pset --indicator
For separate addresses: pset --address http_host:port socks_host:port
Proxy variables apply to this shell and programs started from it.
The prompt icon indicates ProxyCli is active; pstatus checks connectivity.
EOF
}

alias pstart='start_proxy'
alias pscan='scan_proxy'
alias pstop='stop_proxy'
alias ptoggle='toggle_proxy'
alias pstatus='proxy_status'
alias pset='set_proxy'
alias phelp='show_help'
unalias pports 2>/dev/null || true

_PROXYCLI_RUNTIME_LOADED=1
case "$-" in
  *i*) echo "[ProxyCli] Loaded. Type 'phelp' for commands." ;;
esac
