#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	OPT="$HOME/.local/opt/kdrive"
	STATE="$HOME/.local/state/kdrive-tool"
	SYNC="$HOME/kDrive Example"
	CONF="$HOME/.config/kDrive"
	mkdir -p "$OPT" "$STATE/backup/1" "$SYNC/.kDrive-cache" "$CONF" "$HOME/.local/bin"
	echo data >"$SYNC/file.txt"
	echo db >"$CONF/sync.db"
}

assert_refused() {
	[ "$status" -ne 0 ]
	[[ "$output" == *"safe_rm: refusing"* ]]
}

@test "safe_rm deletes a file in the install dir" {
	touch "$OPT/kDrive.AppImage.new"
	run_fn safe_rm "$OPT/kDrive.AppImage.new"
	[ "$status" -eq 0 ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
}

@test "safe_rm deletes a backup directory recursively" {
	touch "$STATE/backup/1/sync.db"
	run_fn safe_rm "$STATE/backup/1"
	[ "$status" -eq 0 ]
	[ ! -e "$STATE/backup/1" ]
}

@test "safe_rm deletes its own binary and desktop entry" {
	mkdir -p "$HOME/.local/share/applications"
	touch "$HOME/.local/bin/kdrive-tool" "$HOME/.local/share/applications/kdrive-tool.desktop"
	run_fn safe_rm "$HOME/.local/bin/kdrive-tool" "$HOME/.local/share/applications/kdrive-tool.desktop"
	[ "$status" -eq 0 ]
	[ ! -e "$HOME/.local/bin/kdrive-tool" ]
	[ ! -e "$HOME/.local/share/applications/kdrive-tool.desktop" ]
}

@test "safe_rm ignores missing paths" {
	run_fn safe_rm "$OPT/does-not-exist"
	[ "$status" -eq 0 ]
}

@test "safe_rm refuses a sync folder" {
	run_fn safe_rm "$SYNC"
	assert_refused
	[ -f "$SYNC/file.txt" ]
}

@test "safe_rm refuses a file inside a sync folder" {
	run_fn safe_rm "$SYNC/file.txt"
	assert_refused
	[ -f "$SYNC/file.txt" ]
}

@test "safe_rm refuses kDrive config and client config" {
	mkdir -p "$HOME/.config/com.infomaniak.drive.desktopclient"
	for p in "$CONF" "$CONF/sync.db" "$HOME/.config/com.infomaniak.drive.desktopclient"; do
		run_fn safe_rm "$p"
		assert_refused
	done
	[ -f "$CONF/sync.db" ]
}

@test "safe_rm refuses HOME, /, and ancestors of protected paths" {
	for p in "$HOME" / "$HOME/.config" "$HOME/.local"; do
		run_fn safe_rm "$p"
		assert_refused
	done
}

@test "safe_rm refuses relative paths and dot components" {
	for p in "kDrive Example" "" "$OPT/.." "$OPT/."; do
		run_fn safe_rm "$p"
		assert_refused
	done
	[ -d "$OPT" ]
}

@test "safe_rm refuses path traversal out of the install dir" {
	run_fn safe_rm "$OPT/../../../.config/kDrive/sync.db"
	assert_refused
	[ -f "$CONF/sync.db" ]
}

@test "safe_rm refuses a lookalike prefix of the install dir" {
	mkdir -p "$HOME/.local/opt/kdrive-evil"
	touch "$HOME/.local/opt/kdrive-evil/x"
	run_fn safe_rm "$HOME/.local/opt/kdrive-evil/x"
	assert_refused
	[ -f "$HOME/.local/opt/kdrive-evil/x" ]
}

@test "safe_rm refuses to follow a symlinked directory out of the allowlist" {
	ln -s "$CONF" "$OPT/link"
	run_fn safe_rm "$OPT/link/sync.db"
	assert_refused
	[ -f "$CONF/sync.db" ]
}

@test "safe_rm removes a symlink itself, not its target" {
	ln -s "$CONF" "$OPT/link"
	run_fn safe_rm "$OPT/link"
	[ "$status" -eq 0 ]
	[ ! -L "$OPT/link" ]
	[ -f "$CONF/sync.db" ]
}

@test "safe_rm refuses everything in HOME when KDRIVE_DIR is overridden to HOME" {
	export KDRIVE_DIR="$HOME"
	run_fn safe_rm "$SYNC"
	assert_refused
	run_fn safe_rm "$HOME/somefile"
	assert_refused
	[ -f "$SYNC/file.txt" ]
}

@test "safe_rm refuses a kDrive cache folder even inside the allowlist" {
	mkdir -p "$OPT/.kDrive-cache"
	run_fn safe_rm "$OPT/.kDrive-cache"
	assert_refused
}

@test "lock prevents concurrent mutating commands" {
	mkdir -p "$STATE"
	exec 8>"$STATE/lock"
	flock -n 8
	run "$KDRIVE_TOOL" update
	exec 8>&-
	[ "$status" -ne 0 ]
	[[ "$output" == *"already running"* ]]
}

@test "lock is released after a command exits" {
	run "$KDRIVE_TOOL" update
	[[ "$output" != *"already running"* ]]
	run "$KDRIVE_TOOL" update
	[[ "$output" != *"already running"* ]]
}

@test "the tool never sends signals to processes" {
	run grep -nwE 'kill|pkill|killall' "$KDRIVE_TOOL"
	[ "$status" -ne 0 ]
}

@test "a kDrive started by the tool does not inherit the lock" {
	mkdir -p "$BATS_TEST_TMPDIR/src"
	make_fake_appimage "$BATS_TEST_TMPDIR/src/kDrive-3.8.8.1-amd64.AppImage"
	KDRIVE_ARCH=x86_64 run "$KDRIVE_TOOL" install --from "$BATS_TEST_TMPDIR/src/kDrive-3.8.8.1-amd64.AppImage" --yes
	[ "$status" -eq 0 ]
	[ -s "$SETSID_STUB_LOG" ]
	[ "$(grep -c LOCK-FD-INHERITED "$SETSID_STUB_LOG")" -eq 0 ]
}
