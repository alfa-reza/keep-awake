#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# if an unset variable is referenced, or if a pipeline fails.
set -euo pipefail

ALLOW_BATTERY=false
readonly VERSION="0.1.0"

resolve_script_path() {
    local source_path="${BASH_SOURCE[0]}"
    local script_dir

    if ! script_dir="$(
        cd -- "$(dirname -- "$source_path")" >/dev/null 2>&1 &&
            pwd -P
    )"; then
        printf 'Error: Unable to resolve the script directory.\n' >&2
        exit 1
    fi

    SCRIPT_PATH="$script_dir/$(basename -- "$source_path")"
}

show_help() {
    cat <<'EOF'
Usage:
  keep-awake.sh [OPTIONS]

Options:
  --allow-battery, --force
      Allow operation without external power.

  --version
      Show version information.

  -h, --help
      Show this help message.
EOF
}

show_version() {
    printf 'keep-awake %s\n' "$VERSION"
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --allow-battery | --force)
                ALLOW_BATTERY=true
                ;;
            -h | --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --)
                shift
                if (($# > 0)); then
                    printf 'Error: Unexpected argument: %s\n' "$1" >&2
                    exit 2
                fi
                break
                ;;
            -*)
                printf 'Error: Unknown option: %s\n' "$1" >&2
                printf "Run '%s --help' for usage.\n" "${0##*/}" >&2
                exit 2
                ;;
            *)
                printf 'Error: Unexpected argument: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done
}

parse_internal_arguments() {
    while (($# > 0)); do
        case "$1" in
            --allow-battery)
                ALLOW_BATTERY=true
                ;;
            *)
                printf 'Error: Invalid internal argument: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done
}

validate_positive_integer() {
    local variable_name="$1"
    local value="$2"

    if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Error: %s must be a positive integer, received: %s\n' \
            "$variable_name" "$value" >&2
        exit 2
    fi
}

validate_runtime_configuration() {
    POWER_SUPPLY_PATH="${KEEP_AWAKE_POWER_SUPPLY_PATH:-/sys/class/power_supply}"
    POLL_INTERVAL="${KEEP_AWAKE_POLL_INTERVAL:-5}"
    DEBOUNCE_SECONDS="${KEEP_AWAKE_DEBOUNCE_SECONDS:-30}"

    validate_positive_integer "KEEP_AWAKE_POLL_INTERVAL" "$POLL_INTERVAL"
    validate_positive_integer "KEEP_AWAKE_DEBOUNCE_SECONDS" "$DEBOUNCE_SECONDS"

    if ((POLL_INTERVAL > DEBOUNCE_SECONDS)); then
        printf 'Error: KEEP_AWAKE_POLL_INTERVAL must not exceed KEEP_AWAKE_DEBOUNCE_SECONDS.\n' >&2
        exit 2
    fi
}

charger_online() {
    local dir online supply_type

    shopt -s nullglob
    local power_supplies=("$POWER_SUPPLY_PATH"/*)
    shopt -u nullglob

    if [ ${#power_supplies[@]} -eq 0 ]; then
        return 1
    fi

    for dir in "${power_supplies[@]}"; do
        [[ -d "$dir" ]] || continue
        [[ -f "$dir/online" ]] || continue
        [[ -f "$dir/type" ]] || continue

        online="$(cat "$dir/online" 2>/dev/null || echo 0)"
        supply_type="$(cat "$dir/type" 2>/dev/null || true)"
        [[ -n "$supply_type" ]] || continue

        if [[ "$supply_type" != "Battery" ]]; then
            if [[ "$online" == "1" ]]; then
                return 0
            fi
        fi
    done

    return 1
}

detect_inhibitor() {
    local candidate

    for candidate in systemd-inhibit elogind-inhibit; do
        command -v "$candidate" >/dev/null 2>&1 || continue

        if "$candidate" \
            --what="sleep:handle-lid-switch" \
            --who="$(id -un)" \
            --why="keep-awake capability probe" \
            --mode="block" \
            true >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

monitor_loop() {
    local offline_since=-1

    if [[ "$ALLOW_BATTERY" == "true" ]]; then
        while :; do
            sleep 3600
        done
    fi

    while :; do
        if charger_online >/dev/null 2>&1; then
            offline_since=-1
        elif ((offline_since < 0)); then
            offline_since=$SECONDS
        elif ((SECONDS - offline_since >= DEBOUNCE_SECONDS)); then
            printf '\nKeep-awake: External power has been unavailable for at least %s seconds. Releasing inhibitor lock.\n' \
                "$DEBOUNCE_SECONDS" >&2
            return 0
        fi
        sleep "$POLL_INTERVAL"
    done
}

main() {
    resolve_script_path

    if [[ "${1:-}" == "--internal-monitor" ]]; then
        shift
        parse_internal_arguments "$@"
        validate_runtime_configuration
        monitor_loop
        return
    fi

    parse_arguments "$@"
    validate_runtime_configuration

    if [[ "$ALLOW_BATTERY" != "true" ]] && ! charger_online; then
        printf 'Error: External power is not detected.\n' >&2
        printf 'Connect external power or use --allow-battery.\n' >&2
        exit 1
    fi

    if ! INHIBIT_CMD="$(detect_inhibitor)"; then
        printf 'Error: No working logind-compatible inhibitor was found.\n' >&2
        printf '\nSupported environments:\n' >&2
        printf '  - systemd with systemd-logind\n' >&2
        printf '  - non-systemd with elogind\n' >&2
        exit 1
    fi

    local inhibitor_reason
    if [[ "$ALLOW_BATTERY" == "true" ]]; then
        inhibitor_reason="Keep laptop awake until manually terminated"
    else
        inhibitor_reason="Keep laptop awake while external power is available"
    fi

    echo "=============================================="
    echo " KEEP AWAKE ACTIVE"
    echo "=============================================="
    echo "• Inhibitor backend: $INHIBIT_CMD"
    if [[ "$ALLOW_BATTERY" == "true" ]]; then
        echo "• Power policy: Battery operation allowed (--allow-battery)"
    else
        echo "• Power policy: External power continuously monitored"
        echo "• Auto-release delay: ${DEBOUNCE_SECONDS} seconds"
    fi
    echo "• Suspend and hibernate are blocked"
    printf '%s\n' \
        "• Lid-close suspend is inhibited through the active logind backend" \
        "• System sleep is inhibited; SSH availability still depends on networking"
    echo
    echo "Press Ctrl+C to terminate and restore normal behavior."
    echo "=============================================="

    local monitor_command=(
        "$BASH"
        "$SCRIPT_PATH"
        --internal-monitor
    )

    if [[ "$ALLOW_BATTERY" == "true" ]]; then
        monitor_command+=(--allow-battery)
    fi

    exec "$INHIBIT_CMD" \
        --what="sleep:handle-lid-switch" \
        --who="$(id -un)" \
        --why="$inhibitor_reason" \
        --mode="block" \
        "${monitor_command[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
