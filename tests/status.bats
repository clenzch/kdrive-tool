#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	OPT="$HOME/.local/opt/kdrive"
	SRC="$BATS_TEST_TMPDIR/src"
	mkdir -p "$SRC"
	make_fake_appimage "$SRC/kDrive-3.8.8.1-amd64.AppImage" 2097152 amd64 v3881
	make_fake_appimage "$SRC/kDrive-3.8.9.1-amd64.AppImage" 2097152 amd64 v3891
}

install_ok() {
	"$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" 2>/dev/null
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
}

# write_kdrive_entries TARGET: what kDrive writes on start, pointing at TARGET.
write_kdrive_entries() {
	mkdir -p "$HOME/.local/share/applications" "$HOME/.config/autostart"
	printf '[Desktop Entry]\nName=kDrive\nExec="%s" %%u\n' "$1" >"$HOME/.local/share/applications/kDrive.desktop"
	printf "[Desktop Entry]\nName=kDrive\nExec='%s'\n" "$1" >"$HOME/.config/autostart/kDrive.desktop"
}

@test "status fails when kDrive is not installed" {
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 1 ]
	[[ "$output" == *"[FAIL] installed"* ]]
}

@test "status is clean on a healthy install" {
	install_ok
	write_kdrive_entries "$OPT/kDrive.AppImage"
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[ ok ] installed      kDrive 3.8.8.1"* ]]
	[[ "$output" == *"[ ok ] app entry"* ]]
	[[ "$output" == *"[ ok ] autostart"* ]]
	[[ "$output" != *"[warn]"* ]]
}

@test "status reports an available update" {
	install_ok
	serve_release 3.8.9.1 "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[warn] latest         kDrive 3.8.9.1 is available"* ]]
	[[ "$output" == *"kdrive-tool update"* ]]
}

@test "status survives being offline" {
	"$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" 2>/dev/null
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 0 ]
	[[ "$output" == *"[warn] latest         could not check"* ]]
}

@test "status fails on a corrupted active AppImage" {
	install_ok
	echo broken >"$OPT/kDrive.AppImage"
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 1 ]
	[[ "$output" == *"not a valid AppImage"* ]]
}

@test "status warns about entries that point elsewhere" {
	install_ok
	write_kdrive_entries "$HOME/.applications/kDrive-3.8.7.1-amd64.AppImage"
	run "$KDRIVE_TOOL" status
	[[ "$output" == *"[warn] app entry      starts $HOME/.applications/kDrive-3.8.7.1-amd64.AppImage"* ]]
	[[ "$output" == *"[warn] autostart      starts $HOME/.applications/kDrive-3.8.7.1-amd64.AppImage"* ]]
}

@test "status shows where a running kDrive was started from" {
	install_ok
	APPIMAGE="$HOME/.applications/kDrive-3.8.7.1-amd64.AppImage" sleep 30 3>&- &
	export PGREP_STUB_RUNNING=always PGREP_STUB_PID=$!
	run "$KDRIVE_TOOL" status
	kill %1
	[[ "$output" == *"[warn] running        kDrive is running from $HOME/.applications/kDrive-3.8.7.1-amd64.AppImage"* ]]
}

@test "status is ok when kDrive runs from the fixed path" {
	install_ok
	APPIMAGE="$OPT/kDrive.AppImage" sleep 30 3>&- &
	export PGREP_STUB_RUNNING=always PGREP_STUB_PID=$!
	run "$KDRIVE_TOOL" status
	kill %1
	[[ "$output" == *"[ ok ] running        kDrive is running from $OPT/kDrive.AppImage"* ]]
}

