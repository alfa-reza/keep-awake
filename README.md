# Keep Awake

A professional Bash script to prevent a Linux laptop from suspending or sleeping when the lid is closed, provided it is connected to a charger. This is ideal for using a laptop as a server or accessing it via SSH, allowing you to close the lid without interrupting operations.

## Features
- **Charger Detection**: Checks for an active external power source (AC/Mains/USB PD) using `/sys/class/power_supply` and fails fast if running only on battery to prevent unintended drain.
- **Inhibitor Lock**: Utilizes `systemd-inhibit` to block both `sleep` (suspend/hibernate) and `handle-lid-switch` (systemd-logind actions when the lid is closed).
- **Graceful Termination**: The inhibitor lock is tied to the lifecycle of the script. Pressing `Ctrl+C` terminates the script and immediately restores normal system power behavior.

## System Requirements & Pre-flight Checks

To run this script, your system must meet the following requirements:

### 1. Init System: systemd
The script relies on `systemd` components. Systems running other init systems (e.g., OpenRC, runit, s6, SysVinit) are not supported.
* **Verify**:
  ```bash
  ps -p 1 -o comm=
  ```
  *Expected Output:* `systemd`

### 2. systemd-inhibit Utility
The `systemd-inhibit` command-line utility must be installed and accessible in your system's `PATH`.
* **Verify existence**:
  ```bash
  command -v systemd-inhibit
  ```
  *Expected Output:* `/usr/bin/systemd-inhibit` (or similar path)
* **Check active locks**:
  ```bash
  systemd-inhibit --list
  ```

### 3. Active systemd-logind Service
The `systemd-logind` daemon must be active as it manages inhibitor locks and handles lid-switch events.
* **Verify**:
  ```bash
  systemctl is-active systemd-logind
  ```
  *Expected Output:* `active`

### 4. Inhibitor Lock Authorization (polkit)
Depending on your distribution's policy kit (`polkit`) configuration, regular users might be restricted from inhibiting certain system events, particularly `handle-lid-switch`.
* **Verify permissions (Dry Run)**:
  Run this command in one terminal:
  ```bash
  systemd-inhibit --what="sleep:handle-lid-switch" --mode=block sleep 10
  ```
  Then, check the active inhibitors in another terminal within 10 seconds:
  ```bash
  systemd-inhibit --list
  ```
  Verify that your test block is listed with `What: sleep:handle-lid-switch` and `Mode: block`. If `systemd-inhibit` prompts for root password or fails with access denied, you may need to run this script as root (`sudo`) or update your polkit policy.

### 5. Kernel Power Supply Interface
The Linux kernel must expose your power supply devices through `sysfs`.
* **Verify**:
  ```bash
  for d in /sys/class/power_supply/*; do
      echo "=== $d ==="
      cat "$d/type" 2>/dev/null
      cat "$d/online" 2>/dev/null
  done
  ```
  *Expected Output:* You should see at least one non-battery power supply (e.g., type `Mains` or `AC`) showing `online` status as `1` when plugged in.

---

## Usage

1. **Make the script executable**:
   ```bash
   chmod +x keep-awake.sh
   ```

2. **Run the script**:
   ```bash
   ./keep-awake.sh
   ```

3. **To stop and restore normal behavior**:
   Simply press `Ctrl+C` in the terminal running the script.
