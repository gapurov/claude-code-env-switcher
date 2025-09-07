#!/usr/bin/env bash
# Claude environment switcher
# Usage after sourcing:
#   clsenv [--env-file <path>] [--local] <command> [args]
# Commands: list | use <name> | reload [name] | show | current | clear
#
# --local (-l) applies the change only to the current shell session and
# does not persist it to the state file used by new shells.
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

cls__state_file() {
  printf '%s/.claude-env-state' "$(cls__script_dir)"
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
cls__has_fzf() {
  command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]
}

# Interactive: list envs with fzf (view-only)
cls__interactive_list() {
  cls__source_envfile
  command -v fzf >/dev/null 2>&1 || { cls__list; return 0; }
  local lines=() n active
  active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  lines+=( "$( [ "$active" = "default" ] && printf '* ' || printf '  ' )default" )
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    [ "$n" = "default" ] && continue
    if [ "$n" = "$active" ]; then lines+=( "* $n" ); else lines+=( "  $n" ); fi
  done <<EOF
$(cls__each_envname)
EOF
  printf '%s\n' "${lines[@]}" | fzf \
    --prompt='clsenv list> ' \
    --header='Environments (active marked with *)' \
    --no-sort --height=60% --border --ansi >/dev/null || true
}

# Interactive: choose env for `use` (with optional --local variants)
cls__interactive_use() {
  cls__source_envfile
  if ! cls__has_fzf; then
    cls__list
    cls__err "fzf not available for interactive selection" || true
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
$(cls__each_envname)
EOF
  sel=$(printf '%s\n' "${choices[@]}" | fzf \
    --prompt='clsenv use> ' \
    --header=$'Select environment (pick normal or --local to not persist)\nActive: '"$active"$'  |  Model: '"$model_disp" \
    --height=60% --border --ansi) || return 130
  case "$sel" in
    *' --local'*) name="${sel%% --local*}"; make_local=1 ;;
    *) name="$sel" ;;
  esac
  [ -z "$name" ] && return 0
  if [ "$make_local" -eq 1 ]; then
    CLS_LOCAL_ONLY=1 cls__use "$name" && printf 'switched to %s (local)\n' "$name"
  else
    CLS_LOCAL_ONLY=0 cls__use "$name" && printf 'switched to %s\n' "$name"
  fi
}

# Interactive: top-level menu
cls__interactive_root() {
  if ! cls__has_fzf; then
    cls__err "fzf not available; showing help" || true
    clsenv help
    return 0
  fi
  local dim=$'\033[2m' normal=$'\033[0m'
  local opts=(
    "use ${dim}pick env${normal}"
    "list ${dim}view envs${normal}"
    "reload ${dim}login shell${normal}"
    'show'
    "clear ${dim}switch to default${normal}"
  ) sel
  local _active="${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}"
  local _model_disp="${ANTHROPIC_MODEL:--}"
  sel=$(printf '%s\n' "${opts[@]}" | fzf \
    --prompt='clsenv> ' \
    --header=$'Select a command\nActive: '"${_active}"$'  |  Model: '"${_model_disp}" \
    --height=50% --border --ansi) || return 130
  case "$sel" in
    list*) cls__list ;;
    use*) cls__interactive_use ;;
    reload*) cls__reload ;;
    'show') cls__show ;;
    clear*) CLS_LOCAL_ONLY=0 cls__use default ;;
    *) return 0 ;;
  esac
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
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CLS_ENV_NAMES 2>/dev/null || true)
    case "$decl" in
      *"typeset -a"*) eval 'for n in "${CLS_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1 ;;
    esac
  elif [ -n "${BASH_VERSION:-}" ]; then
    local decl
    decl=$(declare -p CLS_ENV_NAMES 2>/dev/null || true)
    case "$decl" in
      *"declare -a"*) eval 'for n in "${CLS_ENV_NAMES[@]}"; do printf "%s\n" "$n"; done'; printed=1 ;;
    esac
  fi
  if [ "$printed" -eq 0 ] && [ -n "${CLS_ENV_NAMES:-}" ]; then
    for n in $CLS_ENV_NAMES; do printf '%s\n' "$n"; done
  fi
}

