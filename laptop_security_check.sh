#!/bin/bash

# ============================================================
# Kali Linux - Basic Compromise / Network Security Audit
# Read-only system-admin triage script
# ============================================================

set -u

REPORT="security_audit_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$REPORT") 2>&1

echo "============================================================"
echo " Kali Linux Security / Compromise Triage"
echo "============================================================"
echo "Hostname : $(hostname)"
echo "User     : $(whoami)"
echo "Date     : $(date)"
echo "Kernel   : $(uname -a)"
echo "Report   : $REPORT"
echo "============================================================"
echo

# ------------------------------------------------------------
# 1. SYSTEM INFORMATION
# ------------------------------------------------------------

echo
echo "[1] SYSTEM INFORMATION"
echo "------------------------------------------------------------"

cat /etc/os-release 2>/dev/null
echo
uptime
echo
who
echo

# ------------------------------------------------------------
# 2. NETWORK INTERFACES
# ------------------------------------------------------------

echo
echo "[2] NETWORK INTERFACES"
echo "------------------------------------------------------------"

ip -br addr
echo
ip link
echo

# ------------------------------------------------------------
# 3. ROUTING TABLE
# ------------------------------------------------------------

echo
echo "[3] ROUTING TABLE"
echo "------------------------------------------------------------"

ip route
echo

# ------------------------------------------------------------
# 4. DNS CONFIGURATION
# ------------------------------------------------------------

echo
echo "[4] DNS CONFIGURATION"
echo "------------------------------------------------------------"

echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf 2>/dev/null

echo
echo "--- resolvectl status ---"
resolvectl status 2>/dev/null || true

echo

# ------------------------------------------------------------
# 5. ACTIVE NETWORK CONNECTIONS
# ------------------------------------------------------------

echo
echo "[5] ACTIVE NETWORK CONNECTIONS"
echo "------------------------------------------------------------"

echo "--- TCP/UDP connections ---"
ss -tunap 2>/dev/null

echo
echo "--- Listening TCP ports ---"
ss -lntp 2>/dev/null

echo
echo "--- Listening UDP ports ---"
ss -lnup 2>/dev/null

echo

# ------------------------------------------------------------
# 6. PROCESSES WITH NETWORK CONNECTIONS
# ------------------------------------------------------------

echo
echo "[6] PROCESSES WITH NETWORK CONNECTIONS"
echo "------------------------------------------------------------"

if command -v lsof >/dev/null 2>&1; then
    sudo lsof -nP -i
else
    echo "lsof is not installed."
    echo "Install with: sudo apt install lsof"
fi

echo

# ------------------------------------------------------------
# 7. PROCESS TREE
# ------------------------------------------------------------

echo
echo "[7] RUNNING PROCESSES"
echo "------------------------------------------------------------"

ps aux --sort=-%cpu | head -40

echo
echo "--- Process tree ---"
pstree -alp 2>/dev/null || ps auxf

echo

# ------------------------------------------------------------
# 8. SUSPICIOUS / UNUSUAL NETWORK PORTS
# ------------------------------------------------------------

echo
echo "[8] COMMONLY ABUSED / UNEXPECTED PORTS"
echo "------------------------------------------------------------"

echo "Checking for common remote-access / proxy / tunneling ports..."

ss -lntup 2>/dev/null | grep -E \
':(21|22|23|25|53|80|110|135|139|143|443|445|465|587|993|995|1080|1433|1521|2375|3306|3389|4444|5000|5432|5900|6379|6667|8000|8080|8443|8888|9000|27017)\b' \
|| echo "No matching listening ports found."

echo

# ------------------------------------------------------------
# 9. SSH CONFIGURATION
# ------------------------------------------------------------

echo
echo "[9] SSH CONFIGURATION"
echo "------------------------------------------------------------"

if [ -f /etc/ssh/sshd_config ]; then
    grep -Ei \
    '^(Port|ListenAddress|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|AllowGroups)' \
    /etc/ssh/sshd_config 2>/dev/null
fi

echo
echo "--- SSH service ---"
systemctl status ssh --no-pager 2>/dev/null || true

echo

# ------------------------------------------------------------
# 10. LOGGED-IN USERS
# ------------------------------------------------------------

echo
echo "[10] LOGIN INFORMATION"
echo "------------------------------------------------------------"

echo "--- Current users ---"
who

echo
echo "--- Login history ---"
last -a | head -30

echo
echo "--- Failed login attempts ---"
lastb -a | head -30 2>/dev/null || true

echo

# ------------------------------------------------------------
# 11. LOCAL USERS
# ------------------------------------------------------------

echo
echo "[11] LOCAL USER ACCOUNTS"
echo "------------------------------------------------------------"

awk -F: '$3 >= 1000 {print $1 ":" $3 ":" $6 ":" $7}' /etc/passwd

echo
echo "--- Accounts with login shells ---"

awk -F: '$7 !~ /(nologin|false)$/ {print $1 ":" $7}' /etc/passwd

echo

# ------------------------------------------------------------
# 12. SUDO CONFIGURATION
# ------------------------------------------------------------

