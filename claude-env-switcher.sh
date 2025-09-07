#!/usr/bin/env bash
# Claude environment switcher
# Usage after sourcing:  clsenv list|use <name>|reload [name]|show|current|clear
#
# The config (claude-env-sets.sh) provides:
#   - CLS_ENV_NAMES          : list/array of available env names
#   - CLS_MANAGED_VARS       : list/array of vars to clear on switch
#   - cls_env_globals()      : optional hook run before each env apply
#   - cls_apply_env <name>   : required function; returns non‑zero if unknown

# ----------------------- user-tunable knobs (safe defaults) -------------------
# Default environment name when none is active
: "${CLAUDE_ENV_DEFAULT:=default}"

# Shortcut function name to run your CLI (calls 'claude')
: "${CLAUDE_SHORTCUT:=cls}"

# Default config path: single file next to this script; overridable.
cls__script_dir() {
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
  printf '%s\n' "$(cd -P -- "$(dirname -- "$src")" 2>/dev/null && pwd)"
}

cls__default_env_file() {
  printf '%s/claude-env-sets.sh' "$(cls__script_dir)"
}

cls__expand_tilde() {
  case "$1" in "~"*) printf '%s\n' "${HOME}${1#\~}";; *) printf '%s\n' "$1";; esac
}

# Resolve env file with precedence: CLI > env var > default
cls__resolve_env_file() {
  local candidate
  if [ -n "${CLS_ENV_FILE_CLI:-}" ]; then
    candidate="$CLS_ENV_FILE_CLI"
  elif [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    candidate="$CLAUDE_ENV_FILE"
  else
    candidate="$(cls__default_env_file)"
  fi
  candidate="$(cls__expand_tilde "$candidate")"
  printf '%s\n' "$candidate"
}

# -----------------------------------------------------------------------------


# --- helpers -----------------------------------------------------------------
cls__err() { printf 'clsenv: %s\n' "$*" >&2; return 1; }


cls__source_envfile() {
  local env_file
  env_file="$(cls__resolve_env_file)"
  if [ -r "$env_file" ]; then
    CLS_ENV_FILE_PICKED="$env_file"
    # Ensure config-declared variables/functions land in the global scope.
    # In both zsh and bash, 'typeset/declare' inside a function creates locals,
    # which would be discarded on return. Temporarily wrap to force globals.
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt aliases 2>/dev/null || true
      alias typeset='typeset -g' 2>/dev/null || true
      # shellcheck disable=SC1090
      . "$env_file"
      unalias typeset 2>/dev/null || true
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
  fi
}

# Print a masked version of a secret value (first 4 … last 4)
cls__mask() {
  local val=$1 len=${#1} first last
  if [ "$len" -le 8 ]; then printf '%s' "$val"; return; fi
  first=${val:0:4}
  last=${val:$(($len-4)):4}
  printf '%s…%s' "$first" "$last"
}

# Iterate over CLS_ENV_NAMES (array or string) yielding one name per line
cls__each_envname() {
  local n printed=0
  if [ -n "${ZSH_VERSION:-}" ] && typeset -p CLS_ENV_NAMES 2>/dev/null | grep -q 'typeset -a'; then
    eval 'for n in "${CLS_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1
  elif [ -n "${BASH_VERSION:-}" ] && declare -p CLS_ENV_NAMES 2>/dev/null | grep -q 'declare \-a'; then
    eval 'for n in "${CLS_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1
  fi
  if [ "$printed" -eq 0 ] && [ -n "${CLS_ENV_NAMES:-}" ]; then
    for n in $CLS_ENV_NAMES; do printf '%s\n' "$n"; done
  fi
}

# Clear vars declared as managed in the config.
cls__unset_managed() {
  [ -z "${CLS_MANAGED_VARS:-}" ] && return 0
  local v printed=0
  if [ -n "${ZSH_VERSION:-}" ] && typeset -p CLS_MANAGED_VARS 2>/dev/null | grep -q 'typeset -a'; then
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1
  elif [ -n "${BASH_VERSION:-}" ] && declare -p CLS_MANAGED_VARS 2>/dev/null | grep -q 'declare \-a'; then
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1
  fi
  if [ "$printed" -eq 0 ]; then
    for v in $CLS_MANAGED_VARS; do unset "$v"; done
  fi
}

# --- public commands ----------------------------------------------------------
cls__list() {
  cls__source_envfile
  local active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" n
  [ "$active" = "default" ] && printf '* default\n' || printf '  default\n'
  if [ -n "${CLS_ENV_NAMES:-}" ]; then
    # show config-declared names; keep user order
    while IFS= read -r n; do
      [ -z "$n" ] && continue
      [ "$n" = "default" ] && continue
      [ "$n" = "$active" ] && printf '* %s\n' "$n" || printf '  %s\n' "$n"
    done <<EOF
$(cls__each_envname)
EOF
  fi
}

cls__use() {
  local name="$1"
  [ -z "$name" ] && { cls__err "usage: clsenv use <name>"; return 2; }

  cls__source_envfile
  cls__unset_managed

  # optional globals hook
  if command -v cls_env_globals >/dev/null 2>&1; then cls_env_globals || true; fi

  if [ "$name" != "default" ]; then
    if ! command -v cls_apply_env >/dev/null 2>&1; then
      cls__err "missing cls_apply_env in config: $(cls__resolve_env_file 2>/dev/null || printf '?')"
      return 1
    fi
    if ! cls_apply_env "$name"; then
      cls__err "unknown env '$name' (see: clsenv list)"
      return 1
    fi
  fi

  export CLAUDE_ENV_ACTIVE="$name"
}

cls__reload() {
  [ -n "${1:-}" ] && cls__use "$1" || true
  # Exec the user's shell as a login shell so rc files are re-read.
  local shprog="${SHELL:-}"
  [ -z "$shprog" ] && shprog="$(command -v zsh 2>/dev/null || command -v bash 2>/dev/null || printf '/bin/sh')"
  exec "$shprog" -l
}

cls__show() {
  printf 'active: %s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  if [ -z "${CLS_MANAGED_VARS:-}" ]; then
    printf '  (no CLS_MANAGED_VARS configured)\n'
    return 0
  fi
  local v val
  # Iterate vars either as array or string
  if [ -n "${ZSH_VERSION:-}" ] && typeset -p CLS_MANAGED_VARS 2>/dev/null | grep -q 'typeset -a'; then
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cls__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0
  fi
  if [ -n "${BASH_VERSION:-}" ] && declare -p CLS_MANAGED_VARS 2>/dev/null | grep -q 'declare \-a'; then
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cls__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0
  fi
  # string fallback
  for v in $CLS_MANAGED_VARS; do
    val=$(eval "printf %s \"\${$v-}\"")
    if [ -n "$val" ]; then
      case "$v" in *KEY*|*TOKEN*|*SECRET*) printf '  %s=' "$v"; cls__mask "$val"; printf '\n';;
                    *) printf '  %s=%s\n' "$v" "$val";; esac
    else
      printf '  %s=<unset>\n' "$v"
    fi
  done
}

