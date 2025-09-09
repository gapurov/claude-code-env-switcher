#!/usr/bin/env bash
# Claude environment switcher
# Usage after sourcing:
#   ccenv [--env-file <path>] [--local] <command> [args]
# Commands: list | use <name> | reload [name] | show | current | clear
#
# --local (-l) applies the change only to the current shell session and
# does not persist it to the state file used by new shells.
#
# The config (claude-code-env-sets.sh) provides:
#   - CCENV_ENV_NAMES        : list/array of available env names
#   - CCENV_MANAGED_VARS     : list/array of vars to clear on switch
#   - ccenv_globals()        : optional hook run before each env apply
#   - ccenv_apply_env <name> : required function; returns non‑zero if unknown

# ----------------------- user-tunable knobs (safe defaults) -------------------
# Default environment name when none is active
: "${CLAUDE_ENV_DEFAULT:=default}"


# Default config path: single file next to this script; overridable.
cc__script_dir() {
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

cc__default_env_file() {
  printf '%s/claude-code-env-sets.sh' "$(cc__script_dir)"
}

cc__state_file() {
  printf '%s/.claude-code-env-state' "$(cc__script_dir)"
}

cc__expand_tilde() {
  case "$1" in "~"*) printf '%s\n' "${HOME}${1#\~}";; *) printf '%s\n' "$1";; esac
}

# Resolve env file with precedence: CLI > env var > default
cc__resolve_env_file() {
  local candidate
  if [ -n "${CCENV_ENV_FILE_CLI:-}" ]; then
    candidate="$CCENV_ENV_FILE_CLI"
  elif [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    candidate="$CLAUDE_ENV_FILE"
  else
    candidate="$(cc__default_env_file)"
  fi
  candidate="$(cc__expand_tilde "$candidate")"
  printf '%s\n' "$candidate"
}

# -----------------------------------------------------------------------------


# --- helpers -----------------------------------------------------------------
cc__err() { printf 'ccenv: %s\n' "$*" >&2; return 1; }


cc__source_envfile() {
  local env_file
  env_file="$(cc__resolve_env_file)"
  if [ -r "$env_file" ]; then
    CCENV_ENV_FILE_PICKED="$env_file"
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
  fi
}

# fzf detection
cc__has_fzf() {
  command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]
}

# Interactive: list envs with fzf (view-only)
cc__interactive_list() {
  cc__source_envfile
  command -v fzf >/dev/null 2>&1 || { cc__list; return 0; }
  local lines=() n active
  active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  lines+=( "$( [ "$active" = "default" ] && printf '* ' || printf '  ' )default" )
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    [ "$n" = "default" ] && continue
    if [ "$n" = "$active" ]; then lines+=( "* $n" ); else lines+=( "  $n" ); fi
  done <<EOF
$(cc__each_envname)
EOF
  printf '%s\n' "${lines[@]}" | fzf \
    --prompt='ccenv list> ' \
    --header='Environments (active marked with *)' \
    --no-sort --height=10% --layout=default --margin=0 --border --ansi >/dev/null || true
}

# Interactive: choose env for `use` (with optional --local variants)
cc__interactive_use() {
  cc__source_envfile
  if ! cc__has_fzf; then
    cc__list
    cc__err "fzf not available for interactive selection" || true
    return 2
  fi
  local dim=$'\033[2m' normal=$'\033[0m'
  local choices=() n active sel name make_local=0
  active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  local model_disp="${ANTHROPIC_MODEL:--}"
  choices+=( "default" )
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    [ "$n" = "default" ] && continue
    choices+=( "$n" "$n --local ${dim}do not persist${normal}" )
  done <<EOF
$(cc__each_envname)
EOF
  sel=$(printf '%s\n' "${choices[@]}" | fzf \
    --prompt='ccenv use> ' \
    --header="Select environment (--local to not persist) | Active: $active | Model: $model_disp" \
    --height=10% --layout=default --margin=0 --border --ansi) || return 130
  case "$sel" in
    *' --local'*) name="${sel%% --local*}"; make_local=1 ;;
    *) name="$sel" ;;
  esac
  [ -z "$name" ] && return 0
  if [ "$make_local" -eq 1 ]; then
    CCENV_LOCAL_ONLY=1 cc__use "$name" && printf 'switched to %s (local)\n' "$name"
  else
    CCENV_LOCAL_ONLY=0 cc__use "$name" && printf 'switched to %s\n' "$name"
  fi
}

