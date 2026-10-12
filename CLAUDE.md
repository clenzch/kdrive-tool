# kdrive-tool: project conventions

- **Runtime is one file:** `./kdrive-tool` (bash). No helper scripts, template files or extra
  runtime deps. Embed generated files as heredocs. JSON: `jq` if present, else `python3`.
- **Hard safety rule:** the script may only write/delete its own files (`is_allowed` in `kdrive-tool`,
  listed in docs/DESIGN.md). All deletions go through `safe_rm`. Never touch sync folders,
  `~/.config/kDrive`, `~/.config/com.infomaniak.drive.desktopclient`, or credentials. Never send signals
  to kDrive. Don't open kDrive's SQLite files directly (even read-only creates `-wal`/`-shm`).
- **No automatic legacy cleanup:** `status`/`doctor` may *list* old files, never remove them.
- **Children must not inherit the lock:** anything long-lived started by a mutating command gets `9>&-`.
- **Tests never touch the real machine:** bats tests run with a sandboxed `$HOME` and sysroot
  (`tests/helpers.bash`) and PATH stubs in `tests/stubs/` for curl, pgrep, sudo, etc. No real network in tests.
- Style: tabs, `shfmt` defaults, `set -euo pipefail`, functions `cmd_<name>` for subcommands.
- Before committing: `make check` (shellcheck + shfmt + bats) must pass. One logical change per commit.
- Design and verified kDrive facts: docs/DESIGN.md. Manual migration checklist: docs/migration.md.
