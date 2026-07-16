#!/usr/bin/env bats

setup() {
    # Bats v1.x provides BATS_TEST_TMPDIR natively, but we ensure it works if fallback needed
    if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
        export BATS_TEST_TMPDIR="$(mktemp -d)"
    fi
    MOCK_BIN="$BATS_TEST_TMPDIR/bin"
    MOCK_POWER="$BATS_TEST_TMPDIR/power"
    LOG_FILE="$BATS_TEST_TMPDIR/keep-awake.log"

    mkdir -p "$MOCK_BIN" "$MOCK_POWER"

    cp "$BATS_TEST_DIRNAME/fixtures/bin/fake-inhibit" "$MOCK_BIN/systemd-inhibit"
    cp "$BATS_TEST_DIRNAME/fixtures/bin/fake-inhibit" "$MOCK_BIN/elogind-inhibit"
    chmod +x "$MOCK_BIN/systemd-inhibit" "$MOCK_BIN/elogind-inhibit"

    export PATH="$MOCK_BIN:$PATH"
    export KEEP_AWAKE_POWER_SUPPLY_PATH="$MOCK_POWER"
    export KEEP_AWAKE_POLL_INTERVAL=1
    export KEEP_AWAKE_DEBOUNCE_SECONDS=2
    
    SCRIPT="$BATS_TEST_DIRNAME/../keep-awake.sh"
}

teardown() {
    if [[ -n "${KEEP_AWAKE_PID:-}" ]]; then
        kill "$KEEP_AWAKE_PID" 2>/dev/null || true
        wait "$KEEP_AWAKE_PID" 2>/dev/null || true
    fi
}

wait_for_log() {
    local expected="$1"
    local attempts=50

    while ((attempts > 0)); do
        if grep -Fq -- "$expected" "$LOG_FILE"; then
            return 0
        fi
        sleep 0.1
        attempts=$((attempts - 1))
    done

    printf 'Timed out waiting for log: %s\n' "$expected" >&2
    return 1
}

wait_seconds_and_check_alive() {
    local duration="$1"
    local start="$SECONDS"
    while ((SECONDS - start < duration)); do
        if ! kill -0 "$KEEP_AWAKE_PID" 2>/dev/null; then
            printf 'Process exited unexpectedly during wait\n' >&2
            return 1
        fi
        sleep 0.1
    done
    return 0
}

set_ac_online() {
    mkdir -p "$MOCK_POWER/AC"
    echo "Mains" > "$MOCK_POWER/AC/type"
    echo "1" > "$MOCK_POWER/AC/online"
}

set_ac_offline() {
    mkdir -p "$MOCK_POWER/AC"
    echo "Mains" > "$MOCK_POWER/AC/type"
    echo "0" > "$MOCK_POWER/AC/online"
}

function ac_online_startup_succeeds { #@test
    set_ac_online
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    kill -0 "$KEEP_AWAKE_PID"
}

function ac_offline_startup_fails { #@test
    set_ac_offline
    run "$SCRIPT"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"Error: External power is not detected."* ]]
}

function allow_battery_bypasses_ac { #@test
    set_ac_offline
    "$SCRIPT" --allow-battery >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "Power policy: Battery operation allowed"
}

function force_alias_works { #@test
    set_ac_offline
    "$SCRIPT" --force >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "Power policy: Battery operation allowed"
}

function help_succeeds { #@test
    run "$SCRIPT" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage:"* ]]
}

function version_is_reported { #@test
    run "$SCRIPT" --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == "keep-awake 0.1.0" ]]
}

function rejects_unknown_options { #@test
    run "$SCRIPT" --invalid-option
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Unknown option"* ]]
}

function invalid_poll_interval { #@test
    export KEEP_AWAKE_POLL_INTERVAL=abc
    run "$SCRIPT"
    [[ "$status" -eq 2 ]]
}

function invalid_debounce { #@test
    export KEEP_AWAKE_DEBOUNCE_SECONDS=0
    run "$SCRIPT"
    [[ "$status" -eq 2 ]]
}

function poll_exceeds_debounce { #@test
    export KEEP_AWAKE_POLL_INTERVAL=10
    export KEEP_AWAKE_DEBOUNCE_SECONDS=5
    run "$SCRIPT"
    [[ "$status" -eq 2 ]]
}

function ac_offline_auto_releases { #@test
    set_ac_online
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    set_ac_offline
    wait_for_log "Releasing inhibitor lock"
    run wait "$KEEP_AWAKE_PID"
    [[ "$status" -eq 0 ]]
    unset KEEP_AWAKE_PID
}

function ac_reconnect_resets_timer { #@test
    set_ac_online
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    set_ac_offline
    wait_seconds_and_check_alive 1 # Before debounce (2s)
    set_ac_online
    wait_seconds_and_check_alive 2 # Past original debounce
    if grep -Fq "Releasing inhibitor lock" "$LOG_FILE"; then
        return 1
    fi
}

function ac_offline_after_reconnect { #@test
    set_ac_online
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    set_ac_offline
    wait_seconds_and_check_alive 1
    set_ac_online
    wait_seconds_and_check_alive 1
    set_ac_offline
    wait_for_log "Releasing inhibitor lock"
    run wait "$KEEP_AWAKE_PID"
    [[ "$status" -eq 0 ]]
    unset KEEP_AWAKE_PID
}

function power_supply_directory_missing { #@test
    set_ac_online
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    rm -rf "$MOCK_POWER/AC"
    wait_for_log "Releasing inhibitor lock"
}

function multiple_supplies_one_online { #@test
    set_ac_offline
    mkdir -p "$MOCK_POWER/USB"
    echo "USB" > "$MOCK_POWER/USB/type"
    echo "1" > "$MOCK_POWER/USB/online"
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
}

function systemd_fails_elogind_succeeds { #@test
    set_ac_online
    export FAKE_SYSTEMD_INHIBITOR_FAIL=true
    export FAKE_ELOGIND_INHIBITOR_FAIL=false
    "$SCRIPT" >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "Inhibitor backend: elogind-inhibit"
}

function all_inhibitors_fail { #@test
    set_ac_online
    export FAKE_SYSTEMD_INHIBITOR_FAIL=true
    export FAKE_ELOGIND_INHIBITOR_FAIL=true
    run "$SCRIPT"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"No working logind-compatible inhibitor was found"* ]]
}

function invalid_internal_argument { #@test
    run "$SCRIPT" --internal-monitor --invalid-internal
    [[ "$status" -eq 2 ]]
}

function allow_battery_skips_monitoring { #@test
    set_ac_offline
    "$SCRIPT" --allow-battery >"$LOG_FILE" 2>&1 3>&- &
    KEEP_AWAKE_PID=$!
    wait_for_log "KEEP AWAKE ACTIVE"
    wait_seconds_and_check_alive 3 # Past debounce
    if grep -Fq "Releasing inhibitor lock" "$LOG_FILE"; then
        return 1
    fi
}