# Interactive: top-level menu
cc__interactive_root() {
  if ! cc__has_fzf; then
    cc__err "fzf not available; showing help" || true
    ccenv help
    return 0
  fi
  local dim=$'\033[2m' normal=$'\033[0m'
  local opts=(
    "use ${dim}select env${normal}"
    "list ${dim}view available envs${normal}"
    "current ${dim}print active env${normal}"
    "reload ${dim}login shell${normal}"
    'show'
    "clear ${dim}switch to default${normal}"
  ) sel
  local _active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  local _model_disp="${ANTHROPIC_MODEL:--}"
  sel=$(printf '%s\n' "${opts[@]}" | fzf \
    --prompt='ccenv> ' \
    --header="Select a command | Active: $_active | Model: $_model_disp" \
    --height=10% --layout=default --margin=0 --border --ansi) || return 130
  case "$sel" in
    list*) cc__list ;;
    use*) cc__interactive_use ;;
    current*) printf '%s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" ;;
    reload*) cc__reload ;;
    'show') cc__show ;;
    clear*) CCENV_LOCAL_ONLY=0 cc__use default ;;
    *) return 0 ;;
  esac
}

# Print a masked version of a secret value (first 4 … last 4)
cc__mask() {
  local val=$1 len=${#1} first last
  if [ "$len" -le 8 ]; then printf '%s' "$val"; return; fi
  first=${val:0:4}
  last=${val:$(($len-4)):4}
  printf '%s…%s' "$first" "$last"
}

cc__each_envname() {
  local n printed=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CCENV_ENV_NAMES 2>/dev/null || true)
    case "$decl" in
      *"typeset -a"*) eval 'for n in "${CCENV_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1 ;;
    esac
  elif [ -n "${BASH_VERSION:-}" ]; then
    local decl
    decl=$(declare -p CCENV_ENV_NAMES 2>/dev/null || true)
    case "$decl" in
      *"declare -a"*) eval 'for n in "${CCENV_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1 ;;
    esac
  fi
  if [ "$printed" -eq 0 ] && [ -n "${CCENV_ENV_NAMES:-}" ]; then
    for n in $CCENV_ENV_NAMES; do printf '%s\n' "$n"; done
  fi
}

# Clear vars declared as managed in the config.
cc__unset_managed() {
  if [ -z "${CCENV_MANAGED_VARS:-}" ]; then return 0; fi
  local v printed=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CCENV_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in
      *"typeset -a"*) eval 'for v in "${CCENV_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1 ;;
    esac
  elif [ -n "${BASH_VERSION:-}" ] ; then
    local decl
    decl=$(declare -p CCENV_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in
      *"declare -a"*) eval 'for v in "${CCENV_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1 ;;
    esac
  fi
  if [ "$printed" -eq 0 ]; then
    for v in $CCENV_MANAGED_VARS; do unset "$v"; done
  fi
}

# Save the current environment to the state file
cc__save_state() {
  local env_name="$1"
  local state_file
  state_file="$(cc__state_file)"
  printf '%s\n' "$env_name" > "$state_file"
}

# Load the saved environment from the state file
cc__load_state() {
  local state_file
  state_file="$(cc__state_file)"
  if [ -r "$state_file" ]; then
    local _s
    IFS= read -r _s < "$state_file" || true
    [ -n "${_s+x}" ] && printf '%s\n' "$_s"
  fi
}

# --- public commands ----------------------------------------------------------
cc__list() {
  cc__source_envfile
  local active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" n
  [ "$active" = "default" ] && printf '* default\n' || printf '  default\n'
  if [ -n "${CCENV_ENV_NAMES:-}" ]; then
    # show config-declared names; keep user order
    while IFS= read -r n; do
      [ -z "$n" ] && continue
      [ "$n" = "default" ] && continue
      [ "$n" = "$active" ] && printf '* %s\n' "$n" || printf '  %s\n' "$n"
    done <<EOF
$(cc__each_envname)
EOF
  fi
}

