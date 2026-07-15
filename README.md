# Keep Awake

A professional Bash script that starts only when external power is detected and then holds a logind-compatible inhibitor lock until terminated, allowing a laptop to remain awake with the lid closed for workloads such as SSH.

## Features
- **Charger Detection**: Checks for an active external power source (AC/Mains/USB PD) using `/sys/class/power_supply` and fails fast if running only on battery. This check serves as a startup precondition.
- **Dynamic Capability Detection**: Probes the system for a working logind-compatible inhibitor backend (`systemd-inhibit` or `elogind-inhibit`) by actively attempting to acquire a temporary lock. No hard systemd init or daemon dependencies.
- **Graceful Termination**: The inhibitor lock is tied to the lifecycle of the script. Pressing `Ctrl+C` terminates the script and immediately restores normal system power behavior.

## Compatibility & Requirements

### Expected Compatibility
- **`systemd`-based Linux** with `systemd-logind` (e.g., Ubuntu, Debian, Fedora, Arch, openSUSE).
- **Non-`systemd` Linux** with `elogind` (e.g., Void Linux, Artix, Gentoo, Devuan, Alpine Linux with elogind).

The distributions above describe the intended compatibility range, not a
guarantee that every release, desktop environment, or hardware platform has
been tested. The script requires Bash, `/sys/class/power_supply`, and a
working `systemd-inhibit` or `elogind-inhibit` command that can acquire a
blocking inhibitor lock for the current session.

### Tested Platforms

No platform-specific compatibility claims are recorded yet. Add an entry here
only after verifying the script on a real system, including its power-supply
reporting and lid-close behavior.

### Unsupported Environments
- Systems without a logind-compatible inhibitor backend (e.g., pure `acpid`-only setups).

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

Running multiple instances creates multiple independent inhibitor locks. Normal
sleep and lid-close behavior is restored after all running instances have
exited.

---

## Limitations

Keep Awake holds a logind-compatible inhibitor lock only while the process is
running. The charger check is performed at startup and is not repeated after
the inhibitor starts.

It does not:

- configure or maintain Wi-Fi, Ethernet, or SSH connectivity;
- override firmware-level shutdown or thermal protection;
- prevent power loss or battery discharge after the charger is disconnected;
- guarantee identical behavior across all desktop environments and hardware;
- prevent sleep mechanisms that do not honor the selected logind inhibitor.

## Safety

Running a laptop continuously with the lid closed may increase heat depending
on the device's cooling design. Keep the device adequately ventilated, avoid
enclosed bags or containers, and do not disable normal operating-system or
firmware thermal protections.

## Verification Plan

Perform these steps to verify that your system is configured correctly and that the script functions as expected:

1. **Start on Power**: Run `keep-awake.sh` with the charger connected. Verify that it starts without error.

2. **Verify Active Inhibitor**: In another terminal, inspect the active inhibitors using the detected backend:
   ```bash
   systemd-inhibit --list
   # or:
   elogind-inhibit --list
   ```
   Verify that the lock contains:
   * `What`: `sleep:handle-lid-switch`
   * `Mode`: `block`

3. **Lid-Closed Access**: Close the laptop lid. Verify from another machine that:
   * The laptop remains powered on.
   * The network connection remains active.
   * SSH remains accessible.

4. **Verify Precondition Fails on Battery**: Run the script while the charger is disconnected. Verify that startup fails immediately with:
   ```text
   Error: Charger not detected or not connected.
   ```

5. **Verify Precondition Lifetime**: Run the script while the charger is connected, then unplug the charger. Verify that the script remains active (as charger detection is checked at startup only).

6. **Verify Lock Release**: Press `Ctrl+C` on the active script, and verify that the inhibitor lock is released immediately.

7. **Restore Behavior**: Verify that the system returns to its previously configured lid-close and sleep behavior.
