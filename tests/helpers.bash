# Shared bats setup: every test runs against a throwaway $HOME so the real
# kDrive install, config and sync folders are never reachable.

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
KDRIVE_TOOL="$REPO_ROOT/kdrive-tool"

setup_sandbox() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export XDG_STATE_HOME="$HOME/.local/state"
	export XDG_DATA_HOME="$HOME/.local/share"
	unset KDRIVE_DIR KDRIVE_STATE_DIR KDRIVE_LATEST_URL KDRIVE_ARCH KDRIVE_FORCE_PYTHON KDRIVE_SYSROOT
	mkdir -p "$HOME"
	# Stubs shadow network/system commands (curl, pgrep, sudo, ...).
	export PATH="$REPO_ROOT/tests/stubs:$PATH"
	# The curl stub serves https://HOST/PATH from $CURL_STUB_ROOT/HOST/PATH.
	export CURL_STUB_ROOT="$BATS_TEST_TMPDIR/www"
	export CURL_STUB_LOG="$BATS_TEST_TMPDIR/curl.log"
	export SETSID_STUB_LOG="$BATS_TEST_TMPDIR/setsid.log"
	export PGREP_STUB_COUNT="$BATS_TEST_TMPDIR/pgrep.count"
	export NOTIFY_STUB_LOG="$BATS_TEST_TMPDIR/notify.log"
	export SUDO_STUB_LOG="$BATS_TEST_TMPDIR/sudo.log"
	unset PGREP_STUB_RUNNING PGREP_STUB_PID KDRIVE_QUIT_TIMEOUT STUB_MISSING STUB_MISSING_PKGS XDG_CONFIG_HOME
	mkdir -p "$CURL_STUB_ROOT"
	# Fake /etc and /proc/sys for status/doctor/system: a healthy, configured machine.
	export KDRIVE_SYSROOT="$BATS_TEST_TMPDIR/root"
	mkdir -p "$KDRIVE_SYSROOT/etc/apparmor.d" "$KDRIVE_SYSROOT/etc/sysctl.d" \
		"$KDRIVE_SYSROOT/proc/sys/fs/inotify" "$KDRIVE_SYSROOT/proc/sys/kernel"
	echo 524288 >"$KDRIVE_SYSROOT/proc/sys/fs/inotify/max_user_watches"
	echo 1 >"$KDRIVE_SYSROOT/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
	touch "$KDRIVE_SYSROOT/etc/apparmor.d/kdrive-tool"
	export XDG_CURRENT_DESKTOP=ubuntu:GNOME XDG_SESSION_TYPE=wayland
}

# serve URL FILE: make the curl stub return FILE for URL.
serve() {
	local dest="$CURL_STUB_ROOT/${1#*://}"
	mkdir -p "$(dirname "$dest")"
	cp "$2" "$dest"
}

# serve_latest FILE|JSON: serve a drive/latest payload (fixture path or literal JSON).
serve_latest() {
	local src="$1"
	if [[ ! -f "$src" ]]; then
		src="$BATS_TEST_TMPDIR/latest.json"
		printf '%s\n' "$1" >"$src"
	fi
	serve "https://www.infomaniak.com/drive/latest" "$src"
}

# make_fake_appimage PATH [SIZE_BYTES] [ARCH] [SEED]
# Writes a sparse file with an ELF header for ARCH (amd64|arm64) and the AppImage
# type-2 magic ("AI\x02" at offset 8). SEED makes otherwise identical files differ.
make_fake_appimage() {
	local path="$1" size="${2:-2097152}" arch="${3:-amd64}" seed="${4:-}" machine='\x3e'
	[[ "$arch" == arm64 ]] && machine='\xb7'
	printf "\x7fELF\x02\x01\x01\x00AI\x02\x00\x00\x00\x00\x00\x03\x00${machine}\x00%s" "$seed" >"$path"
	truncate -s "$size" "$path"
	chmod +x "$path"
}

# serve_release VERSION FILE [ARCH]: publish FILE (+ .sha256) as kDrive VERSION and
# point drive/latest at it.
serve_release() {
	local version="$1" file="$2" arch="${3:-amd64}" url sum
	url="https://download.storage.infomaniak.com/drive/desktopclient/kDrive-$version-$arch.AppImage"
	serve "$url" "$file"
	sum="$(sha256sum "$file")"
	printf '%s  %s\n' "${sum%% *}" "kDrive-$version-$arch.AppImage" >"$BATS_TEST_TMPDIR/sum"
	serve "$url.sha256" "$BATS_TEST_TMPDIR/sum"
	serve_latest "{\"linux-$arch\": {\"version\": \"$version\", \"downloadurl\": \"$url\"}}"
}

# tree_sum DIR: one checksum over all file names and contents below DIR.
tree_sum() {
	(
		cd "$1" || exit
		find . | LC_ALL=C sort
		find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
	) | sha256sum
}

# run_fn FUNCTION [ARGS...]: source the tool in a subshell and call one of its functions.
run_fn() {
	run bash -c 'src="$1"; shift; source "$src"; "$@"' run_fn "$KDRIVE_TOOL" "$@"
}
