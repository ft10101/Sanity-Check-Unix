#!/usr/bin/env bash

# ============================================================
# Linux Laptop Hardware Sanity Check
# Non-destructive diagnostic script
# Tested conceptually for Debian/Kali/Ubuntu-based systems
# ============================================================

set +e

REPORT="hardware_report_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee "$REPORT") 2>&1

# ---------- Formatting ----------
line() {
    printf '%*s\n' 70 '' | tr ' ' '='
}

section() {
    echo
    line
    echo "  $1"
    line
}

ok()   { echo "[ PASS ] $1"; }
warn() { echo "[ WARN ] $1"; }
fail() { echo "[ FAIL ] $1"; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "=============================================================="
echo "           LAPTOP HARDWARE SANITY CHECK"
echo "=============================================================="
echo "Date       : $(date)"
echo "Hostname   : $(hostname)"
echo "Kernel     : $(uname -r)"
echo "Report     : $REPORT"
echo "=============================================================="

# ============================================================
# SYSTEM
# ============================================================

section "SYSTEM INFORMATION"

echo "OS:"
cat /etc/os-release 2>/dev/null | grep -E '^(PRETTY_NAME|VERSION)='

echo
echo "Kernel:"
uname -a

echo
echo "Architecture:"
uname -m

echo
echo "Uptime:"
uptime

# ============================================================
# CPU
# ============================================================

section "CPU"

if command_exists lscpu; then
    lscpu | grep -E \
    'Model name|Socket|Core|Thread|CPU\(s\)|MHz|CPU max MHz|CPU min MHz'
else
    warn "lscpu not installed"
fi

echo
echo "CPU Load:"
uptime

# CPU temperature
echo
echo "CPU / System Temperatures:"

if command_exists sensors; then
    sensors 2>/dev/null
else
    warn "lm-sensors not installed"
    echo "Install with:"
    echo "sudo apt install lm-sensors"
fi

# ============================================================
# MEMORY
# ============================================================

section "RAM / MEMORY"

free -h

echo
echo "Memory modules:"

if command_exists dmidecode; then
    sudo dmidecode --type memory 2>/dev/null |
    grep -E \
    'Memory Device|Size:|Type:|Speed:|Manufacturer:|Part Number:|Serial Number:'
else
    warn "dmidecode not installed"
fi

echo
echo "Kernel memory errors:"

MEM_ERRORS=$(dmesg 2>/dev/null |
    grep -Ei 'memory error|edac|ecc error|mce|hardware error' |
    tail -20)

if [ -z "$MEM_ERRORS" ]; then
    ok "No obvious memory/ECC hardware errors found in dmesg"
else
    warn "Possible memory-related errors detected:"
    echo "$MEM_ERRORS"
fi

# ============================================================
# STORAGE
# ============================================================

section "STORAGE DEVICES"

if command_exists lsblk; then
    lsblk -e 7 -o NAME,MODEL,SIZE,TYPE,FSTYPE,MOUNTPOINTS,ROTA,TRAN
fi

echo
echo "Disk usage:"
df -hT

echo
echo "Disk health / SMART:"

if command_exists smartctl; then

    for disk in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'); do

        echo
        echo "------------------------------------------------------------"
        echo "DEVICE: $disk"
        echo "------------------------------------------------------------"

        sudo smartctl -H "$disk" 2>/dev/null

        echo
        sudo smartctl -A "$disk" 2>/dev/null |
        grep -Ei \
        'SMART overall|PASSED|FAILED|Temperature|Reallocated|Pending|Uncorrect|Error|Percentage|Available Spare|Critical Warning|Media'
    done

else
    warn "smartctl not installed"
    echo "Install with:"
    echo "sudo apt install smartmontools"
fi

# ============================================================
# NVMe
# ============================================================

section "NVMe HEALTH"

if command_exists nvme; then

    for nv in /dev/nvme[0-9]; do
        [ -e "$nv" ] || continue

        echo
        echo "DEVICE: $nv"

        sudo nvme smart-log "$nv" 2>/dev/null

    done

else
    echo "nvme-cli not installed."
    echo "Install with:"
    echo "sudo apt install nvme-cli"
fi

# ============================================================
# GPU
# ============================================================

section "GPU"

if command_exists lspci; then

    lspci | grep -Ei \
    'VGA compatible controller|3D controller|Display controller'

    echo
    echo "Detailed GPU information:"
    lspci -nnk | grep -A4 -Ei \
    'VGA compatible controller|3D controller|Display controller'

else
    warn "lspci not available"
fi

# ============================================================
# MOTHERBOARD / BIOS
# ============================================================

section "MOTHERBOARD / BIOS"

if command_exists dmidecode; then

    sudo dmidecode -t system 2>/dev/null |
    grep -E \
    'Manufacturer:|Product Name:|Version:|Serial Number:|UUID:'

    echo
    sudo dmidecode -t baseboard 2>/dev/null |
    grep -E \
    'Manufacturer:|Product Name:|Version:|Serial Number:'

    echo
    sudo dmidecode -t bios 2>/dev/null |
    grep -E \
    'Vendor:|Version:|Release Date:|BIOS Revision:'

else
    warn "dmidecode not installed"
fi

# ============================================================
# BATTERY
# ============================================================

section "BATTERY"

if [ -d /sys/class/power_supply ]; then

    for bat in /sys/class/power_supply/BAT*; do

        [ -d "$bat" ] || continue

        echo
        echo "Battery: $(basename "$bat")"

        echo "Status       : $(cat "$bat/status" 2>/dev/null)"
        echo "Capacity     : $(cat "$bat/capacity" 2>/dev/null)%"
        echo "Technology   : $(cat "$bat/technology" 2>/dev/null)"
        echo "Manufacturer : $(cat "$bat/manufacturer" 2>/dev/null)"
        echo "Model        : $(cat "$bat/model_name" 2>/dev/null)"
        echo "Cycle Count  : $(cat "$bat/cycle_count" 2>/dev/null)"

        DESIGN=$(cat "$bat/energy_full_design" 2>/dev/null)
        FULL=$(cat "$bat/energy_full" 2>/dev/null)

        if [[ "$DESIGN" =~ ^[0-9]+$ ]] &&
           [[ "$FULL" =~ ^[0-9]+$ ]] &&
           [ "$DESIGN" -gt 0 ]; then

            HEALTH=$(awk \
            "BEGIN {printf \"%.1f\", ($FULL/$DESIGN)*100}")

            echo "Health       : ${HEALTH}%"

            if (( $(echo "$HEALTH >= 80" | bc -l) )); then
                ok "Battery health appears good"
            elif (( $(echo "$HEALTH >= 60" | bc -l) )); then
                warn "Battery has noticeable wear"
            else
                fail "Battery has significant wear"
            fi
        fi
    done

else
    warn "No battery information found"
fi

# ============================================================
# NETWORK
# ============================================================

section "NETWORK HARDWARE"

if command_exists ip; then
    ip -br link
fi

echo
echo "Network controllers:"

if command_exists lspci; then
    lspci | grep -Ei \
    'Ethernet controller|Network controller|Wireless'
fi

echo
echo "Wireless interfaces:"

if command_exists iw; then
    iw dev 2>/dev/null
fi

# ============================================================
# USB
# ============================================================

section "USB DEVICES"

if command_exists lsusb; then
    lsusb
else
    warn "lsusb not installed"
fi

# ============================================================
# AUDIO
# ============================================================

section "AUDIO HARDWARE"

if command_exists lspci; then
    lspci | grep -Ei \
    'audio|multimedia'
fi

if command_exists aplay; then
    echo
    echo "Audio playback devices:"
    aplay -l 2>/dev/null
fi

# ============================================================
# PCI
# ============================================================

section "PCI HARDWARE"

if command_exists lspci; then
    lspci
fi

# ============================================================
# FAN / SENSORS
# ============================================================

section "SENSORS / FAN"

if command_exists sensors; then
    sensors 2>/dev/null
else
    warn "Install lm-sensors for temperature/fan information:"
    echo "sudo apt install lm-sensors"
fi

# ============================================================
# KERNEL HARDWARE ERRORS
# ============================================================

section "KERNEL HARDWARE ERRORS"

echo "Recent hardware-related kernel messages:"

ERRORS=$(sudo dmesg 2>/dev/null |
    grep -Ei \
    'hardware error|machine check|mce|edac|ecc|thermal|overheat|critical|firmware error|I/O error|nvme.*error|ata.*error|gpu.*error|amdgpu.*error|nvidia.*error' |
    tail -50)

if [ -z "$ERRORS" ]; then
    ok "No obvious hardware errors found in dmesg"
else
    warn "Hardware-related messages found:"
    echo "$ERRORS"
fi

# ============================================================
# FAILED SYSTEMD SERVICES
# ============================================================

section "FAILED SYSTEM SERVICES"

if command_exists systemctl; then

    FAILED=$(systemctl --failed --no-legend 2>/dev/null)

    if [ -z "$FAILED" ]; then
        ok "No failed systemd services"
    else
        warn "Failed services detected:"
        echo "$FAILED"
    fi
fi

# ============================================================
# THERMAL
# ============================================================

section "THERMAL STATUS"

if [ -d /sys/class/thermal ]; then

    for zone in /sys/class/thermal/thermal_zone*; do

        [ -d "$zone" ] || continue

        TYPE=$(cat "$zone/type" 2>/dev/null)
        TEMP=$(cat "$zone/temp" 2>/dev/null)

        if [[ "$TEMP" =~ ^[0-9]+$ ]]; then
            TEMP_C=$(awk "BEGIN {printf \"%.1f\", $TEMP/1000}")

            printf "%-25s %s°C\n" "$TYPE" "$TEMP_C"
        fi

    done

fi

# ============================================================
# USB / PCI ERRORS
# ============================================================

section "I/O ERROR CHECK"

IO_ERRORS=$(sudo dmesg 2>/dev/null |
    grep -Ei \
    'I/O error|blk_update_request|Buffer I/O|USB.*error|reset.*USB|ata.*error|nvme.*error' |
    tail -30)

if [ -z "$IO_ERRORS" ]; then
    ok "No obvious storage/USB I/O errors found"
else
    warn "I/O errors detected:"
    echo "$IO_ERRORS"
fi

# ============================================================
# CPU MICROCODE
# ============================================================

section "CPU MICROCODE"

grep -m1 -E \
'^(vendor_id|model name|microcode)' /proc/cpuinfo 2>/dev/null

echo
grep -m1 microcode /proc/cpuinfo 2>/dev/null

# ============================================================
# FINAL SUMMARY
# ============================================================

section "FINAL SUMMARY"

echo
echo "The following checks were performed:"
echo
echo "  [✓] CPU"
echo "  [✓] CPU temperature"
echo "  [✓] RAM"
echo "  [✓] Memory errors"
echo "  [✓] Storage devices"
echo "  [✓] SMART health"
echo "  [✓] NVMe health"
echo "  [✓] GPU"
echo "  [✓] Motherboard"
echo "  [✓] BIOS"
echo "  [✓] Battery"
echo "  [✓] Network hardware"
echo "  [✓] USB"
echo "  [✓] Audio"
echo "  [✓] PCI devices"
echo "  [✓] Sensors"
echo "  [✓] Kernel hardware errors"
echo "  [✓] Thermal status"
echo "  [✓] I/O errors"
echo "  [✓] Failed system services"

echo
line
echo "REPORT SAVED TO:"
echo "$REPORT"
line

echo
echo "IMPORTANT:"
echo "PASS means no obvious problem was detected."
echo "WARN means something deserves investigation."
echo "Absence of errors does NOT guarantee hardware is perfect."
echo
