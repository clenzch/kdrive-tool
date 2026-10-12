# Migrating an existing manual kDrive install

A one-time checklist for machines where kDrive was installed by hand (e.g. AppImages in
`~/.applications/`). `kdrive-tool` never deletes legacy files itself; you do the cleanup
by hand **after** the new install is verified.

Throughout: synced folders and `~/.config/kDrive` stay where they are. kDrive keeps the
same account and sync state because only the program file changes.

## 0. Look first
```sh
./kdrive-tool doctor
```
Changes nothing. Expect `FAIL installed` (nothing installed by the tool yet), `warn running` and
`warn app entry/autostart` pointing at the old AppImage, plus a list of `leftover` lines.
Keep that list: it is your cleanup checklist for step 5.

## 1. Back up config (not synced files)
```sh
b=~/kdrive-migration-backup-$(date +%F); mkdir -p "$b"/{autostart,applications}
cp -a ~/.config/kDrive ~/.config/com.infomaniak.drive.desktopclient "$b"/
cp -a ~/.config/autostart/kDrive.desktop "$b"/autostart/       # both entries are named kDrive.desktop
cp -a ~/.local/share/applications/kDrive.desktop "$b"/applications/
```
Note your sync folder paths from kDrive's settings. (`install` also makes its own backup of the
sync databases in `~/.local/state/kdrive-tool/backup/`, but a full copy of your own costs nothing.)

## 2. Install side by side
```sh
./kdrive-tool install --from ~/.applications/kDrive-<running>-amd64.AppImage  # copies, source stays
kdrive-tool system                                                           # optional, asks per step
```
Use the version that is **running now**, so the switch changes only the path. Newer versions come
afterwards via `kdrive-tool update` (step 4), and the old binary stays a clean fallback until then.
`--from` checks the file against Infomaniak's published SHA-256 when online. Use plain
`./kdrive-tool install` instead to download the latest version. kDrive keeps running during this
step. `install` notices that and does not start a second instance.

## 3. Switch over
Quit kDrive from its tray icon menu (no `kill`). Then start the new one:
```sh
setsid -f ~/.local/opt/kdrive/kDrive.AppImage   # detached from the terminal
```
On start, kDrive rewrites its app entry and autostart entry to this path.

## 4. Verify
- [ ] same account, every sync shows "up to date", with **no** mass download or deletion activity
- [ ] `kdrive-tool status`: `ok running … from ~/.local/opt/kdrive/kDrive.AppImage`, and `ok app entry`
      and `ok autostart` both starting that path
- [ ] a `kdrive://` link opens kDrive, and the tray icon is visible
- [ ] after a reboot, kDrive autostarts (and `status` still says the same)
- [ ] **Update kDrive** appears in the app grid (that's how you update from now on)

**If anything is wrong:** quit kDrive from the tray and start the old
`~/.applications/kDrive-<old>-amd64.AppImage`. It rewrites the entries back, and config and sync DBs
are unchanged.

## 5. Clean up by hand, one item at a time
Work through the `leftover` lines from `kdrive-tool status`. Typical items:
- [ ] `~/.applications/kDrive-*.AppImage`, then `rmdir ~/.applications`
- [ ] old downloads, e.g. `~/Downloads/kDrive-*.AppImage`
- [ ] custom launchers, e.g. `~/.local/bin/kdrive-launch`
- [ ] stale AppArmor profiles for old paths (the tool's own one is `/etc/apparmor.d/kdrive-tool`):
      `sudo apparmor_parser -R /etc/apparmor.d/<profile> && sudo rm /etc/apparmor.d/<profile>`
- [ ] the backup folder from step 1, once you're confident (keep it for a few weeks)

When `status` shows no `leftover` lines and no warnings, you're done.
