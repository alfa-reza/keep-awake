#!/usr/bin/env bash

set -u

# Pastikan systemd-inhibit tersedia
if ! command -v systemd-inhibit >/dev/null 2>&1; then
    echo "Error: systemd-inhibit tidak ditemukan."
    echo "Skrip ini membutuhkan Linux berbasis systemd."
    exit 1
fi

# Cek apakah ada sumber daya eksternal yang sedang online
charger_online() {
    local dir online type

    for dir in /sys/class/power_supply/*; do
        [[ -d "$dir" ]] || continue
        [[ -f "$dir/online" ]] || continue

        online="$(cat "$dir/online" 2>/dev/null || echo 0)"
        type="$(cat "$dir/type" 2>/dev/null || echo Unknown)"

        # Abaikan battery; cari AC/USB/USB-C/PD/dll yang online
        if [[ "$type" != "Battery" && "$online" == "1" ]]; then
            return 0
        fi
    done

    return 1
}

if ! charger_online; then
    echo "Charger tidak terdeteksi."
    echo "Hubungkan charger lalu jalankan kembali."
    exit 1
fi

echo "=============================================="
echo " KEEP AWAKE AKTIF"
echo "=============================================="
echo "• Charger terdeteksi"
echo "• Suspend/hibernate diblokir"
echo "• Tutup layar/lid tidak akan memicu suspend"
echo "• Sistem tetap berjalan untuk SSH"
echo
echo "Tekan Ctrl+C untuk berhenti dan kembali normal."
echo "=============================================="

exec systemd-inhibit \
    --what="sleep:handle-lid-switch" \
    --who="${USER:-$(id -un)}" \
    --why="Keep laptop awake while charging for SSH access" \
    --mode="block" \
    bash -c 'while sleep 3600; do :; done'
