#!/usr/bin/env bats

load helpers

setup() { setup_sandbox; }

@test "help prints usage" {
	run "$KDRIVE_TOOL" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: kdrive-tool"* ]]
}

@test "no arguments prints usage" {
	run "$KDRIVE_TOOL"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Commands:"* ]]
}

@test "version prints tool version" {
	run "$KDRIVE_TOOL" version
	[ "$status" -eq 0 ]
	[[ "$output" == kdrive-tool\ * ]]
}

@test "unknown command fails" {
	run "$KDRIVE_TOOL" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown command: frobnicate"* ]]
}

@test "sourcing does not run main" {
	run bash -c "source '$KDRIVE_TOOL'; echo sourced"
	[ "$status" -eq 0 ]
	[ "$output" = "sourced" ]
}
