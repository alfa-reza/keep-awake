#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status,
# if an unset variable is referenced, or if a pipeline fails.
set -euo pipefail

# 1. Check if the system is running systemd as the init system (PID 1)
if [ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ] && ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: This script requires a systemd-based Linux distribution." >&2
    exit 1
fi

# 2. Check if systemd-inhibit is available
if ! command -v systemd-inhibit >/dev/null 2>&1; then
    echo "Error: systemd-inhibit is not installed or not in PATH." >&2
    exit 1
fi

# 3. Check if systemd-logind is active
if [ "$(systemctl is-active systemd-logind 2>/dev/null)" != "active" ]; then
    echo "Error: systemd-logind service is not active." >&2
    echo "This service is required to manage inhibitor locks and lid switch events." >&2
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

# 4. Check if the charger is connected
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

# 5. Execute systemd-inhibit to block sleep and lid-switch actions.
# This requires appropriate polkit permissions for handle-lid-switch.
# If permission is denied, systemd-inhibit will output an error and exit.
exec systemd-inhibit \
    --what="sleep:handle-lid-switch" \
    --who="${USER:-$(id -un)}" \
    --why="Keep laptop awake while charging for SSH access" \
    --mode="block" \
    bash -c 'while sleep 3600; do :; done'
