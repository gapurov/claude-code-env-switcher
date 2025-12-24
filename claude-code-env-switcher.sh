#!/usr/bin/env bash
# Claude environment switcher
# Version: 2.0.0
# Usage after sourcing:
#   ccenv [--env-file <path>] [--local] <command> [args]
# Commands: list | use <name> | reload [name] | show | current | clear
#
# --local (-l) applies the change only to the current shell session and
# does not persist it to the state file used by new shells.
#
# The config (claude-code-env-config.sh) provides:
#   - CCENV_ENV_NAMES        : list/array of available env names (optional)
#   - CCENV_MANAGED_VARS     : list/array of vars to clear on switch
#   - ccenv_globals()        : optional hook run before each env apply
#   - ccenv_apply_env <name> : required function; returns non-zero if unknown
# If CCENV_ENV_NAMES is not set, names are auto-discovered from .env.* files
# in CCENV_ENV_DIR or alongside the config file.

# ----------------------- user-tunable knobs (safe defaults) -------------------
# Script version (exposed via `ccenv version`)
CCENV_VERSION="2.0.0"

# Default environment name when none is active
: "${CLAUDE_ENV_DEFAULT:=default}"


# Default config path: single file next to this script; overridable.
CCENV__SCRIPT_DIR=""

ccenv__script_dir() {
  if [ -n "${CCENV__SCRIPT_DIR:-}" ]; then
    printf '%s\n' "$CCENV__SCRIPT_DIR"
    return 0
  fi

  local src=""
  if [ -n "${BASH_VERSION:-}" ] && [ -n "${BASH_SOURCE[0]+x}" ]; then
    src="${BASH_SOURCE[0]}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    eval 'src=${funcfiletrace[1]%:*}' 2>/dev/null || src=""
    [ -z "$src" ] && eval 'src=${(%):-%N}'
  else
    src="$0"
  fi
  case "$src" in "~"*) src="${HOME}${src#\~}";; esac
  CCENV__SCRIPT_DIR="$(cd -P -- "$(dirname -- "$src")" 2>/dev/null && pwd)"
  printf '%s\n' "$CCENV__SCRIPT_DIR"
}

ccenv__default_env_file() {
  printf '%s/claude-code-env-config.sh' "$(ccenv__script_dir)"
}

ccenv__state_file() {
  printf '%s/.claude-code-env-global-active' "$(ccenv__script_dir)"
}

ccenv__expand_tilde() {
  case "$1" in "~"*) printf '%s\n' "${HOME}${1#\~}";; *) printf '%s\n' "$1";; esac
}