cc__use() {
  local name="$1"
  [ -z "$name" ] && { cc__err "usage: ccenv use <name>"; return 2; }

  cc__source_envfile
  cc__unset_managed

  # optional globals hook
  if command -v ccenv_globals >/dev/null 2>&1; then ccenv_globals || true; fi

  if [ "$name" != "default" ]; then
    if ! command -v ccenv_apply_env >/dev/null 2>&1; then
      cc__err "missing ccenv_apply_env in config: $(cc__resolve_env_file 2>/dev/null || printf '?')"
      return 1
    fi
    ccenv_apply_env "$name" || { cc__err "unknown env '$name' (see: ccenv list)"; return 1; }
  fi

  export CLAUDE_ENV_ACTIVE="$name"
  # Save the state for future shell invocations unless --local was used
  if [ "${CCENV_LOCAL_ONLY:-0}" != "1" ]; then
    cc__save_state "$name"
  fi
}

cc__reload() {
  [ -n "${1:-}" ] && cc__use "$1" || true
  # Exec the user's shell as a login shell so rc files are re-read.
  local shprog="${SHELL:-}"
  [ -z "$shprog" ] && shprog="$(command -v zsh 2>/dev/null || command -v bash 2>/dev/null || printf '/bin/sh')"
  exec "$shprog" -l
}

cc__show() {
  printf 'active: %s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  if [ -z "${CCENV_MANAGED_VARS:-}" ]; then
    printf '  (no CCENV_MANAGED_VARS configured)\n'
    return 0
  fi
  local v val
  # Iterate vars either as array or string
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CCENV_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in *"typeset -a"*)
    eval 'for v in "${CCENV_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cc__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0 ;;
    esac
    # no array; fall through to string fallback
  fi
  if [ -n "${BASH_VERSION:-}" ]; then
    local decl
    decl=$(declare -p CCENV_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in *"declare -a"*)
    eval 'for v in "${CCENV_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cc__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0 ;;
    esac
    # no array; fall through to string fallback
  fi
  # string fallback
  for v in ${CCENV_MANAGED_VARS}; do
    val=$(eval "printf %s \"\${$v-}\"")
    if [ -n "$val" ]; then
      case "$v" in *KEY*|*TOKEN*|*SECRET*) printf '  %s=' "$v"; cc__mask "$val"; printf '\n';;
                    *) printf '  %s=%s\n' "$v" "$val";; esac
    else
      printf '  %s=<unset>\n' "$v"
    fi
  done
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
          cc__err "missing path after $1"; return 2
        fi ;;
      --local|-l)
        CCENV_LOCAL_ONLY=1; shift ;;
      --) shift; break ;;
      -*) break ;;
      *) break ;;
    esac
  done
  # If no command and fzf is available, open interactive menu
  if [ $# -eq 0 ] && cc__has_fzf; then
    cc__interactive_root
    return $?
  fi
  local cmd="${1:-help}"; [ $# -gt 0 ] && shift
  case "$cmd" in
    list)      cc__list ;;
    use)
      if [ $# -eq 0 ] && cc__has_fzf; then
        cc__interactive_use
      else
        cc__use "$@"
      fi
      ;;
    reload)    cc__reload "$@" ;;
    show)      cc__show ;;
    current)   printf '%s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" ;;
    clear|default) cc__use default ;;
    help|-h|--help)
      cat <<'EOF'
Usage: ccenv [--env-file <path>] [--local] <command> [args]

  list                 # show available env names (from config)
  use <name>           # switch current shell to this env (persists across shells)
  reload [<name>]      # (optionally switch) then restart the shell
  show                 # print managed vars (masked for secrets)
  current              # print active env name
  clear|default        # switch to the empty default env
\nOptions:
  -e, --env-file <path>   use a specific claude-code-env-sets.sh (overrides env var)
  -l, --local             do not persist change; affects only current shell
EOF
      ;;
    *) cc__err "unknown command: $cmd (see ccenv help)"; return 1 ;;
  esac
}

# (Config is sourced on demand; avoid double-sourcing here.)


# Initialize default env once per shell
if [ -z "${CLAUDE_ENV_ACTIVE:-}" ]; then
  cc__source_envfile
  # Try to load saved state first, otherwise use default
  saved_env="$(cc__load_state)"
  if [ -n "$saved_env" ]; then
    cc__use "$saved_env" >/dev/null 2>&1 || {
      cc__unset_managed
      export CLAUDE_ENV_ACTIVE="default"
    }
  else
    cc__use "$CLAUDE_ENV_DEFAULT" >/dev/null 2>&1 || {
      cc__unset_managed
      export CLAUDE_ENV_ACTIVE="default"
    }
  fi
  unset saved_env
fi
