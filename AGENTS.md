- NEVER comment unless absolutely necessary.
- MUST: Use descriptive names for variables (avoid shorthands, or 1-2 character names).
- MUST: Remove unused code and don't repeat yourself.
- MUST: Always find, think, then implement the most _elegant_ solution.

## Git commits

- **Never commit unless explicitly asked**.
- When asked, use **Conventional Commits** and **mirror the style of recent commits**
- Prefer: `type(scope): imperative summary`.
- Keep messages short and specific.

## Tool Selection (Shell)

When you need to call tools from the shell, use this rubric:

- Find files by file name: `fd`
- Find files with path name: `fd -p <file-path>`
- List files in a directory: `fd . <directory>`
- Find files with extension and pattern: `fd -e <extension> <pattern>`
- Find text: `rg` (ripgrep)
- Structured code search: `ast-grep`
  - Default to TypeScript:
    - `.ts` → `ast-grep --lang ts -p '<pattern>'`
    - `.tsx` (React) → `ast-grep --lang tsx -p '<pattern>'`
  - Common languages:
    - Bash → `ast-grep --lang bash -p '<pattern>'`
    - Python → `ast-grep --lang python -p '<pattern>'`
    - TypeScript → `ast-grep --lang ts -p '<pattern>'`
    - TSX (React) → `ast-grep --lang tsx -p '<pattern>'`
    - JavaScript → `ast-grep --lang js -p '<pattern>'`
    - Rust → `ast-grep --lang rust -p '<pattern>'`
    - JSON → `ast-grep --lang json -p '<pattern>'`
  - For other languages, set `--lang` appropriately.
- Select among matches: pipe to `fzf`
- JSON: `jq`
- YAML/XML: `yq`

If `ast-grep` is available, avoid `rg` or `grep` unless a plain-text search is explicitly requested.

---

## Bash / Shell

Default to Bash. For `.sh` files or scripts with a `bash` shebang, assume Bash; for pure POSIX `sh`, adjust flags accordingly.

- Lint (static analysis): `shellcheck`

  - Single file (follow sourced files): `shellcheck -x path/to/script.sh`
  - Many by extension: `fd -e sh -e bash -t f | xargs -r shellcheck -x`
  - Many by shebang: `rg -l '^\s*#!.*\b(bash|sh)\b' | fzf -m | xargs -r shellcheck -x`
  - Severity: `-S warning` or `-S style`
  - Exclude rules sparingly: `-e SC1091,SC2086` (prefer file-local disables: `# shellcheck disable=SC2086`)

- Format: `shfmt`

  - Check (diff only): `shfmt -d -i 2 -ci -sr .`
  - Write changes: `shfmt -w -i 2 -ci -sr .`
  - Bash dialect when needed: `shfmt -ln=bash -w -i 2 -ci -sr .`

- Test: `bats` (Bats-core)
  - Run all tests: `bats -r test/`
  - Pick a test via fzf: `fd -e bats test | fzf | xargs -r bats`
  - Minimal test template:
    ```bash
    # test/my_script.bats
    @test "prints help" {
      run ./my_script.sh -h
      [ "$status" -eq 0 ]
      [[ "$output" == *"Usage:"* ]]
    }
    ```

### CI one-liners

- Lint: `fd -e sh -e bash -t f | xargs -r shellcheck -S warning -x`
- Format check: `shfmt -d -i 2 -ci -sr .`
- Tests: `bats -r test/`