# Resolve env file with precedence: CLI > env var > default
ccenv__resolve_env_file() {
  local candidate
  if [ -n "${CCENV_ENV_FILE_CLI:-}" ]; then
    candidate="$CCENV_ENV_FILE_CLI"
  elif [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    candidate="$CLAUDE_ENV_FILE"
  else
    candidate="$(ccenv__default_env_file)"
  fi
  candidate="$(ccenv__expand_tilde "$candidate")"
  printf '%s\n' "$candidate"
}

ccenv__global_env_dir() {
  local env_directory="" env_file=""
  if [ -n "${CCENV_ENV_DIR:-}" ]; then
    env_directory="$(ccenv__expand_tilde "$CCENV_ENV_DIR")"
  else
    env_file="${CCENV_ENV_FILE_PICKED:-}"
    [ -z "$env_file" ] && env_file="$(ccenv__resolve_env_file 2>/dev/null || true)"
    if [ -n "$env_file" ]; then
      env_directory="$(cd -P -- "$(dirname -- "$env_file")" 2>/dev/null && pwd)"
    fi
  fi
  [ -n "$env_directory" ] && [ -d "$env_directory" ] && printf '%s\n' "$env_directory"
}

ccenv__list_env_files() {
  local env_directory="$1"
  [ -z "$env_directory" ] && return 0
  if command -v fd >/dev/null 2>&1; then
    fd -H -I -t f -g '.env.*' -E '*.example' -d 1 "$env_directory" -x basename -a {} 2>/dev/null | LC_ALL=C sort
  else
    find "$env_directory" -maxdepth 1 -type f -name '.env.*' ! -name '*.example' -print 2>/dev/null | sed 's#.*/##' | LC_ALL=C sort
  fi
}

ccenv__dir_has_env_files() {
  local env_directory="$1" found_env_file=""
  [ -z "$env_directory" ] && return 1
  if ccenv__list_env_files "$env_directory" | { read -r found_env_file; }; then
    [ -n "$found_env_file" ] && return 0
  fi
  return 1
}

ccenv__local_env_dir() {
  local env_directory=""
  env_directory="$(pwd -P 2>/dev/null || pwd)"
  if ccenv__dir_has_env_files "$env_directory"; then
    printf '%s\n' "$env_directory"
  fi
}

ccenv__env_dirs() {
  local local_env_directory global_env_directory
  local_env_directory="$(ccenv__local_env_dir 2>/dev/null || true)"
  global_env_directory="$(ccenv__global_env_dir 2>/dev/null || true)"
  [ -n "$local_env_directory" ] && printf '%s\n' "$local_env_directory"
  if [ -n "$global_env_directory" ] && [ "$global_env_directory" != "$local_env_directory" ]; then
    printf '%s\n' "$global_env_directory"
  fi
}

ccenv__env_dir_for_name() {
  local env_name="$1" local_env_directory global_env_directory
  local_env_directory="$(ccenv__local_env_dir 2>/dev/null || true)"
  if [ -n "$local_env_directory" ] && [ -r "$local_env_directory/.env.$env_name" ]; then
    printf '%s\n' "$local_env_directory"
    return 0
  fi
  global_env_directory="$(ccenv__global_env_dir 2>/dev/null || true)"
  if [ -n "$global_env_directory" ] && [ -r "$global_env_directory/.env.$env_name" ]; then
    printf '%s\n' "$global_env_directory"
    return 0
  fi
  return 1
}

ccenv__env_file_for() {
  local env_name="$1" env_directory
  env_directory="$(ccenv__env_dir_for_name "$env_name" 2>/dev/null || true)"
  [ -z "$env_directory" ] && return 1
  printf '%s/.env.%s\n' "$env_directory" "$env_name"
}

ccenv__display_name_for() {
  local env_name="$1" env_file raw_display_name trimmed_display_name
  env_file="$(ccenv__env_file_for "$env_name" 2>/dev/null || true)"
  [ -r "$env_file" ] || return 0
  raw_display_name="$(awk '
    /^[[:space:]]*(export[[:space:]]+)?CCENV_DISPLAY_NAME[[:space:]]*=/ {
      sub(/^[[:space:]]*(export[[:space:]]+)?CCENV_DISPLAY_NAME[[:space:]]*=/, "");
      print; exit
    }' "$env_file" 2>/dev/null)"
  [ -z "$raw_display_name" ] && return 0
  trimmed_display_name="${raw_display_name#"${raw_display_name%%[![:space:]]*}"}"
  trimmed_display_name="${trimmed_display_name%"${trimmed_display_name##*[![:space:]]}"}"
  case "$trimmed_display_name" in
    \"*\") trimmed_display_name="${trimmed_display_name#\"}"; trimmed_display_name="${trimmed_display_name%\"}";;
    \'*\') trimmed_display_name="${trimmed_display_name#\'}"; trimmed_display_name="${trimmed_display_name%\'}";;
  esac
  [ -n "$trimmed_display_name" ] && printf '%s\n' "$trimmed_display_name"
}

ccenv__label_for() {
  local env_name="$1" display_name
  display_name="$(ccenv__display_name_for "$env_name")"
  if [ -n "$display_name" ] && [ "$display_name" != "$env_name" ]; then
    printf '%s (%s)\n' "$display_name" "$env_name"
  else
    printf '%s\n' "$env_name"
  fi
}

CCENV__CONFIG_PATH=""
CCENV__CONFIG_MTIME=""
CCENV__CONFIG_STATUS=""
CCENV__CONFIG_LAST_ERROR=""

ccenv__file_mtime() {
  local path="$1" ts
  if [ -z "$path" ] || [ ! -e "$path" ]; then
    printf '0'
    return 0
  fi
  if ts=$(stat -f '%m' "$path" 2>/dev/null); then
    printf '%s' "$ts"
    return 0
  fi
  if ts=$(stat -c '%Y' "$path" 2>/dev/null); then
    printf '%s' "$ts"
    return 0
  fi
  printf '0'
}

ccenv__report_config_issue() {
  local msg="$1"
  if [ "$msg" != "${CCENV__CONFIG_LAST_ERROR:-}" ]; then
    CCENV__CONFIG_LAST_ERROR="$msg"
    ccenv__error "$CCENV_ERR_FILE_NOT_FOUND" "$msg"
  fi
}

# -----------------------------------------------------------------------------


# --- helpers -----------------------------------------------------------------
# Standardized error handling
readonly CCENV_ERR_UNKNOWN_CMD=1
readonly CCENV_ERR_MISSING_ARG=2
readonly CCENV_ERR_FILE_NOT_FOUND=3
readonly CCENV_ERR_INVALID_ENV=4

ccenv__error() {
  # usage: ccenv__error <code> <message>
  local code="$1"; shift
  printf 'ccenv: %s\n' "$*" >&2
  return "$code"
}

# Backward-compat shim
ccenv__err() { ccenv__error "$CCENV_ERR_UNKNOWN_CMD" "$@"; }

# Array and variable helpers with minimal eval surface
ccenv__is_array() {
  # usage: ccenv__is_array VAR_NAME
  local _n="$1" decl
  if [ -n "${BASH_VERSION:-}" ]; then
    decl=$(declare -p "$_n" 2>/dev/null || true)
    case "$decl" in *'declare -a'*|*'declare -A'*) return 0;; esac
    return 1
  elif [ -n "${ZSH_VERSION:-}" ]; then
    decl=$(typeset -p "$_n" 2>/dev/null || true)
    case "$decl" in *'typeset -a'*|*'typeset -A'*) return 0;; esac
    return 1
  fi
  return 1
}

ccenv__iterate_array() {
  # usage: ccenv__iterate_array VAR_NAME
  local _n="$1"

  if [ -n "${BASH_VERSION:-}" ] && ccenv__is_array "$_n"; then
    local bash_major="${BASH_VERSINFO[0]:-0}"
    local bash_minor="${BASH_VERSINFO[1]:-0}"
    if [ "$bash_major" -gt 4 ] || { [ "$bash_major" -eq 4 ] && [ "$bash_minor" -ge 3 ]; }; then
      local -n ccenv__arr_ref="$_n"
      for __cc_i in "${ccenv__arr_ref[@]}"; do printf '%s\n' "$__cc_i"; done
      return 0
    fi
  fi

  if [ -n "${ZSH_VERSION:-}" ] && ccenv__is_array "$_n"; then
    local -a ccenv__vals
    ccenv__vals=( "${(@P)_n[@]}" )
    local __cc_i
    for __cc_i in "${ccenv__vals[@]}"; do printf '%s\n' "$__cc_i"; done
    return 0
  fi

  eval "for __cc_i in \${$_n}; do printf '%s\\n' \"\$__cc_i\"; done"
}

ccenv__var_get() {
  # usage: ccenv__var_get VAR_NAME   -> prints value (empty if unset)
  local _n="$1"
  if [ -n "${BASH_VERSION:-}" ]; then
    printf '%s' "${!_n-}"
  elif [ -n "${ZSH_VERSION:-}" ]; then
    printf '%s' "${(P)_n-}"
  else
    eval "printf '%s' \"\${$_n-}\""
  fi
}

# UI helpers
ccenv__active_label() {
  local active_env="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  local model_disp="${ANTHROPIC_MODEL:-}"
  if [ -z "$model_disp" ] || [ "$model_disp" = "-" ]; then
    if [ "$active_env" = "default" ]; then
      model_disp='default'
    else
      model_disp='-'
    fi
  fi
  if [ "${CLAUDE_ENV_IS_LOCAL:-0}" = "1" ]; then
    printf '%s (local)' "$model_disp"
  else
    printf '%s' "$model_disp"
  fi
}

ccenv__fzf() {
  # usage: ccenv__fzf <prompt> <header> [extra fzf args]
  local _p="$1" _h="$2"
  shift 2 || true
  fzf \
    --prompt="$_p" \
    --header="$_h" \
    --height=6% --layout=default --margin=0 --border --ansi \
    "$@"
}

# Source-once cache (with mtime tracking)
CCENV__CONFIG_LOADED=0
ccenv__source_envfile_once() {
  local env_file env_file_mtime=""
  env_file="$(ccenv__resolve_env_file)" || return 1

  if [ "$env_file" != "${CCENV__CONFIG_PATH:-}" ]; then
    CCENV__CONFIG_LOADED=0
    CCENV__CONFIG_MTIME=""
    CCENV__CONFIG_LAST_ERROR=""
  elif [ "$CCENV__CONFIG_LOADED" -eq 1 ] && [ "${CCENV__CONFIG_STATUS:-}" = "ok" ]; then
    env_file_mtime="$(ccenv__file_mtime "$env_file")"
    if [ "$env_file_mtime" != "${CCENV__CONFIG_MTIME:-}" ]; then
      CCENV__CONFIG_LOADED=0
    fi
  fi

  if [ "$CCENV__CONFIG_LOADED" -eq 0 ]; then
    if ccenv__source_envfile "$env_file"; then
      CCENV__CONFIG_STATUS="ok"
      if [ -z "$env_file_mtime" ]; then
        env_file_mtime="$(ccenv__file_mtime "$env_file")"
      fi
      CCENV__CONFIG_MTIME="$env_file_mtime"
      CCENV__CONFIG_LOADED=1
    else
      CCENV__CONFIG_STATUS="error"
      CCENV__CONFIG_MTIME=""
      CCENV__CONFIG_LOADED=0
      CCENV__CONFIG_PATH="$env_file"
      return 1
    fi
    CCENV__CONFIG_PATH="$env_file"
  fi

  return 0
}

ccenv__reload_config() {
  CCENV__CONFIG_LOADED=0
  CCENV__CONFIG_MTIME=""
  CCENV__CONFIG_STATUS=""
  CCENV__CONFIG_LAST_ERROR=""
  ccenv__source_envfile_once
}


ccenv__source_envfile() {
  local env_file="$1"
  if [ -z "$env_file" ]; then
    env_file="$(ccenv__resolve_env_file)" || return 1
  fi

  if [ ! -e "$env_file" ]; then
    ccenv__report_config_issue "config file not found: $env_file"
    return $CCENV_ERR_FILE_NOT_FOUND
  fi
  if [ ! -r "$env_file" ]; then
    ccenv__report_config_issue "config file not readable: $env_file"
    return $CCENV_ERR_FILE_NOT_FOUND
  fi

  CCENV_ENV_FILE_PICKED="$env_file"
  CCENV__CONFIG_LAST_ERROR=""

  # Ensure config-declared variables/functions land in the global scope.
  # In both zsh and bash, 'typeset/declare' inside a function creates locals,
  # which would be discarded on return. Temporarily wrap to force globals.
  if [ -n "${ZSH_VERSION:-}" ]; then
    # Preserve and temporarily enable alias expansion so our 'typeset' alias
    # works, then restore the previous state to avoid altering the user's
    # shell options.
    local had_aliases=0
    if [[ -o aliases ]]; then had_aliases=1; fi
    setopt aliases 2>/dev/null || true
    alias typeset='typeset -g' 2>/dev/null || true
    # shellcheck disable=SC1090
    . "$env_file"
    unalias typeset 2>/dev/null || true
    if [ "$had_aliases" -eq 0 ]; then unsetopt aliases 2>/dev/null || true; fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    if declare -g __probe 2>/dev/null; then
      unset __probe
      typeset() { builtin declare -g "$@"; }
      # shellcheck disable=SC1090
      . "$env_file"
      unset -f typeset 2>/dev/null || true
    else
      # Older bash without -g: neutralize 'typeset' so assignments are global
      typeset() { :; }
      # shellcheck disable=SC1090
      . "$env_file"
      unset -f typeset 2>/dev/null || true
    fi
  else
    # Fallback: plain source
    # shellcheck disable=SC1090
    . "$env_file"
  fi

  return 0
}

# fzf detection
ccenv__has_fzf() {
  command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]
}

