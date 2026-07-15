# Keep Awake

A simple bash script to prevent a Linux laptop from suspending or sleeping when the lid is closed, provided it is connected to a charger. This is particularly useful when using a laptop as a server or accessing it via SSH, allowing you to close the lid without the laptop entering sleep mode.

## Features
- Detects if a charger is connected (fails fast if running only on battery).
- Uses `systemd-inhibit` to block suspend, hibernate, and lid-switch events.
- Released immediately by terminating the script (Ctrl+C).

## Prerequisites
- A systemd-based Linux distribution.
- Power supply interface in `/sys/class/power_supply/`.

## Usage
Make the script executable (if it isn't already) and run it from the terminal:

```bash
chmod +x keep-awake.sh
./keep-awake.sh
```

To stop and return the laptop to its normal behavior, simply press `Ctrl+C`.

## How it works
The script utilizes `systemd-inhibit` with `--what="sleep:handle-lid-switch"` which tells `systemd-logind` to ignore sleep requests and lid close events. The inhibit lock is tied to the life of the script's execution.
