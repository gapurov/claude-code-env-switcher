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
: "${CLAUDE_ENV_DEFAULT:=default}"        # startup env
: "${CLAUDE_CLI_BIN:=claude}"             # the actual CLI to run
: "${CLAUDE_SHORTCUT:=cls}"               # set "" to disable the shortcut
# CLAUDE_ENV_FILE may be an array (preferred) or a space-separated string.
# First existing file wins. If unset, we’ll look at ./claude-env-sets.sh
: "${CLAUDE_ENV_FILE:=./claude-env-sets.sh}"
# -----------------------------------------------------------------------------


# --- helpers -----------------------------------------------------------------
cls__err() { printf 'clsenv: %s\n' "$*" >&2; return 1; }

# Iterate over values of CLAUDE_ENV_FILE supporting zsh/bash arrays or strings.
cls__each_envfile() {
  local printed=0 f
  if [ -n "${ZSH_VERSION:-}" ]; then
    if typeset -p CLAUDE_ENV_FILE 2>/dev/null | grep -q 'typeset -a'; then
      # zsh array
      eval 'for f in "${CLAUDE_ENV_FILE[@]}"; do printf "%s\n" "$f"; done'
      printed=1
    fi
  fi
  if [ "$printed" -eq 0 ] && [ -n "${BASH_VERSION:-}" ]; then
    if declare -p CLAUDE_ENV_FILE 2>/dev/null | grep -q 'declare \-a'; then
      # bash array
      eval 'for f in "${CLAUDE_ENV_FILE[@]}"; do printf "%s\n" "$f"; done'
      printed=1
    fi
  fi
  if [ "$printed" -eq 0 ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    # whitespace-separated fallback
    for f in $CLAUDE_ENV_FILE; do printf "%s\n" "$f"; done
  fi
}

# Pick first existing config path; memoize as CLS_ENV_FILE_PICKED.
cls__pick_envfile() {
  if [ -n "${CLS_ENV_FILE_PICKED:-}" ] && [ -f "$CLS_ENV_FILE_PICKED" ]; then
    printf '%s' "$CLS_ENV_FILE_PICKED"; return 0
  fi
  local f
  # candidates: user-provided list, then the default
  while IFS= read -r f; do
    case "$f" in "~"*) f="${HOME}${f#\~}";; esac
    [ -f "$f" ] || continue
    CLS_ENV_FILE_PICKED="$f"
    printf '%s' "$f"
    return 0
  done <<EOF
$(cls__each_envfile)
$HOME/.claude/claude-env-sets.sh
EOF
  return 1
}

cls__source_envfile() {
  if cls__pick_envfile >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    . "$CLS_ENV_FILE_PICKED"
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
      cls__err "missing cls_apply_env in config: $(cls__pick_envfile 2>/dev/null || printf '?')"
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
Usage: clsenv <command> [args]

  list                 # show available env names (from config)
  use <name>           # switch current shell to this env
  reload [<name>]      # (optionally switch) then restart the shell
  show                 # print managed vars (masked for secrets)
  current              # print active env name
  clear|default        # switch to the empty default env
EOF
      ;;
    *) cls__err "unknown command: $cmd (see clsenv help)"; return 1 ;;
  esac
}

# Optional CLI shortcut: 'cls' → $CLAUDE_CLI_BIN
cls__maybe_shortcut() {
  [ -z "$CLAUDE_SHORTCUT" ] && return 0
  if command -v "$CLAUDE_SHORTCUT" >/dev/null 2>&1; then return 0; fi
  eval "${CLAUDE_SHORTCUT}(){ command \"${CLAUDE_CLI_BIN}\" \"\$@\"; }"
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