# Interactive: list envs with fzf (view-only)
ccenv__interactive_list() {
  ccenv__source_envfile_once || true
  command -v fzf >/dev/null 2>&1 || { ccenv__list; return 0; }
  local lines=() env_name active_env display_label
  active_env="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  lines+=( "$( [ "$active_env" = "default" ] && printf '* ' || printf '  ' )default" )
  while IFS= read -r env_name; do
    [ -z "$env_name" ] && continue
    [ "$env_name" = "default" ] && continue
    display_label="$(ccenv__label_for "$env_name")"
    if [ "$env_name" = "$active_env" ]; then lines+=( "* $display_label" ); else lines+=( "  $display_label" ); fi
  done <<EOF
$(ccenv__each_envname)
EOF
  printf '%s\n' "${lines[@]}" | ccenv__fzf 'ccenv list> ' 'Environments (active marked with *)' \
    --no-sort >/dev/null || true
}

# Interactive: choose env for `use` (with optional --local variants)
ccenv__interactive_use() {
  if ! ccenv__source_envfile_once; then
    return $CCENV_ERR_FILE_NOT_FOUND
  fi
  if ! ccenv__has_fzf; then
    ccenv__list
    ccenv__err "fzf not available for interactive selection" || true
    return $CCENV_ERR_MISSING_ARG
  fi
  local dim=$'\033[2m' normal=$'\033[0m'
  local sep=$'\037'
  local choices=() env_name selection selected_name make_local=0 display_label
  local header="Select environment (--local to not persist) | Active: $(ccenv__active_label)"
  choices+=( "default${sep}default" )
  while IFS= read -r env_name; do
    [ -z "$env_name" ] && continue
    [ "$env_name" = "default" ] && continue
    display_label="$(ccenv__label_for "$env_name")"
    choices+=( "${env_name}${sep}${display_label}" )
    choices+=( "${env_name}|local${sep}${display_label} --local ${dim}do not persist${normal}" )
  done <<EOF
$(ccenv__each_envname)
EOF
  selection=$(printf '%s\n' "${choices[@]}" | ccenv__fzf 'ccenv use> ' "$header" \
    --with-nth=2 --delimiter="$sep") || return 130
  local value="${selection%%$sep*}"
  [ -z "$value" ] && return 0
  case "$value" in
    *'|local') selected_name="${value%|local}"; make_local=1 ;;
    *) selected_name="$value" ;;
  esac
  [ -z "$selected_name" ] && return 0
  if [ "$make_local" -eq 1 ]; then
    CCENV_LOCAL_ONLY=1 ccenv__use "$selected_name" && printf 'switched to %s (local)\n' "$selected_name"
  else
    CCENV_LOCAL_ONLY=0 ccenv__use "$selected_name" && printf 'switched to %s\n' "$selected_name"
  fi
}