echo
echo "[12] SUDO CONFIGURATION"
echo "------------------------------------------------------------"

echo "--- /etc/sudoers entries ---"
grep -vE '^[[:space:]]*#|^[[:space:]]*$' /etc/sudoers 2>/dev/null

echo
echo "--- sudoers.d ---"

if [ -d /etc/sudoers.d ]; then
    find /etc/sudoers.d -type f -maxdepth 1 -print 2>/dev/null
fi

echo

# ------------------------------------------------------------
# 13. SYSTEMD SERVICES
# ------------------------------------------------------------

echo
echo "[13] ENABLED SYSTEMD SERVICES"
echo "------------------------------------------------------------"

systemctl list-unit-files --type=service --state=enabled 2>/dev/null

echo
echo "--- Currently running services ---"

systemctl list-units --type=service --state=running 2>/dev/null

echo

# ------------------------------------------------------------
# 14. SYSTEMD TIMERS
# ------------------------------------------------------------

echo
echo "[14] SYSTEMD TIMERS"
echo "------------------------------------------------------------"

systemctl list-timers --all 2>/dev/null

echo

# ------------------------------------------------------------
# 15. CRON PERSISTENCE
# ------------------------------------------------------------

echo
echo "[15] CRON / SCHEDULED TASKS"
echo "------------------------------------------------------------"

echo "--- System crontab ---"
cat /etc/crontab 2>/dev/null

echo
echo "--- Cron directories ---"

for DIR in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly
do
    echo
    echo "### $DIR"
    ls -la "$DIR" 2>/dev/null
done

echo
echo "--- User crontab ---"

crontab -l 2>/dev/null || echo "No user crontab."

echo
echo "--- Root crontab ---"

sudo crontab -l 2>/dev/null || echo "No root crontab."

echo

# ------------------------------------------------------------
# 16. STARTUP FILES
# ------------------------------------------------------------

echo
echo "[16] USER STARTUP FILES"
echo "------------------------------------------------------------"

