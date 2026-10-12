#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	OPT="$HOME/.local/opt/kdrive"
	BACKUPS="$HOME/.local/state/kdrive-tool/backup"
	SRC="$BATS_TEST_TMPDIR/src"
	OLD="$SRC/kDrive-3.8.8.1-amd64.AppImage"
	NEWER="$SRC/kDrive-3.8.9.1-amd64.AppImage"
	mkdir -p "$SRC"
	make_fake_appimage "$OLD" 2097152 amd64 v3881
	make_fake_appimage "$NEWER" 2097152 amd64 v3891
	"$KDRIVE_TOOL" install --from "$OLD" 2>/dev/null
}

# make_db PATH: a small SQLite DB with one known row, in WAL mode like kDrive's.
make_db() {
	python3 -c '
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("pragma journal_mode=wal")
c.execute("create table t(v)")
c.execute("insert into t values (42)")
c.commit()
' "$1"
}

@test "update fails when kDrive is not installed by the tool" {
	rm -rf "$OPT"
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -ne 0 ]
	[[ "$output" == *"run 'kdrive-tool install' first"* ]]
}

@test "update is a no-op when up to date" {
	serve_release 3.8.8.1 "$OLD"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[[ "$output" == *"up to date"* ]]
	[ "$(grep -c '\.AppImage$' "$CURL_STUB_LOG")" -eq 0 ]
}

@test "update installs a newer version and keeps the old one as .prev" {
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$NEWER"
	cmp "$OPT/kDrive.AppImage.prev" "$OLD"
	[ "$(cat "$OPT/VERSION")" = 3.8.9.1 ]
	[ "$(cat "$OPT/VERSION.prev")" = 3.8.8.1 ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
}

@test "repeating update is a no-op" {
	serve_release 3.8.9.1 "$NEWER"
	"$KDRIVE_TOOL" update 2>/dev/null
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[[ "$output" == *"up to date"* ]]
	[ "$(grep -c '\.AppImage$' "$CURL_STUB_LOG")" -eq 1 ]
}

@test "update keeps only one previous version" {
	make_fake_appimage "$SRC/kDrive-3.8.10.1-amd64.AppImage" 2097152 amd64 v38101
	serve_release 3.8.9.1 "$NEWER"
	"$KDRIVE_TOOL" update 2>/dev/null
	serve_release 3.8.10.1 "$SRC/kDrive-3.8.10.1-amd64.AppImage"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage.prev" "$NEWER"
	[ "$(find "$OPT" -name 'kDrive.AppImage*' | wc -l)" -eq 2 ]
}

@test "update never downgrades unless --force" {
	"$KDRIVE_TOOL" install --from "$NEWER" 2>/dev/null
	serve_release 3.8.8.1 "$OLD"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[[ "$output" == *"newer than the published"* ]]
	cmp "$OPT/kDrive.AppImage" "$NEWER"
	run "$KDRIVE_TOOL" update --force
	[ "$status" -eq 0 ]
	cmp "$OPT/kDrive.AppImage" "$OLD"
}

@test "a failed update leaves the active version untouched" {
	serve_release 3.8.9.1 "$NEWER"
	serve "https://download.storage.infomaniak.com/drive/desktopclient/kDrive-3.8.9.1-amd64.AppImage" "$OLD"
	run "$KDRIVE_TOOL" update
	[ "$status" -ne 0 ]
	[[ "$output" == *"SHA-256 mismatch"* ]]
	cmp "$OPT/kDrive.AppImage" "$OLD"
	[ "$(cat "$OPT/VERSION")" = 3.8.8.1 ]
	[ ! -e "$OPT/kDrive.AppImage.new" ]
	[ ! -e "$OPT/kDrive.AppImage.prev" ]
}

@test "update fails cleanly on network error" {
	run "$KDRIVE_TOOL" update
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not fetch"* ]]
	cmp "$OPT/kDrive.AppImage" "$OLD"
}

@test "update backs up kDrive's DBs consistently and never changes them" {
	mkdir -p "$HOME/.config/kDrive" "$HOME/.config/com.infomaniak.drive.desktopclient"
	make_db "$HOME/.config/kDrive/.sync_1.db"
	echo conf >"$HOME/.config/com.infomaniak.drive.desktopclient/kDrive_client.conf"
	before="$(tree_sum "$HOME/.config")"
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[ "$(tree_sum "$HOME/.config")" = "$before" ]
	backup="$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d)"
	[ "$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select v from t").fetchone()[0])' "$backup/.sync_1.db")" = 42 ]
	[ -f "$backup/kDrive_client.conf" ]
}

