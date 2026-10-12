# kdrive-tool

One self-contained bash script to install, update and roll back the
[Infomaniak kDrive](https://www.infomaniak.com/kdrive) desktop client (AppImage) on Ubuntu,
and to bring other machines to the same setup.

## Why
kDrive for Linux ships as a versioned AppImage. Every update means downloading, `chmod`-ing
and fixing launchers, and kDrive rewrites its own desktop entries (app grid and autostart) with
whatever path it was last started from. `kdrive-tool` keeps the AppImage at **one fixed path**,
`~/.local/opt/kdrive/kDrive.AppImage`, and swaps the file in place on update. kDrive's entries,
autostart and the AppArmor profile then stay valid across updates.

## Quick start
Requirements: Ubuntu 24.04 or newer (amd64 or arm64), `curl` and `python3` (`jq` is used if present).

```sh
# get the single file `kdrive-tool` (clone this repo, or copy just that file), then:
./kdrive-tool install       # download the latest kDrive, verify it, install the tool to ~/.local/bin
kdrive-tool system          # optional, sudo, asks per step: libfuse2, keyring, AppArmor, inotify
kdrive-tool doctor          # check everything
```
Then log in to kDrive and add your sync folders in its GUI. Accounts and sync state are
deliberately not copied between machines.

Already running kDrive from a hand-downloaded AppImage? Follow [docs/migration.md](docs/migration.md).

## Updating
When kDrive says a new version is available, open **Update kDrive** from the app grid, or run
`kdrive-tool update`. The tool downloads and verifies the new version, backs up kDrive's config and
swaps the file in. Then it asks you to quit kDrive from its tray icon menu, and starts the new version
once kDrive has exited. If kDrive is already up to date and not running, it offers to start it.

Something wrong with the new version? `kdrive-tool rollback` switches back to the previous one.

## Commands
| Command | What it does |
|---|---|
| `install [--from FILE [--version V]] [--force] [--yes]` | Install the latest kDrive, or copy a local AppImage (`--from`, never moved). Also installs the tool to `~/.local/bin`, extracts the icon and adds the **Update kDrive** app entry. Safe to run again. |
| `update [--yes] [--force]` | Install the latest version if it is newer, then offer to restart kDrive. Never downgrades without `--force`. |
| `rollback [--yes]` | Swap the active and previous version, then offer to restart kDrive. |
| `status` | Installed, previous and latest version; whether kDrive runs, and from which file; where kDrive's entries point; leftovers from manual installs. |
| `doctor` | `status` plus prerequisites: libfuse2, keyring (secret service), tray icon extension, inotify limit, AppArmor. |
| `system [--yes]` | Machine-wide setup via sudo, asking before each step (see below). |
| `uninstall [--yes]` | Remove what the tool installed (see [Safety](#safety)). |

`--yes` answers prompts with yes. Without a terminal and without `--yes`, kDrive is never started or restarted.

`status` and `doctor` change nothing. Each line is marked `ok`, `info`, `warn` or `FAIL` (colored in a terminal;
`NO_COLOR` turns colors off). The exit code is 1 only if there is a `FAIL`, so both work in scripts.

### What `system` changes
Each step asks first, and only runs if needed:
- installs `libfuse2t64` (or `libfuse2`) and `gnome-keyring` if missing;
- if the kernel restricts unprivileged user namespaces (Ubuntu 24.04+), writes
  `/etc/apparmor.d/kdrive-tool` for the fixed path and loads it (kDrive's login window needs it);
- writes `/etc/sysctl.d/60-kdrive-inotify.conf` (`fs.inotify.max_user_watches = 524288`), so large syncs
  can be watched.

## Safety
- **Your data is never touched:** not the sync folders, not `~/.config/kDrive` (accounts and sync databases),
  not `~/.config/com.infomaniak.drive.desktopclient`, not the keyring. Swapping the program file leaves
  config and sync databases in place, so the new version resumes the same syncs without re-downloading.
- **Writes are limited to its own files:** `~/.local/opt/kdrive/`, `~/.local/state/kdrive-tool/`,
  `~/.local/bin/kdrive-tool`, `~/.local/share/applications/kdrive-tool.desktop`,
  `~/.local/share/icons/kdrive-tool.png`, and via `system` the two files under `/etc` above.
  Every deletion goes through one allowlist check, which is covered by tests.
- **Downloads are verified before use:** HTTPS only, from `download.storage.infomaniak.com` only, and they must
  match the SHA-256 Infomaniak publishes next to each AppImage. The file must be a real AppImage for your CPU.
  Only then is it swapped in by a rename. The active path never disappears, and the previous version is kept.
- **Config backup before every swap:** kDrive's databases and client settings are copied to
  `~/.local/state/kdrive-tool/backup/` (last 3 kept). Synced files are not part of the backup.
- **No signals to kDrive:** kDrive has no scriptable quit, so the tool asks you to quit it from the tray.
- **No automatic cleanup:** `status` lists old AppImages, launchers and AppArmor profiles from manual installs.
  You remove them yourself.
- **`uninstall`** asks first and refuses while kDrive runs from the fixed path. It keeps the config backups
  and kDrive's own entries, and never touches accounts or synced files. To remove an account or a sync,
  use the kDrive GUI.

## Troubleshooting
- **kDrive does not start ("dlopen(): error loading libfuse.so.2"):** run `kdrive-tool system`, or
  `sudo apt install libfuse2t64`.
- **The login window stays blank or crashes:** on Ubuntu 24.04+ AppArmor may block the user namespaces it needs.
  Run `kdrive-tool system` (AppArmor step). `doctor` shows whether the profile is in place.
- **kDrive asks for the login again after every reboot:** the keyring is missing or locked. `doctor` checks
  for the secret service. Install `gnome-keyring` and make sure it is unlocked at login.
- **No tray icon (GNOME):** `gnome-extensions enable ubuntu-appindicators@ubuntu.com`, or install
  `gnome-shell-extension-appindicator`.
- **Crash at start under Wayland:** try `QT_QPA_PLATFORM=xcb ~/.local/opt/kdrive/kDrive.AppImage`.
- **Large syncs stop picking up changes:** the inotify limit is too low. Run `kdrive-tool system` (inotify step).
- **kDrive misbehaves after an update:** `kdrive-tool rollback`. Config backups are in
  `~/.local/state/kdrive-tool/backup/`.
- **"another kdrive-tool is already running":** another `install`/`update`/`rollback`/`system`/`uninstall`
  is still open, for example an **Update kDrive** window waiting for Enter. Close it and retry.
- **Log of everything the tool did:** `~/.local/state/kdrive-tool/log`.

## Development
The tool is the single file `kdrive-tool`. Everything else is tests and docs.
```sh
sudo apt install shellcheck shfmt bats
make check   # shellcheck + shfmt + bats
```
Tests run with a throwaway `$HOME`, a fake `/etc` and `/proc/sys`, and stubs for `curl`, `sudo`, `pgrep`
and others (`tests/stubs/`). They never touch the real machine or the network.
How it works and why: [docs/DESIGN.md](docs/DESIGN.md). Coding conventions: [CLAUDE.md](CLAUDE.md).

## License
MIT, see [LICENSE](LICENSE).

kDrive is a product of [Infomaniak](https://www.infomaniak.com). This project is an independent tool
and is not affiliated with or endorsed by Infomaniak.