# Interactive: top-level menu
ccenv__interactive_root() {
  if ! ccenv__has_fzf; then
    ccenv__err "fzf not available; showing help" || true
    ccenv help
    return 0
  fi
  local dim=$'\033[2m' normal=$'\033[0m'
  local sep=$'\037'
  local opts=() sel
  local __active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  if [ "${__active}" != "default" ]; then
    opts+=( "clear${sep}reset to default" )
  fi
  opts+=(
    "reload${sep}reload ${dim}shell${normal}"
    "select${sep}select ${dim}claude code env${normal}"
  )
  sel=$(printf '%s\n' "${opts[@]}" | ccenv__fzf 'ccenv> ' "Active: $(ccenv__active_label)" \
    --with-nth=2 --delimiter="$sep") || return 130
  local choice="${sel%%$sep*}"
  [ -z "$choice" ] && return 0
  case "$choice" in
    reset) CCENV_LOCAL_ONLY=0 ccenv__use default ;;
    reload) ccenv__reload ;;
    select) ccenv__interactive_use ;;
    *) return 0 ;;
  esac
}

# Print a masked version of a secret value (first 4 … last 4)
ccenv__mask() {
  local val=$1 len=${#1} first last
  if [ "$len" -le 8 ]; then printf '%s' "$val"; return; fi
  first=${val:0:4}
  last=${val:$(($len-4)):4}
  printf '%s…%s' "$first" "$last"
}

ccenv__each_envname() {
  if [ -n "${CCENV_ENV_NAMES:-}" ]; then
    ccenv__iterate_array CCENV_ENV_NAMES
    return 0
  fi
  local env_directory
  {
    while IFS= read -r env_directory; do
      [ -z "$env_directory" ] && continue
      ccenv__list_env_files "$env_directory"
    done <<EOF
$(ccenv__env_dirs)
EOF
  } | awk '
    { sub(/^\.env\./, "", $0); if ($0 != "" && !seen[$0]++) print }
  '
}

ccenv__env_known() {
  local candidate="$1" env_name
  [ "$candidate" = "default" ] && return 0
  while IFS= read -r env_name; do
    [ -z "$env_name" ] && continue
    if [ "$env_name" = "$candidate" ]; then
      return 0
    fi
  done <<EOF
$(ccenv__each_envname)
EOF
  return 1
}

ccenv__validate_env_name() {
  local name="$1"
  if [ -z "$name" ]; then
    ccenv__error "$CCENV_ERR_MISSING_ARG" "usage: ccenv use <name>"
    return $CCENV_ERR_MISSING_ARG
  fi
  if [ "$name" = "default" ]; then
    return 0
  fi
  if [ "${CCENV__CONFIG_STATUS:-}" != "ok" ]; then
    ccenv__error "$CCENV_ERR_FILE_NOT_FOUND" "environment config not loaded; see --env-file"
    return $CCENV_ERR_FILE_NOT_FOUND
  fi
  if ! ccenv__env_known "$name"; then
    ccenv__error "$CCENV_ERR_INVALID_ENV" "unknown env '$name' (see: ccenv list)"
    return $CCENV_ERR_INVALID_ENV
  fi
  return 0
}

# Clear vars declared as managed in the config.
ccenv__unset_managed() {
  if [ -z "${CCENV_MANAGED_VARS:-}" ]; then return 0; fi
  local v
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    unset "$v"
  done <<EOF
$(ccenv__iterate_array CCENV_MANAGED_VARS)
EOF
}

# Save the current environment to the state file
ccenv__save_state() {
  local env_name="$1"
  local state_file
  state_file="$(ccenv__state_file)"
  (
    umask 077
    printf '%s\n' "$env_name" > "$state_file"
  )
  chmod 600 "$state_file" 2>/dev/null || true
}

# Load the saved environment from the state file
ccenv__load_state() {
  local state_file saved_env_name
  state_file="$(ccenv__state_file)"
  if [ -r "$state_file" ]; then
    IFS= read -r saved_env_name < "$state_file" || true
    [ -n "${saved_env_name+x}" ] && printf '%s\n' "$saved_env_name"
    return 0
  fi
}

# --- public commands ----------------------------------------------------------
ccenv__list() {
  local status=0
  if ! ccenv__source_envfile_once; then
    status=$CCENV_ERR_FILE_NOT_FOUND
  fi
  local active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" env_name display_label
  [ "$active" = "default" ] && printf '* default\n' || printf '  default\n'
  # show config-declared names or auto-discovered env files
  while IFS= read -r env_name; do
    [ -z "$env_name" ] && continue
    [ "$env_name" = "default" ] && continue
    display_label="$(ccenv__label_for "$env_name")"
    [ "$env_name" = "$active" ] && printf '* %s\n' "$display_label" || printf '  %s\n' "$display_label"
  done <<EOF
$(ccenv__each_envname)
EOF
  return $status
}

ccenv__use() {
  local name="$1"
  [ -z "$name" ] && { ccenv__error "$CCENV_ERR_MISSING_ARG" "usage: ccenv use <name>"; return $CCENV_ERR_MISSING_ARG; }

  if [ "$name" = "default" ]; then
    ccenv__source_envfile_once || true
  else
    if ! ccenv__source_envfile_once; then
      return $CCENV_ERR_FILE_NOT_FOUND
    fi
  fi

  if ! ccenv__validate_env_name "$name"; then
    return $?
  fi

  ccenv__unset_managed

  # optional globals hook
  if command -v ccenv_globals >/dev/null 2>&1; then ccenv_globals || true; fi

  if [ "$name" != "default" ]; then
    if ! command -v ccenv_apply_env >/dev/null 2>&1; then
      ccenv__error "$CCENV_ERR_FILE_NOT_FOUND" "missing ccenv_apply_env in config: $(ccenv__resolve_env_file 2>/dev/null || printf '?')"
      return $CCENV_ERR_FILE_NOT_FOUND
    fi
    if ! ccenv_apply_env "$name"; then
      ccenv__error "$CCENV_ERR_INVALID_ENV" "unknown env '$name' (see: ccenv list)"
      return $CCENV_ERR_INVALID_ENV
    fi
  fi

  export CLAUDE_ENV_ACTIVE="$name"
  if [ "${CCENV_LOCAL_ONLY:-0}" = "1" ]; then
    export CLAUDE_ENV_IS_LOCAL=1
  else
    export CLAUDE_ENV_IS_LOCAL=0
  fi
  # Save the state for future shell invocations unless --local was used
  if [ "${CCENV_LOCAL_ONLY:-0}" != "1" ]; then
    ccenv__save_state "$name"
  fi
}

ccenv__reload() {
  [ -n "${1:-}" ] && ccenv__use "$1" || true
  # Exec the user's shell as a login shell so rc files are re-read.
  local shprog="${SHELL:-}"
  [ -z "$shprog" ] && shprog="$(command -v zsh 2>/dev/null || command -v bash 2>/dev/null || printf '/bin/sh')"
  exec "$shprog" -l
}



ccenv__command_use() {
  if [ $# -eq 0 ] && ccenv__has_fzf; then
    ccenv__interactive_use
    return $?
  fi
  ccenv__use "$@"
}



ccenv__print_help() {
  cat <<'EOF'
Usage: ccenv [--env-file <path>] [--local] <command> [args]

  use <name>           # switch current shell to this env (persists across shells)
  reload [<name>]      # (optionally switch) then restart the shell
  reset|clear|default # switch to the empty default env
  version              # print ccenv script version
  current              # print active env name

Options:
  -e, --env-file <path>   use a specific claude-code-env-config.sh (overrides env var)
  -l, --local             do not persist change; affects only current shell
EOF
}

ccenv__dispatch() {
  local cmd="$1"
  shift || true
  case "$cmd" in
    list)      ccenv__list ;;
    use)       ccenv__command_use "$@" ;;
    reload)    ccenv__reload "$@" ;;
    reset|clear|default) ccenv__use default ;;
    version)   printf '%s\n' "${CCENV_VERSION:-dev}" ;;
    current)   printf '%s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" ;;
    help|-h|--help) ccenv__print_help ;;
    *) ccenv__error "$CCENV_ERR_UNKNOWN_CMD" "unknown command: $cmd" ;;
  esac
}

