#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	OPT="$HOME/.local/opt/kdrive"
	SRC="$BATS_TEST_TMPDIR/src"
	OLD="$SRC/kDrive-3.8.8.1-amd64.AppImage"
	NEWER="$SRC/kDrive-3.8.9.1-amd64.AppImage"
	mkdir -p "$SRC"
	make_fake_appimage "$OLD" 2097152 amd64 v3881
	make_fake_appimage "$NEWER" 2097152 amd64 v3891
}

install_both() {
	"$KDRIVE_TOOL" install --from "$OLD" 2>/dev/null
	"$KDRIVE_TOOL" install --from "$NEWER" 2>/dev/null
}

@test "rollback fails without a previous version" {
	"$KDRIVE_TOOL" install --from "$OLD" 2>/dev/null
	run "$KDRIVE_TOOL" rollback
	[ "$status" -ne 0 ]
	[[ "$output" == *"no previous version"* ]]
	cmp "$OPT/kDrive.AppImage" "$OLD"
}

@test "rollback swaps active and previous, including versions" {
	install_both
	run "$KDRIVE_TOOL" rollback
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$OLD"
	cmp "$OPT/kDrive.AppImage.prev" "$NEWER"
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
	[ "$(cat "$OPT/VERSION.prev")" = 3.8.9.1 ]
	[ ! -e "$OPT/kDrive.AppImage.swap" ]
}

@test "rolling back twice restores the original state" {
	install_both
	"$KDRIVE_TOOL" rollback 2>/dev/null
	run "$KDRIVE_TOOL" rollback
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$NEWER"
	cmp "$OPT/kDrive.AppImage.prev" "$OLD"
	[ "$(cat "$OPT/VERSION")" = 3.8.9.1 ]
}

@test "rollback refuses a corrupted previous AppImage" {
	install_both
	echo broken >"$OPT/kDrive.AppImage.prev"
	run "$KDRIVE_TOOL" rollback
	[ "$status" -ne 0 ]
	cmp "$OPT/kDrive.AppImage" "$NEWER"
}

@test "rollback completes a swap interrupted after the first rename" {
	install_both
	# State after "rename .prev over active": old active only in .swap, no .prev.
	mv "$OPT/kDrive.AppImage" "$OPT/kDrive.AppImage.swap"
	mv "$OPT/kDrive.AppImage.prev" "$OPT/kDrive.AppImage"
	run "$KDRIVE_TOOL" rollback
	[ "$status" -eq 0 ]
	[ ! -e "$OPT/kDrive.AppImage.swap" ]
	[ "$(find "$OPT" -name 'kDrive.AppImage*' | wc -l)" -eq 2 ]
}

@test "rollback while kDrive runs, with --yes: waits for quit, then starts" {
	install_both
	export PGREP_STUB_RUNNING=1
	run "$KDRIVE_TOOL" rollback --yes
	[ "$status" -eq 0 ]
	grep -qx -- "-f $OPT/kDrive.AppImage" "$SETSID_STUB_LOG"
}

@test "rollback leaves sync folders and kDrive config untouched" {
	install_both
	mkdir -p "$HOME/kDrive Example" "$HOME/.config/kDrive"
	echo data >"$HOME/kDrive Example/file.txt"
	echo db >"$HOME/.config/kDrive/.parms.db"
	sync_before="$(tree_sum "$HOME/kDrive Example")"
	conf_before="$(tree_sum "$HOME/.config")"
	run "$KDRIVE_TOOL" rollback --yes
	[ "$status" -eq 0 ]
	[ "$(tree_sum "$HOME/kDrive Example")" = "$sync_before" ]
	[ "$(tree_sum "$HOME/.config")" = "$conf_before" ]
}