@test "backup keeps raw copies of files that are not readable as SQLite" {
	mkdir -p "$HOME/.config/kDrive"
	echo garbage >"$HOME/.config/kDrive/.parms.db"
	echo wal >"$HOME/.config/kDrive/.parms.db-wal"
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	backup="$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d)"
	[ "$(cat "$backup/.parms.db")" = garbage ]
	[ "$(cat "$backup/.parms.db-wal")" = wal ]
	[[ "$output" == *"may be inconsistent"* ]]
}

@test "backup includes data that is still only in the WAL" {
	mkdir -p "$HOME/.config/kDrive"
	db="$HOME/.config/kDrive/.sync_1.db"
	make_db "$db"
	# Keep a connection open with an uncheckpointed commit, like a running kDrive.
	python3 -c '
import sqlite3, sys, time
c = sqlite3.connect(sys.argv[1])
c.execute("pragma wal_autocheckpoint=0")
c.execute("insert into t values (43)")
c.commit()
open(sys.argv[2], "w").close()
time.sleep(5)
' "$db" "$BATS_TEST_TMPDIR/ready" 3>&- &
	while [ ! -e "$BATS_TEST_TMPDIR/ready" ]; do sleep 0.1; done
	[ -s "$db-wal" ]
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	kill %1 2>/dev/null || true
	[ "$status" -eq 0 ]
	backup="$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d)"
	[ ! -e "$backup/.sync_1.db-wal" ]
	[ "$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from t").fetchone()[0])' "$backup/.sync_1.db")" = 2 ]
}

@test "update keeps the newest 3 config backups" {
	mkdir -p "$HOME/.config/kDrive" "$BACKUPS"/20200101T000000 "$BACKUPS"/20200102T000000 "$BACKUPS"/20200103T000000
	make_db "$HOME/.config/kDrive/.parms.db"
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[ "$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 3 ]
	[ ! -e "$BACKUPS/20200101T000000" ]
	[ -e "$BACKUPS/20200103T000000" ]
}

@test "update leaves sync folders untouched" {
	mkdir -p "$HOME/kDrive Example/.kDrive-cache"
	echo data >"$HOME/kDrive Example/file.txt"
	before="$(tree_sum "$HOME/kDrive Example")"
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	[ "$(tree_sum "$HOME/kDrive Example")" = "$before" ]
}

@test "update without a terminal does not start kDrive" {
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	[ ! -s "$SETSID_STUB_LOG" ]
}

@test "update --yes starts kDrive when it was not running" {
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	grep -qx -- "-f $OPT/kDrive.AppImage" "$SETSID_STUB_LOG"
}

@test "update while kDrive runs, without --yes: notify, no restart" {
	export PGREP_STUB_RUNNING=always
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update
	[ "$status" -eq 0 ]
	grep -q "Quit and restart kDrive" "$NOTIFY_STUB_LOG"
	[ ! -s "$SETSID_STUB_LOG" ]
}

@test "update --yes waits for kDrive to be quit, then starts the new version" {
	export PGREP_STUB_RUNNING=2
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	grep -q "Quit kDrive from its tray icon" "$NOTIFY_STUB_LOG"
	[ "$(wc -l <"$SETSID_STUB_LOG")" -eq 1 ]
	[[ "$output" == *"kDrive 3.8.9.1 started"* ]]
}

@test "update --yes gives up waiting and does not start a second kDrive" {
	export PGREP_STUB_RUNNING=always KDRIVE_QUIT_TIMEOUT=1
	serve_release 3.8.9.1 "$NEWER"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"still running"* ]]
	[ ! -s "$SETSID_STUB_LOG" ]
	cmp "$OPT/kDrive.AppImage" "$NEWER"
}

@test "up-to-date update offers to start kDrive when it is not running" {
	serve_release 3.8.8.1 "$OLD"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	[[ "$output" == *"up to date"* ]]
	grep -qx -- "-f $OPT/kDrive.AppImage" "$SETSID_STUB_LOG"
}

@test "up-to-date update leaves a running kDrive alone" {
	export PGREP_STUB_RUNNING=always
	serve_release 3.8.8.1 "$OLD"
	run "$KDRIVE_TOOL" update --yes
	[ "$status" -eq 0 ]
	[ ! -s "$SETSID_STUB_LOG" ]
	[ ! -s "$NOTIFY_STUB_LOG" ]
}

@test "update rejects unknown options" {
	run "$KDRIVE_TOOL" update --frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}