# Clear vars declared as managed in the config.
cls__unset_managed() {
  [ -z "${CLS_MANAGED_VARS:-}" ] && return 0
  local v printed=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CLS_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in
      *"typeset -a"*) eval 'for v in "${CLS_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1 ;;
    esac
  elif [ -n "${BASH_VERSION:-}" ] ; then
    local decl
    decl=$(declare -p CLS_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in
      *"declare -a"*) eval 'for v in "${CLS_MANAGED_VARS[@]}"; do unset "$v"; done'; printed=1 ;;
    esac
  fi
  if [ "$printed" -eq 0 ]; then
    for v in $CLS_MANAGED_VARS; do unset "$v"; done
  fi
}

# Save the current environment to the state file
cls__save_state() {
  local env_name="$1"
  local state_file
  state_file="$(cls__state_file)"
  printf '%s\n' "$env_name" > "$state_file"
}

# Load the saved environment from the state file
cls__load_state() {
  local state_file
  state_file="$(cls__state_file)"
  if [ -r "$state_file" ]; then
    local _s
    IFS= read -r _s < "$state_file" || true
    [ -n "${_s+x}" ] && printf '%s\n' "$_s"
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
  # Save the state for future shell invocations unless --local was used
  if [ "${CLS_LOCAL_ONLY:-0}" != "1" ]; then
    cls__save_state "$name"
  fi
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
  if [ -n "${ZSH_VERSION:-}" ]; then
    local decl
    decl=$(typeset -p CLS_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in *"typeset -a"*)
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cls__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0 ;;
    esac
  fi
  if [ -n "${BASH_VERSION:-}" ]; then
    local decl
    decl=$(declare -p CLS_MANAGED_VARS 2>/dev/null || true)
    case "$decl" in *"declare -a"*)
    eval 'for v in "${CLS_MANAGED_VARS[@]}"; do
      val=$(eval "printf %s \"\${$v-}\"")
      if [ -n "$val" ]; then
        case "$v" in *KEY*|*TOKEN*|*SECRET*) printf "  %s=" "$v"; cls__mask "$val"; printf "\n";;
                      *) printf "  %s=%s\n" "$v" "$val";; esac
      else printf "  %s=<unset>\n" "$v"; fi
    done'
    return 0 ;;
    esac
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
  CLS_LOCAL_ONLY=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --env-file=*) CLS_ENV_FILE_CLI="${1#*=}"; export CLAUDE_ENV_FILE="$CLS_ENV_FILE_CLI"; shift ;;
      --env-file|-e)
        if [ -n "${2:-}" ]; then
          CLS_ENV_FILE_CLI="$2"; export CLAUDE_ENV_FILE="$CLS_ENV_FILE_CLI"; shift 2
        else
          cls__err "missing path after $1"; return 2
        fi ;;
      --local|-l)
        CLS_LOCAL_ONLY=1; shift ;;
      --) shift; break ;;
      -*) break ;;
      *) break ;;
    esac
  done
  # If no command and fzf is available, open interactive menu
  if [ $# -eq 0 ] && cls__has_fzf; then
    cls__interactive_root
    return $?
  fi
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    list)      cls__list ;;
    use)
      if [ $# -eq 0 ] && cls__has_fzf; then
        cls__interactive_use
      else
        cls__use "$@"
      fi
      ;;
    reload)    cls__reload "$@" ;;
    show)      cls__show ;;
    current)   printf '%s\n' "${CLAUDE_ENV_ACTIVE:-$CLAUDE_ENV_DEFAULT}" ;;
    clear|default) cls__use default ;;
    help|-h|--help)
      cat <<'EOF'
Usage: clsenv [--env-file <path>] [--local] <command> [args]

  list                 # show available env names (from config)
  use <name>           # switch current shell to this env (persists across shells)
  reload [<name>]      # (optionally switch) then restart the shell
  show                 # print managed vars (masked for secrets)
  current              # print active env name
  clear|default        # switch to the empty default env
\nOptions:
  -e, --env-file <path>   use a specific claude-env-sets.sh (overrides env var)
  -l, --local             do not persist change; affects only current shell
EOF
      ;;
    *) cls__err "unknown command: $cmd (see clsenv help)"; return 1 ;;
  esac
}

# (Config is sourced on demand; avoid double-sourcing here.)

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
  # Try to load saved state first, otherwise use default
  saved_env="$(cls__load_state)"
  if [ -n "$saved_env" ]; then
    cls__use "$saved_env" >/dev/null 2>&1 || {
      cls__unset_managed
      export CLAUDE_ENV_ACTIVE="default"
    }
  else
    cls__use "$CLAUDE_ENV_DEFAULT" >/dev/null 2>&1 || {
      cls__unset_managed
      export CLAUDE_ENV_ACTIVE="default"
    }
  fi
  unset saved_env
fi
