#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	ETC="$KDRIVE_SYSROOT/etc"
	# A fresh Ubuntu: restricted userns, default inotify limit, no profile, packages missing.
	rm "$ETC/apparmor.d/kdrive-tool"
	echo 65536 >"$KDRIVE_SYSROOT/proc/sys/fs/inotify/max_user_watches"
	export STUB_MISSING_PKGS="libfuse2t64 gnome-keyring"
}

@test "system refuses to run without a terminal or --yes" {
	run "$KDRIVE_TOOL" system
	[ "$status" -ne 0 ]
	[[ "$output" == *"--yes"* ]]
	[ ! -s "$SUDO_STUB_LOG" ]
}

@test "system --yes installs missing packages" {
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	grep -qx -- "apt-get install -y -- libfuse2t64 gnome-keyring" "$SUDO_STUB_LOG"
}

@test "system falls back to libfuse2 on releases without libfuse2t64" {
	export STUB_MISSING=t64 STUB_MISSING_PKGS="libfuse2"
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	grep -qx -- "apt-get install -y -- libfuse2" "$SUDO_STUB_LOG"
}

@test "system --yes writes and loads the AppArmor profile for the fixed path" {
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	profile="$ETC/apparmor.d/kdrive-tool"
	grep -qF "profile kdrive-tool \"$HOME/.local/opt/kdrive/kDrive.AppImage\" flags=(unconfined) {" "$profile"
	grep -qx '  userns,' "$profile"
	[ "$(stat -c %a "$profile")" = 644 ]
	grep -qx -- "apparmor_parser -r -- $profile" "$SUDO_STUB_LOG"
}

@test "system --yes raises the inotify limit persistently" {
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	grep -qx 'fs.inotify.max_user_watches = 524288' "$ETC/sysctl.d/60-kdrive-inotify.conf"
	grep -qx -- "sysctl -q -p $ETC/sysctl.d/60-kdrive-inotify.conf" "$SUDO_STUB_LOG"
}

@test "system is idempotent" {
	"$KDRIVE_TOOL" system --yes 2>/dev/null
	echo 524288 >"$KDRIVE_SYSROOT/proc/sys/fs/inotify/max_user_watches"
	unset STUB_MISSING_PKGS
	: >"$SUDO_STUB_LOG"
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	[ "$(grep -cvx -- '-v' "$SUDO_STUB_LOG")" -eq 0 ]
	[[ "$output" == *"profile up to date"* ]]
}

@test "system skips the profile when user namespaces are not restricted" {
	echo 0 >"$KDRIVE_SYSROOT/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	[ ! -e "$ETC/apparmor.d/kdrive-tool" ]
	[ "$(grep -c apparmor_parser "$SUDO_STUB_LOG")" -eq 0 ]
}

@test "system reports other kDrive AppArmor profiles without removing them" {
	stale="$ETC/apparmor.d/home.u.Applications.kDrive-3.8.2.6-amd64.AppImage"
	touch "$stale"
	run "$KDRIVE_TOOL" system --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"other kDrive profile found (not removed): $stale"* ]]
	[ -e "$stale" ]
}

@test "system rejects unknown options" {
	run "$KDRIVE_TOOL" system --frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}
