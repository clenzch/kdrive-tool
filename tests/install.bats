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

# assert_not_installed: a failed install leaves nothing half-done behind.
assert_not_installed() {
	[ ! -e "$OPT/kDrive.AppImage" ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
	[ ! -e "$OPT/VERSION" ]
}

# downloads: number of AppImage downloads the curl stub saw.
downloads() {
	grep -c '\.AppImage$' "$CURL_STUB_LOG" || true
}

@test "install downloads, verifies and activates the latest release" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ -x "$OPT/kDrive.AppImage" ]
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
	[ ! -e "$OPT/kDrive.AppImage.prev" ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
}

@test "install copies itself and writes its desktop entry" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -eq 0 ]
	cmp "$HOME/.local/bin/kdrive-tool" "$KDRIVE_TOOL"
	[ -x "$HOME/.local/bin/kdrive-tool" ]
	entry="$HOME/.local/share/applications/kdrive-tool.desktop"
	grep -qx "Exec=\"$HOME/.local/bin/kdrive-tool\" --pause update" "$entry"
	grep -qx "Exec=\"$OPT/kDrive.AppImage\"" "$entry"
	grep -qx 'Terminal=true' "$entry"
}

@test "install never writes kDrive's own desktop entries" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -eq 0 ]
	[ ! -e "$HOME/.local/share/applications/kDrive.desktop" ]
	[ ! -e "$HOME/.config/autostart/kDrive.desktop" ]
}

@test "install fails on checksum mismatch and leaves nothing behind" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	serve "https://download.storage.infomaniak.com/drive/desktopclient/kDrive-3.8.8.1-amd64.AppImage" \
		"$SRC/kDrive-3.8.9.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"SHA-256 mismatch"* ]]
	assert_not_installed
}

@test "install fails without a published checksum, before downloading" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	rm "$CURL_STUB_ROOT/download.storage.infomaniak.com/drive/desktopclient/kDrive-3.8.8.1-amd64.AppImage.sha256"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not fetch checksum"* ]]
	[ "$(downloads)" -eq 0 ]
	assert_not_installed
}

@test "install fails when the download fails" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	rm "$CURL_STUB_ROOT/download.storage.infomaniak.com/drive/desktopclient/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"download failed"* ]]
	assert_not_installed
}

@test "install rejects a download that is not an AppImage" {
	head -c 2097152 /dev/zero >"$SRC/zeros"
	serve_release 3.8.8.1 "$SRC/zeros"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"not an ELF file"* ]]
	assert_not_installed
}

@test "install rejects a truncated download" {
	make_fake_appimage "$SRC/small" 4096
	serve_release 3.8.8.1 "$SRC/small"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"too small"* ]]
	assert_not_installed
}

@test "install rejects an AppImage for the wrong architecture" {
	make_fake_appimage "$SRC/arm" 2097152 arm64
	serve_release 3.8.8.1 "$SRC/arm"
	run "$KDRIVE_TOOL" install
	[ "$status" -ne 0 ]
	[[ "$output" == *"not built for amd64"* ]]
	assert_not_installed
}

@test "install is idempotent: no second download" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install
	[ "$status" -eq 0 ]
	run "$KDRIVE_TOOL" install
	[ "$status" -eq 0 ]
	[[ "$output" == *"already installed"* ]]
	[ "$(downloads)" -eq 1 ]
	[ -f "$HOME/.local/share/applications/kdrive-tool.desktop" ]
}

@test "install --from copies the file and never touches the source" {
	src="$SRC/kDrive-3.8.8.1-amd64.AppImage"
	before="$(sha256sum "$src")"
	run "$KDRIVE_TOOL" install --from "$src"
	[ "$status" -eq 0 ]
	[ -f "$src" ]
	[ "$(sha256sum "$src")" = "$before" ]
	cmp "$OPT/kDrive.AppImage" "$src"
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
	[ "$(downloads)" -eq 0 ]
}

@test "install --from checks the published checksum when available" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$status" -eq 0 ]
	[[ "$output" == *"checksum matches"* ]]
}

@test "install --from refuses a file that differs from the published release" {
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not match the published"* ]]
	assert_not_installed
}

@test "install --from needs a version it can read from the name or --version" {
	cp "$SRC/kDrive-3.8.8.1-amd64.AppImage" "$SRC/kdrive.AppImage"
	run "$KDRIVE_TOOL" install --from "$SRC/kdrive.AppImage"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--version"* ]]
	assert_not_installed
	run "$KDRIVE_TOOL" install --from "$SRC/kdrive.AppImage" --version 3.8.8.1
	[ "$status" -eq 0 ]
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
}

@test "install --from a newer version keeps the old one as .prev" {
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$status" -eq 0 ]
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	cmp "$OPT/kDrive.AppImage.prev" "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$(cat "$OPT/VERSION")" = 3.8.9.1 ]
	[ "$(cat "$OPT/VERSION.prev")" = 3.8.8.1 ]
}

@test "install --from refuses a downgrade unless --force" {
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$status" -ne 0 ]
	[[ "$output" == *"--force"* ]]
	cmp "$OPT/kDrive.AppImage" "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" --force
	[ "$status" -eq 0 ]
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
}

@test "a failed replacement leaves the active AppImage untouched" {
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	make_fake_appimage "$SRC/kDrive-3.8.9.1-amd64.AppImage" 2097152 arm64
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.9.1-amd64.AppImage"
	[ "$status" -ne 0 ]
	cmp "$OPT/kDrive.AppImage" "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
}

@test "install does not start kDrive without a terminal or --yes" {
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	[ "$status" -eq 0 ]
	[ ! -s "$SETSID_STUB_LOG" ]
	[[ "$output" == *"start kDrive with"* ]]
}

@test "install --yes starts kDrive from the fixed path" {
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" --yes
	[ "$status" -eq 0 ]
	grep -qx -- "-f $OPT/kDrive.AppImage" "$SETSID_STUB_LOG"
}

@test "install does not start a second kDrive" {
	export PGREP_STUB_RUNNING=always
	run "$KDRIVE_TOOL" install --from "$SRC/kDrive-3.8.8.1-amd64.AppImage" --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"kDrive is running"* ]]
	[ ! -s "$SETSID_STUB_LOG" ]
}

@test "install leaves sync folders and kDrive config untouched" {
	mkdir -p "$HOME/kDrive Example/.kDrive-cache" "$HOME/.config/kDrive" "$HOME/.config/autostart"
	echo data >"$HOME/kDrive Example/file.txt"
	echo db >"$HOME/.config/kDrive/sync.db"
	echo entry >"$HOME/.config/autostart/kDrive.desktop"
	sync_before="$(tree_sum "$HOME/kDrive Example")"
	conf_before="$(tree_sum "$HOME/.config")"
	serve_release 3.8.8.1 "$SRC/kDrive-3.8.8.1-amd64.AppImage"
	run "$KDRIVE_TOOL" install --yes
	[ "$status" -eq 0 ]
	[ "$(tree_sum "$HOME/kDrive Example")" = "$sync_before" ]
	[ "$(tree_sum "$HOME/.config")" = "$conf_before" ]
}

@test "install rejects unknown options" {
	run "$KDRIVE_TOOL" install --frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}