ccenv() {
  # Optional global options parsed before the command
  CCENV_LOCAL_ONLY=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-file=*) CCENV_ENV_FILE_CLI="${1#*=}"; export CLAUDE_ENV_FILE="$CCENV_ENV_FILE_CLI"; shift ;;
      --env-file|-e)
        if [ -n "${2:-}" ]; then
          CCENV_ENV_FILE_CLI="$2"; export CLAUDE_ENV_FILE="$CCENV_ENV_FILE_CLI"; shift 2
        else
          ccenv__error "$CCENV_ERR_MISSING_ARG" "missing path after $1"
          return $CCENV_ERR_MISSING_ARG
        fi ;;
      --local|-l)
        CCENV_LOCAL_ONLY=1; shift ;;
      --) shift; break ;;
      -*) break ;;
      *) break ;;
    esac
  done
  # If no command and fzf is available, open interactive menu
  if [ $# -eq 0 ] && ccenv__has_fzf; then
    ccenv__interactive_root
    return $?
  fi
  local cmd="${1:-help}"; [ $# -gt 0 ] && shift
  ccenv__dispatch "$cmd" "$@"
}

# (Config is sourced on demand; avoid double-sourcing here.)


# Initialize default env once per shell
if [ -z "${CLAUDE_ENV_ACTIVE:-}" ]; then
  ccenv__source_envfile_once || true
  saved_env="$(ccenv__load_state)"
  if [ -n "$saved_env" ] && ccenv__use "$saved_env" >/dev/null 2>&1; then
    :
  else
    if [ -n "$saved_env" ]; then
      printf 'ccenv: failed to restore saved environment "%s", falling back to default\n' "$saved_env" >&2
    fi
    if ! ccenv__use "$CLAUDE_ENV_DEFAULT" >/dev/null 2>&1; then
      printf 'ccenv: failed to apply default environment "%s"; clearing managed variables\n' "$CLAUDE_ENV_DEFAULT" >&2
      ccenv__unset_managed
      export CLAUDE_ENV_ACTIVE="default"
    fi
  fi
  unset saved_env
fi
