#!/usr/bin/env bash
# ProxyCli installer for Bash and Zsh.

set -u

case "${HOME:-}" in
  /*)
    if [ "$HOME" = "/" ]; then
      printf '[ProxyCli] HOME must not be the filesystem root.\n' >&2
      return 1 2>/dev/null || exit 1
    fi
    ;;
  *)
    printf '[ProxyCli] HOME must be an absolute path.\n' >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

PROJECT_NAME="ProxyCli"
REPO_SLUG="baixiaoshengofficial/ProxyCli"
RAW_BASE_URL="https://raw.githubusercontent.com/${REPO_SLUG}/main"
INSTALL_DIR="${HOME}/.proxycli"
LEGACY_INSTALL_DIR="${HOME}/.proxy-manager"
SOURCE_FILE="${INSTALL_DIR}/src/proxy-setup.sh"
MARKER_BEGIN="# >>> ProxyCli configuration >>>"
MARKER_END="# <<< ProxyCli configuration <<<"
LEGACY_MARKER="# Proxy Manager Configuration"

print_error() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$1" >&2
}

print_success() {
  printf '[%s] %s\n' "$PROJECT_NAME" "$1"
}

detect_shell() {
  local shell_name

  case "${SHELL:-unknown}" in
    */*)
      shell_name="${SHELL##*/}"
      ;;
    *)
      shell_name="${SHELL:-unknown}"
      ;;
  esac

  case "$shell_name" in
    bash|zsh)
      printf '%s\n' "$shell_name"
      ;;
    *)
      print_error "Only Bash and Zsh are supported. Set SHELL to one of them and retry."
      return 1
      ;;
  esac
}

find_shell_config() {
  case "$1" in
    bash)
      if [ -f "${HOME}/.bashrc" ]; then
        printf '%s\n' "${HOME}/.bashrc"
      elif [ -f "${HOME}/.bash_profile" ]; then
        printf '%s\n' "${HOME}/.bash_profile"
      else
        printf '%s\n' "${HOME}/.bashrc"
      fi
      ;;
    zsh)
      printf '%s\n' "${HOME}/.zshrc"
      ;;
  esac
}

remove_config_block() {
  local config_file=$1 temp_file
  [ -f "$config_file" ] || return 0

  temp_file=$(mktemp "${config_file}.proxycli.XXXXXX") || return 1
  if ! awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v legacy="$LEGACY_MARKER" '
    $0 == begin { in_block = 1; next }
    $0 == end { in_block = 0; next }
    $0 == legacy { skip_next = 1; next }
    skip_next { skip_next = 0; next }
    !in_block { print }
  ' "$config_file" > "$temp_file" || ! cat "$temp_file" > "$config_file"; then
    rm -f "$temp_file"
    return 1
  fi
  rm -f "$temp_file"
}

configure_shell() {
  local config_file=$1

  [ -e "$config_file" ] || : > "$config_file" || return 1
  remove_config_block "$config_file" || return 1
  {
    printf '\n%s\n' "$MARKER_BEGIN"
    printf '[ -f "%s" ] && . "%s"\n' "$SOURCE_FILE" "$SOURCE_FILE"
    printf '%s\n' "$MARKER_END"
  } >> "$config_file"
}

install_proxycli() {
  local action="Installed" shell_type config_file temp_file

  command -v curl >/dev/null 2>&1 || {
    print_error "curl is required to install ${PROJECT_NAME}."
    return 1
  }
  shell_type=$(detect_shell) || return 1
  config_file=$(find_shell_config "$shell_type")
  [ -f "$SOURCE_FILE" ] && action="Updated"

  mkdir -p "${INSTALL_DIR}/src" || {
    print_error "Could not create ${INSTALL_DIR}."
    return 1
  }
  temp_file=$(mktemp "${SOURCE_FILE}.XXXXXX") || {
    print_error "Could not create a temporary download file."
    return 1
  }

  if ! curl -fSsL "${RAW_BASE_URL}/src/proxy-setup.sh" -o "$temp_file" || [ ! -s "$temp_file" ]; then
    rm -f "$temp_file"
    print_error "Download failed; no shell configuration was changed."
    return 1
  fi

  if ! bash -n "$temp_file"; then
    rm -f "$temp_file"
    print_error "The downloaded runtime script failed validation."
    return 1
  fi

  chmod +x "$temp_file" && mv "$temp_file" "$SOURCE_FILE" || {
    rm -f "$temp_file"
    print_error "Could not install the runtime script."
    return 1
  }
  configure_shell "$config_file" || {
    print_error "Installed the runtime but could not update ${config_file}."
    return 1
  }

  print_success "${action} runtime: ${SOURCE_FILE}"
  print_success "Load this version in the current shell:"
  printf '  . "%s"\n' "$SOURCE_FILE"
}

uninstall_proxycli() {
  local config_file

  for config_file in "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.zshrc"; do
    [ -f "$config_file" ] || continue
    remove_config_block "$config_file" || {
      print_error "Could not remove configuration from ${config_file}."
      return 1
    }
  done

  rm -rf "$INSTALL_DIR" "$LEGACY_INSTALL_DIR"
  print_success "Removed ProxyCli configuration and runtime files."
  print_success "Restart the shell to remove commands from the current session."
}

show_help() {
  cat <<EOF
${PROJECT_NAME} installer

Usage: bash install.sh [install|uninstall|help]

  install      Download and configure ${PROJECT_NAME} (default)
  uninstall    Remove ${PROJECT_NAME} configuration and runtime files
  help         Show this message
EOF
}

case "${1:-install}" in
  install)
    install_proxycli
    ;;
  uninstall|remove|--uninstall)
    uninstall_proxycli
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    print_error "Unknown option: $1"
    show_help >&2
    exit 2
    ;;
esac