@test "status lists legacy leftovers and removes nothing" {
	install_ok
	mkdir -p "$HOME/.applications" "$HOME/Downloads" "$HOME/.local/bin" "$HOME/.local/share/applications"
	make_fake_appimage "$HOME/.applications/kDrive-3.8.7.1-amd64.AppImage"
	make_fake_appimage "$HOME/Downloads/kDrive-3.8.5.2-amd64.AppImage"
	touch "$HOME/.local/bin/kdrive-launch"
	printf '[Desktop Entry]\nExec=%s\n' "$HOME/.applications/kDrive-3.8.2.6-amd64.AppImage" \
		>"$HOME/.local/share/applications/appimagekit_x-kDrive.desktop"
	touch "$KDRIVE_SYSROOT/etc/apparmor.d/home.u.Applications.kDrive-3.8.2.6-amd64.AppImage"
	before="$(tree_sum "$HOME")"
	run "$KDRIVE_TOOL" status
	[ "$status" -eq 0 ]
	[ "$(grep -c '^\[info\] leftover' <<<"$output")" -eq 5 ]
	[[ "$output" == *"leftover       $HOME/.local/bin/kdrive-launch"* ]]
	[[ "$output" != *"leftover       $KDRIVE_SYSROOT/etc/apparmor.d/kdrive-tool"* ]]
	[ "$(tree_sum "$HOME")" = "$before" ]
}

@test "status and doctor write nothing, not even the log" {
	run "$KDRIVE_TOOL" doctor
	[ ! -e "$HOME/.local/state/kdrive-tool" ]
	[ ! -e "$HOME/.local/opt" ]
}

@test "status does not clean up the .new of a parallel update" {
	install_ok
	touch "$OPT/kDrive.AppImage.new"
	run "$KDRIVE_TOOL" status
	[ -e "$OPT/kDrive.AppImage.new" ]
}

@test "doctor is clean on a healthy machine" {
	install_ok
	write_kdrive_entries "$OPT/kDrive.AppImage"
	run "$KDRIVE_TOOL" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"[ ok ] libfuse2"* ]]
	[[ "$output" == *"[ ok ] keyring"* ]]
	[[ "$output" == *"[ ok ] tray icon"* ]]
	[[ "$output" == *"[ ok ] inotify"* ]]
	[[ "$output" == *"[ ok ] apparmor"* ]]
	[[ "$output" != *"[warn]"* ]]
}

@test "doctor fails on missing libfuse2 and secret service" {
	install_ok
	export STUB_MISSING="fuse secrets"
	run "$KDRIVE_TOOL" doctor
	[ "$status" -eq 1 ]
	[[ "$output" == *"[FAIL] libfuse2"* ]]
	[[ "$output" == *"[FAIL] keyring"* ]]
}

@test "doctor warns about tray, inotify and AppArmor setup" {
	install_ok
	export STUB_MISSING=appindicator
	echo 65536 >"$KDRIVE_SYSROOT/proc/sys/fs/inotify/max_user_watches"
	rm "$KDRIVE_SYSROOT/etc/apparmor.d/kdrive-tool"
	run "$KDRIVE_TOOL" doctor
	[ "$status" -eq 0 ]
	[[ "$output" == *"[warn] tray icon"* ]]
	[[ "$output" == *"[warn] inotify        max_user_watches=65536"* ]]
	[[ "$output" == *"[warn] apparmor"* ]]
	[[ "$output" == *"kdrive-tool system"* ]]
}

@test "doctor skips the AppArmor profile when user namespaces are not restricted" {
	install_ok
	echo 0 >"$KDRIVE_SYSROOT/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
	rm "$KDRIVE_SYSROOT/etc/apparmor.d/kdrive-tool"
	run "$KDRIVE_TOOL" doctor
	[[ "$output" == *"[ ok ] apparmor       unprivileged user namespaces not restricted"* ]]
}

@test "doctor skips the tray check outside GNOME" {
	install_ok
	export XDG_CURRENT_DESKTOP=KDE STUB_MISSING=appindicator
	run "$KDRIVE_TOOL" doctor
	[[ "$output" != *"tray icon"* ]]
}

@test "status colors marks only when asked or on a terminal" {
	install_ok
	run "$KDRIVE_TOOL" status
	[[ "$output" != *$'\e['* ]]
	CLICOLOR_FORCE=1 run "$KDRIVE_TOOL" status
	[[ "$output" == *$'[\e[32m ok \e[0m] installed'* ]]
	[[ "$output" == *$'[\e[33minfo\e[0m] running'* ]]
	NO_COLOR=1 CLICOLOR_FORCE=1 run "$KDRIVE_TOOL" status
	[[ "$output" != *$'\e['* ]]
}
