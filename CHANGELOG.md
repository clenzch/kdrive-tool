# Changelog

## [0.1.0] - 2026-10-12
First version.

- `install`: download the latest kDrive (SHA-256 checked against Infomaniak's published checksum, AppImage
  header and CPU architecture checked), or copy a local AppImage with `--from`. Installs to the fixed path
  `~/.local/opt/kdrive/kDrive.AppImage`, installs the tool to `~/.local/bin` and adds an **Update kDrive**
  app entry.
- `update` / `rollback`: swap in place, keeping one previous version. Config backup before every swap (last 3).
  Restart by asking you to quit kDrive from the tray (no signals). An up-to-date `update` offers to start kDrive
  if it isn't running.
- `status` / `doctor`: read-only checks with colored `ok`/`info`/`warn`/`FAIL` marks, including where kDrive
  runs from, where its entries point, prerequisites, and leftovers from manual installs.
- `system`: sudo setup that asks before each step: libfuse2 and gnome-keyring, AppArmor userns profile,
  inotify limit.
- `uninstall`: removes only the tool's own files and system additions. Keeps config backups.
- Safety: every deletion goes through one allowlist (`safe_rm`). Sync folders, kDrive config and the keyring
  are never written. Covered by bats tests in a sandboxed `$HOME`.
