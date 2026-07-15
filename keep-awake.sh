#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# if an unset variable is referenced, or if a pipeline fails.
set -euo pipefail

# Determine a working logind-compatible inhibitor backend.
detect_inhibitor() {
    local candidate

    for candidate in systemd-inhibit elogind-inhibit; do
        command -v "$candidate" >/dev/null 2>&1 || continue

        # Perform an actual capability probe. Run 'true' to quickly hold and release the lock.
        if "$candidate" \
            --what="sleep:handle-lid-switch" \
            --who="${USER:-$(id -un)}" \
            --why="keep-awake capability probe" \
            --mode="block" \
            true >/dev/null 2>&1
        then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

if ! INHIBIT_CMD="$(detect_inhibitor)"; then
    echo "Error: No working logind-compatible inhibitor was found." >&2
    echo >&2
    echo "Supported environments:" >&2
    echo "  - systemd with systemd-logind" >&2
    echo "  - non-systemd with elogind" >&2
    exit 1
fi

# Function to detect if an external power source (charger) is connected
charger_online() {
    local dir online type found_charger=false

    # Enable nullglob to avoid errors if /sys/class/power_supply/ is empty
    shopt -s nullglob
    local power_supplies=(/sys/class/power_supply/*)
    shopt -u nullglob

    if [ ${#power_supplies[@]} -eq 0 ]; then
        echo "Error: No power supply devices found in /sys/class/power_supply/." >&2
        return 1
    fi

    for dir in "${power_supplies[@]}"; do
        [[ -d "$dir" ]] || continue
        [[ -f "$dir/online" ]] || continue

        online="$(cat "$dir/online" 2>/dev/null || echo 0)"
        type="$(cat "$dir/type" 2>/dev/null || echo Unknown)"

        # Check for non-battery power supplies (AC, USB, Mains, etc.)
        if [[ "$type" != "Battery" ]]; then
            found_charger=true
            if [[ "$online" == "1" ]]; then
                return 0
            fi
        fi
    done

    if [ "$found_charger" = false ]; then
        echo "Error: No external power source (AC/Mains) found in /sys/class/power_supply/." >&2
    fi
    return 1
}

# Check if the charger is connected (precondition check)
if ! charger_online; then
    echo "Error: Charger not detected or not connected." >&2
    echo "Please connect the charger and try again." >&2
    exit 1
fi

echo "=============================================="
echo " KEEP AWAKE ACTIVE"
echo "=============================================="
echo "• Charger detected (Online)"
echo "• Suspend and hibernate are blocked"
echo "• Closing the lid will not trigger suspend"
echo "• System remains active (ideal for SSH sessions)"
echo
echo "Press Ctrl+C to terminate and restore normal behavior."
echo "=============================================="

# Execute the inhibitor to block sleep and lid-switch actions.
# The lock is active for the lifetime of this command.
exec "$INHIBIT_CMD" \
    --what="sleep:handle-lid-switch" \
    --who="${USER:-$(id -un)}" \
    --why="Keep laptop awake while charging for SSH access" \
    --mode="block" \
    bash -c 'while :; do sleep 3600; done'
