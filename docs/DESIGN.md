# Design notes

Why `kdrive-tool` works the way it does, and the facts about kDrive it relies on. They were checked
against kDrive 3.8.7.1 and 3.8.8.1 on Ubuntu 26.04 and against the
[kDrive source](https://github.com/Infomaniak/desktop-kDrive). If kDrive changes, start here.

## Goals
- One self-contained file. No helper scripts, templates or runtime dependencies beyond what Ubuntu ships.
  Generated files are heredocs. JSON is parsed with `jq` if present, else `python3`.
- Install, update and roll back kDrive. Bring a second machine to the same setup by copying one file.
- Never risk synced data (see [Safety](#safety)).

## Facts about kDrive
- **Releases:** `https://www.infomaniak.com/drive/latest` returns JSON with `linux-amd64` and `linux-arm64`
  entries (`version`, `downloadurl`). Every AppImage has a `<downloadurl>.sha256` next to it
  (`<hex>  <filename>`).
- **kDrive rewrites its desktop entries on every start:** `~/.local/share/applications/kDrive.desktop`
  (with the `kdrive://` handler) and, if autostart is enabled, `~/.config/autostart/kDrive.desktop`.
  Both get `Exec=` set to the AppImage path it was started from. Wrappers and symlinks get overwritten.
- **kDrive's own updater on Linux only notifies** ("manual update available"). It never replaces the binary.
- **No graceful quit from a script:** the binary has no `--quit` option. The server's SIGTERM handler is
  commented out upstream ("interferes with Sentry"), so SIGTERM would kill it mid-sync. The only graceful quit
  is the tray menu.
- **Process layout:** the AppImage runtime (holds the squashfs mount), `AppRun.wrapped` (the sync server) and
  `kDrive_client` (GUI, started by the server). The client's environment has `APPIMAGE=<path>`, which tells
  which file kDrive was started from.
- **State:** accounts and sync databases in `~/.config/kDrive/` (`.parms.db`, `.sync_*.db`, SQLite in WAL mode).
  Client settings are in `~/.config/com.infomaniak.drive.desktopclient/`. kDrive upgrades `.parms.db`
  when a newer version starts, so an older binary may not read it cleanly afterwards.
- **Ubuntu 24.04+** sets `kernel.apparmor_restrict_unprivileged_userns=1`. kDrive's embedded browser
  (login window) needs user namespaces, hence the AppArmor profile.

## Fixed path
The AppImage always lives at `~/.local/opt/kdrive/kDrive.AppImage`, with `kDrive.AppImage.prev` and the
`VERSION` / `VERSION.prev` files next to it. Because the path never changes, kDrive's own entry rewrites,
autostart and the AppArmor profile stay valid across updates. The tool never writes kDrive's entries:
they are outside its allowlist, and kDrive creates them on first start.

**Swapping without a gap:** the new file is downloaded to `kDrive.AppImage.new` and verified. The current
file is hard-linked to `.prev`, then `.new` is renamed over the active path. The active path is never missing,
and a running kDrive keeps its open inode. `rollback` does the same in reverse via a `.swap` hard link. A swap
interrupted between renames is completed or undone on the next run.

## Verification
HTTPS only, also on redirects (`--proto =https --proto-redir =https`). The download host must be exactly
`download.storage.infomaniak.com`, with a plain path ending in `.AppImage`. Versions must look like `a.b.c.d`.
The SHA-256 must match the published `.sha256`. This checks integrity, not authenticity, since the checksum
comes from the same origin. The file must be an ELF with the AppImage type-2 magic (`AI\x02` at offset 8)
and the right `e_machine` for the CPU, and at least 1 MB. `install --from` copies a local file, and checks
it against the published checksum for its version when reachable. No downgrade without `--force`.

## Restarting kDrive
Since kDrive can't be quit from a script, `update` and `rollback` ask the user to quit it from the tray
menu, poll until it has exited (10 minutes at most), and start the new version detached (`setsid -f`).
The tool never sends a signal (a test greps for `kill`). Started kDrive processes must not inherit the
lock file descriptor, or they would hold the lock for their whole lifetime.

## Config backup
Before every swap, kDrive's DBs and client settings are copied to
`~/.local/state/kdrive-tool/backup/<timestamp>/`, and the newest 3 are kept. The originals are only read
with `cp`: opening them with SQLite, even `mode=ro`, creates `-wal`/`-shm` files next to them when kDrive
isn't running. SQLite then runs on the copy (`quick_check`, fold the WAL in). A copy torn by a concurrent
write is kept raw and flagged.

## Safety
- The tool only writes inside `~/.local/opt/kdrive/` and `~/.local/state/kdrive-tool/`, plus its own
  `~/.local/bin/kdrive-tool`, `kdrive-tool.desktop` and `kdrive-tool.png`, and via `system`
  `/etc/apparmor.d/kdrive-tool` and `/etc/sysctl.d/60-kdrive-inotify.conf`.
- Every deletion goes through `safe_rm`. It resolves the parent directory's symlinks, refuses anything outside
  the allowlist, and always refuses `$HOME`, `/`, kDrive's config, keyring and cache folders, and their
  ancestors. `safe_rm --sudo` removes only the two `/etc` files, never directories.
- No automatic cleanup of old installs. `status` lists leftovers, and the user removes them.
- One mutating command at a time (`flock`). `status` and `doctor` take no lock and write nothing,
  not even the log.

## Testing
bats tests run with a throwaway `$HOME`, a fake `/etc` and `/proc/sys` (`KDRIVE_SYSROOT`), and stubs in
`tests/stubs/`. `curl` serves files from a fake mirror, and `sudo` never runs anything as root.
Test-only environment variables: `KDRIVE_DIR`, `KDRIVE_STATE_DIR`, `KDRIVE_LATEST_URL`, `KDRIVE_ARCH`,
`KDRIVE_FORCE_PYTHON`, `KDRIVE_SYSROOT`, `KDRIVE_QUIT_TIMEOUT`. `install`, `update`, `rollback` and
`uninstall` each have a test that sync folders and kDrive's config are unchanged afterwards.