clsenv() {
  # Optional global options parsed before the command
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-file=*) CLS_ENV_FILE_CLI="${1#*=}"; export CLAUDE_ENV_FILE="$CLS_ENV_FILE_CLI"; shift ;;
      --env-file|-e)
        if [ -n "${2:-}" ]; then
          CLS_ENV_FILE_CLI="$2"; export CLAUDE_ENV_FILE="$CLS_ENV_FILE_CLI"; shift 2
        else
          cls__err "missing path after $1"; return 2
        fi ;;
      --) shift; break ;;
      -*) break ;;
      *) break ;;
    esac
  done
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    list)      cls__list ;;
    use)       cls__use "$@" ;;
    reload)    cls__reload "$@" ;;
    show)      cls__show ;;
    current)   printf '%s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" ;;
    clear|default) cls__use default ;;
    help|-h|--help)
      cat <<'EOF'
Usage: clsenv [--env-file <path>] <command> [args]

  list                 # show available env names (from config)
  use <name>           # switch current shell to this env
  reload [<name>]      # (optionally switch) then restart the shell
  show                 # print managed vars (masked for secrets)
  current              # print active env name
  clear|default        # switch to the empty default env
\nOptions:
  -e, --env-file <path>   use a specific claude-env-sets.sh (overrides env var)
EOF
      ;;
    *) cls__err "unknown command: $cmd (see clsenv help)"; return 1 ;;
  esac
}

# Preload the config once at top level so arrays/functions declared with
# 'typeset' become global in shells that lack 'declare -g' (e.g., bash 3.2).
if [ -z "${CLS_ENV_FILE_PICKED:-}" ]; then
  env_file_preload="$(cls__resolve_env_file)"
  if [ -r "$env_file_preload" ]; then
    CLS_ENV_FILE_PICKED="$env_file_preload"
    # shellcheck disable=SC1090
    . "$env_file_preload"
  fi
fi

# Optional CLI shortcut: 'cls' → claude
cls__maybe_shortcut() {
  # Create a convenience shortcut to the 'claude' CLI if requested.
  local shortcut="${CLAUDE_SHORTCUT:-cls}"
  [ -n "$shortcut" ] || return 0
  if command -v "$shortcut" >/dev/null 2>&1; then return 0; fi
  eval "${shortcut}(){ command claude \"\$@\"; }"
}
cls__maybe_shortcut

# Initialize default env once per shell
if [ -z "${CLAUDE_ENV_ACTIVE:-}" ]; then
  cls__source_envfile
  cls__use "$CLAUDE_ENV_DEFAULT" >/dev/null 2>&1 || {
    cls__unset_managed
    export CLAUDE_ENV_ACTIVE="default"
  }
fi