for FILE in \
    ~/.bashrc \
    ~/.bash_profile \
    ~/.profile \
    ~/.zshrc \
    ~/.config/autostart/*

do
    if [ -e "$FILE" ]; then
        echo
        echo "### $FILE"
        ls -la "$FILE" 2>/dev/null
    fi
done

echo

# ------------------------------------------------------------
# 17. SSH AUTHORIZED KEYS
# ------------------------------------------------------------

echo
echo "[17] SSH AUTHORIZED KEYS"
echo "------------------------------------------------------------"

find /home /root -name authorized_keys -type f -print 2>/dev/null

echo
echo "--- Contents ---"

for FILE in $(find /home /root -name authorized_keys -type f 2>/dev/null); do
    echo
    echo "### $FILE"
    cat "$FILE"
done

echo

# ------------------------------------------------------------
# 18. RECENTLY MODIFIED SYSTEM FILES
# ------------------------------------------------------------

echo
echo "[18] RECENTLY MODIFIED SYSTEM FILES"
echo "------------------------------------------------------------"

echo "Files modified within the last 3 days under /etc:"

find /etc -type f -mtime -3 -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null \
| sort -r | head -100

echo

# ------------------------------------------------------------
# 19. WORLD-WRITABLE FILES IN IMPORTANT LOCATIONS
# ------------------------------------------------------------

echo
echo "[19] WORLD-WRITABLE FILE CHECK"
echo "------------------------------------------------------------"

find /etc /usr/local/bin /usr/local/sbin /opt \
-type f -perm -0002 -ls 2>/dev/null | head -100

echo

# ------------------------------------------------------------
# 20. SUID / SGID FILES
# ------------------------------------------------------------

echo
echo "[20] SUID / SGID EXECUTABLES"
echo "------------------------------------------------------------"

find / \
-type f \
\( -perm -4000 -o -perm -2000 \) \
-executable \
-print 2>/dev/null | head -200

echo

# ------------------------------------------------------------
# 21. FIREWALL STATUS
# ------------------------------------------------------------

echo
echo "[21] FIREWALL STATUS"
echo "------------------------------------------------------------"

echo "--- UFW ---"
ufw status verbose 2>/dev/null || true

echo
echo "--- nftables ---"
nft list ruleset 2>/dev/null || true

echo
echo "--- iptables ---"
iptables -L -n -v 2>/dev/null || true

echo

# ------------------------------------------------------------
# 22. NETWORK MANAGER CONNECTIONS
# ------------------------------------------------------------

echo
echo "[22] NETWORK MANAGER CONNECTIONS"
echo "------------------------------------------------------------"

nmcli connection show 2>/dev/null || true

echo

# ------------------------------------------------------------
# 23. ARP / NEIGHBOR TABLE
# ------------------------------------------------------------

echo
echo "[23] ARP / NETWORK NEIGHBORS"
echo "------------------------------------------------------------"

ip neigh
echo

# ------------------------------------------------------------
# 24. DNS CACHE / HOST OVERRIDES
# ------------------------------------------------------------

echo
echo "[24] HOSTNAME / DNS OVERRIDES"
echo "------------------------------------------------------------"

echo "--- /etc/hosts ---"
cat /etc/hosts

echo

# ------------------------------------------------------------
# 25. SUSPICIOUS ENVIRONMENT VARIABLES
# ------------------------------------------------------------

echo
echo "[25] PROXY / NETWORK ENVIRONMENT VARIABLES"
echo "------------------------------------------------------------"

env | grep -Ei \
'proxy|http_proxy|https_proxy|all_proxy|no_proxy' \
|| echo "No proxy-related environment variables found."

echo

# ------------------------------------------------------------
# 26. KERNEL MODULES
# ------------------------------------------------------------

echo
echo "[26] LOADED KERNEL MODULES"
echo "------------------------------------------------------------"

lsmod 2>/dev/null | head -100

echo

# ------------------------------------------------------------
# 27. RECENT PACKAGE CHANGES
# ------------------------------------------------------------

echo
echo "[27] RECENT PACKAGE INSTALLATION ACTIVITY"
echo "------------------------------------------------------------"

if [ -f /var/log/dpkg.log ]; then
    grep -E ' install | upgrade | remove ' /var/log/dpkg.log \
    | tail -100
fi

echo

# ------------------------------------------------------------
# 28. RECENT AUTH LOGS
# ------------------------------------------------------------

echo
echo "[28] AUTHENTICATION LOGS"
echo "------------------------------------------------------------"

if [ -f /var/log/auth.log ]; then
    tail -200 /var/log/auth.log
fi

echo

# ------------------------------------------------------------
# 29. SYSTEMD JOURNAL - SECURITY EVENTS
# ------------------------------------------------------------

echo
echo "[29] RECENT SECURITY-RELEVANT JOURNAL EVENTS"
echo "------------------------------------------------------------"

journalctl --since "3 days ago" \
| grep -Ei \
'failed|failure|authentication|sudo|ssh|invalid|accepted|session opened|session closed|segfault|denied' \
| tail -300

echo

# ------------------------------------------------------------
# 30. OUTBOUND CONNECTION SNAPSHOT
# ------------------------------------------------------------

echo
echo "[30] OUTBOUND CONNECTION SNAPSHOT"
echo "------------------------------------------------------------"

ss -tunp 2>/dev/null \
| awk 'NR==1 || $1 ~ /ESTAB|SYN-SENT/'

echo

# ------------------------------------------------------------
# 31. DNS / NETWORK PROCESSES
# ------------------------------------------------------------

echo
echo "[31] PROCESSES RELATED TO NETWORKING"
echo "------------------------------------------------------------"

ps aux | grep -Ei \
'dns|proxy|tor|ssh|sshd|nc |netcat|socat|curl|wget|python|perl|ruby|node' \
| grep -v grep || true

echo

# ------------------------------------------------------------
# 32. CHECK FOR TOR
# ------------------------------------------------------------

echo
echo "[32] TOR CHECK"
echo "------------------------------------------------------------"

if command -v systemctl >/dev/null 2>&1; then
    systemctl status tor --no-pager 2>/dev/null || true
fi

pgrep -a tor 2>/dev/null || echo "No running tor process detected."

echo

# ------------------------------------------------------------
# 33. CHECK FOR COMMON REMOTE ACCESS TOOLS
# ------------------------------------------------------------

echo
echo "[33] REMOTE ACCESS SOFTWARE CHECK"
echo "------------------------------------------------------------"

for CMD in \
    ssh \
    sshd \
    xrdp \
    vncserver \
    nc \
    ncat \
    socat \
    rdesktop \
    remmina \
    metasploit

do
    if command -v "$CMD" >/dev/null 2>&1; then
        echo "Installed: $CMD -> $(command -v "$CMD")"
    fi
done

echo

# ------------------------------------------------------------
# 34. LIST RECENTLY CREATED EXECUTABLES
# ------------------------------------------------------------

echo
echo "[34] RECENTLY MODIFIED EXECUTABLE FILES"
echo "------------------------------------------------------------"

find /tmp /var/tmp /dev/shm \
-type f \
-executable \
-mtime -7 \
-ls 2>/dev/null | head -200

echo

# ------------------------------------------------------------
# 35. /tmp AND SHARED MEMORY CHECK
# ------------------------------------------------------------

echo
echo "[35] TEMPORARY DIRECTORIES"
echo "------------------------------------------------------------"

echo "--- /tmp ---"
ls -lah /tmp

echo
echo "--- /var/tmp ---"
ls -lah /var/tmp 2>/dev/null

echo
echo "--- /dev/shm ---"
ls -lah /dev/shm 2>/dev/null

echo

# ------------------------------------------------------------
# 36. END
# ------------------------------------------------------------

echo
echo "============================================================"
echo " AUDIT COMPLETE"
echo "============================================================"
echo
echo "Report saved to:"
echo "$(realpath "$REPORT")"
echo
echo "IMPORTANT:"
echo "This is a triage script, not a definitive malware scanner."
echo "Investigate unknown processes, connections, users and"
echo "persistence mechanisms before taking action."
echo "============================================================"
