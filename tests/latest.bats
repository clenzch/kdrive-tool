#!/usr/bin/env bats

load helpers

setup() {
	setup_sandbox
	export KDRIVE_ARCH=x86_64
	FIX="$REPO_ROOT/tests/fixtures"
	DL="https://download.storage.infomaniak.com/drive/desktopclient"
}

# print_latest: run fetch_latest and print the result as "VERSION URL".
print_latest() {
	# shellcheck disable=SC2016 # expanded by eval inside the sourced tool
	run_fn eval 'fetch_latest && echo "$LATEST_VERSION $LATEST_DOWNLOAD_URL"'
}

# latest_with_url URL: serve a payload whose amd64 entry points at URL.
latest_with_url() {
	serve_latest "{\"linux-amd64\": {\"version\": \"3.8.9.1\", \"downloadurl\": \"$1\"}}"
}

@test "fetch_latest reads the amd64 release" {
	serve_latest "$FIX/latest.json"
	print_latest
	[ "$status" -eq 0 ]
	[ "$output" = "3.8.8.1 $DL/kDrive-3.8.8.1-amd64.AppImage" ]
}

@test "fetch_latest reads the arm64 release on aarch64" {
	export KDRIVE_ARCH=aarch64
	serve_latest "$FIX/latest.json"
	print_latest
	[ "$status" -eq 0 ]
	[ "$output" = "3.8.8.1 $DL/kDrive-3.8.8.1-arm64.AppImage" ]
}

@test "fetch_latest works with the python3 fallback" {
	export KDRIVE_FORCE_PYTHON=1
	serve_latest "$FIX/latest.json"
	print_latest
	[ "$status" -eq 0 ]
	[ "$output" = "3.8.8.1 $DL/kDrive-3.8.8.1-amd64.AppImage" ]
}

@test "fetch_latest forces https on curl, including redirects" {
	serve_latest "$FIX/latest.json"
	print_latest
	grep -q -- "--proto =https --proto-redir =https" "$CURL_STUB_LOG"
}

@test "fetch_latest fails on network error" {
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"could not fetch"* ]]
}

@test "fetch_latest fails on invalid JSON (jq and python3)" {
	serve_latest "$FIX/latest-garbage.json"
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid JSON"* ]]
	export KDRIVE_FORCE_PYTHON=1
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid JSON"* ]]
}

@test "fetch_latest fails when no linux release for the arch is listed" {
	for json in '{"win32": {"version": "3.8.7.1"}}' '[]' '"x"' '{"linux-amd64": "x"}' \
		'{"linux-amd64": {"version": 3, "downloadurl": "x"}}'; do
		serve_latest "$json"
		print_latest
		[ "$status" -ne 0 ]
		[[ "$output" == *"no linux-amd64 release"* ]]
	done
}

@test "fetch_latest rejects a bad version" {
	serve_latest "$FIX/latest-bad-version.json"
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"unexpected version format"* ]]
}

@test "fetch_latest rejects a foreign download host" {
	serve_latest "$FIX/latest-bad-host.json"
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing download URL"* ]]
}

@test "fetch_latest rejects lookalike and malformed download URLs" {
	for url in \
		"http://download.storage.infomaniak.com/x.AppImage" \
		"https://download.storage.infomaniak.com.evil.com/x.AppImage" \
		"https://evil.com@download.storage.infomaniak.com/x.AppImage" \
		"https://download.storage.infomaniak.com@evil.com/x.AppImage" \
		"https://download.storage.infomaniak.com:8443/x.AppImage" \
		"https://download.storage.infomaniak.com/x.exe" \
		"https://download.storage.infomaniak.com/../x.AppImage" \
		"https://download.storage.infomaniak.com/x.AppImage?y" \
		"https://download.storage.infomaniak.com/a b.AppImage"; do
		latest_with_url "$url"
		print_latest
		[ "$status" -ne 0 ]
		[[ "$output" == *"refusing download URL"* ]]
	done
}

@test "fetch_latest refuses a non-https update URL" {
	export KDRIVE_LATEST_URL=http://www.infomaniak.com/drive/latest
	print_latest
	[ "$status" -ne 0 ]
	[[ "$output" == *"refusing non-https"* ]]
	[ ! -s "$CURL_STUB_LOG" ]
}

@test "map_arch maps uname values and rejects others" {
	run_fn map_arch x86_64
	[ "$output" = amd64 ]
	run_fn map_arch aarch64
	[ "$output" = arm64 ]
	run_fn map_arch riscv64
	[ "$status" -ne 0 ]
	[[ "$output" == *"unsupported architecture"* ]]
}

@test "version_gt compares numerically" {
	run_fn version_gt 3.8.10.1 3.8.9.1
	[ "$status" -eq 0 ]
	run_fn version_gt 3.8.9.1 3.8.10.1
	[ "$status" -ne 0 ]
	run_fn version_gt 3.8.8.1 3.8.8.1
	[ "$status" -ne 0 ]
	run_fn version_gt 4.0.0.0 3.99.99.99
	[ "$status" -eq 0 ]
	run_fn version_gt 3.8.8.08 3.8.8.7
	[ "$status" -eq 0 ]
}
