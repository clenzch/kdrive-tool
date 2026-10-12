#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	OPT="$HOME/.local/opt/kdrive"
	STATE="$HOME/.local/state/kdrive-tool"
	ETC="$KDRIVE_SYSROOT/etc"
	SRC="$BATS_TEST_TMPDIR/src"
	mkdir -p "$SRC"
	make_fake_appimage "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	"$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" 2>/dev/null
	touch "$HOME/.local/share/icons/kdrive-tool.png"
}

@test "uninstall asks first and does nothing without a terminal or --yes" {
	run "$KDRIVE_TOOL" uninstall
	[ "$status" -ne 0 ]
	[[ "$output" == *"cancelled"* ]]
	[ -f "$OPT/kDrive.AppImage" ]
}

@test "uninstall refuses while kDrive is running" {
	export PGREP_STUB_RUNNING=always
	run "$KDRIVE_TOOL" uninstall --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"quit it from the tray first"* ]]
	[ -f "$OPT/kDrive.AppImage" ]
}

@test "uninstall removes exactly the tool's files" {
	run "$KDRIVE_TOOL" uninstall --yes
	[ "$status" -eq 0 ]
	[ ! -e "$OPT" ]
	[ ! -e "$HOME/.local/bin/kdrive-tool" ]
	[ ! -e "$HOME/.local/share/applications/kdrive-tool.desktop" ]
	[ ! -e "$HOME/.local/share/icons/kdrive-tool.png" ]
	[ ! -e "$STATE" ]
	[ -d "$HOME/.local/opt" ]
	[ -d "$HOME/.local/bin" ]
}

@test "uninstall keeps sync folders, kDrive config and kDrive's own entries" {
	mkdir -p "$HOME/kDrive Example/.kDrive-cache" "$HOME/.config/kDrive" "$HOME/.config/autostart" \
		"$HOME/.config/com.infomaniak.drive.desktopclient"
	echo data >"$HOME/kDrive Example/file.txt"
	echo db >"$HOME/.config/kDrive/.parms.db"
	echo conf >"$HOME/.config/com.infomaniak.drive.desktopclient/kDrive_client.conf"
	printf '[Desktop Entry]\nExec=%s\n' "$OPT/kDrive.AppImage" >"$HOME/.config/autostart/kDrive.desktop"
	sync_before="$(tree_sum "$HOME/kDrive Example")"
	conf_before="$(tree_sum "$HOME/.config")"
	run "$KDRIVE_TOOL" uninstall --yes
	[ "$status" -eq 0 ]
	[ "$(tree_sum "$HOME/kDrive Example")" = "$sync_before" ]
	[ "$(tree_sum "$HOME/.config")" = "$conf_before" ]
	[[ "$output" == *"still points to $OPT/kDrive.AppImage"* ]]
}

@test "uninstall keeps config backups but removes log and lock" {
	mkdir -p "$STATE/backup/20260101T000000"
	touch "$STATE/backup/20260101T000000/.parms.db" "$STATE/log"
	run "$KDRIVE_TOOL" uninstall --yes
	[ "$status" -eq 0 ]
	[ -f "$STATE/backup/20260101T000000/.parms.db" ]
	[ ! -e "$STATE/log" ]
	[ ! -e "$STATE/lock" ]
	[[ "$output" == *"kept config backups"* ]]
}

@test "uninstall removes the system additions via sudo" {
	echo profile >"$ETC/apparmor.d/kdrive-tool"
	echo conf >"$ETC/sysctl.d/60-kdrive-inotify.conf"
	touch "$ETC/apparmor.d/other-profile"
	run "$KDRIVE_TOOL" uninstall --yes
	[ "$status" -eq 0 ]
	[ ! -e "$ETC/apparmor.d/kdrive-tool" ]
	[ ! -e "$ETC/sysctl.d/60-kdrive-inotify.conf" ]
	[ -e "$ETC/apparmor.d/other-profile" ]
	grep -qx -- "apparmor_parser -R -- $ETC/apparmor.d/kdrive-tool" "$SUDO_STUB_LOG"
}

@test "uninstall works when run from the installed copy" {
	run "$HOME/.local/bin/kdrive-tool" uninstall --yes
	[ "$status" -eq 0 ]
	[ ! -e "$HOME/.local/bin/kdrive-tool" ]
	[ ! -e "$OPT" ]
}

@test "safe_rm --sudo refuses paths outside the allowlist and directories" {
	run_fn safe_rm --sudo "$ETC/apparmor.d/other-profile"
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing"* ]]
	run_fn safe_rm --sudo /etc/passwd
	[ "$status" -ne 0 ]
	mkdir -p "$ETC/sysctl.d/60-kdrive-inotify.conf"
	run_fn safe_rm --sudo "$ETC/sysctl.d/60-kdrive-inotify.conf"
	[ "$status" -ne 0 ]
	[[ "$output" == *"directory as root"* ]]
}
