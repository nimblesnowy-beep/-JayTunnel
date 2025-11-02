#!/usr/bin/env bash
# Jay Tunnel Production Installer - XRAY, SSH, Telegram Panel, WebSocket, gRPC, SSL, All Features
# https://github.com/nimblesnowy-beep/-JayTunnel
# Enhanced with Interactive Menu

set -Eeuo pipefail

INSTALL_DIR="/etc/jay-tunnel"
BIN_DIR="/usr/local/bin"
LOG_DIR="/var/log/jay-tunnel"
FLAG_FILE="$INSTALL_DIR/.installed"
DOMAIN_FILE="$INSTALL_DIR/domain"
CONFIG_JSON="$INSTALL_DIR/config.json"
ENV_FILE="$INSTALL_DIR/.env"
ERROR_LOG="$LOG_DIR/installer_error.log"
PANEL_PY_URL="https://raw.githubusercontent.com/nimblesnowy-beep/-JayTunnel/main/panel.py"
PANEL_PY="$INSTALL_DIR/panel.py"
AUTO_NOTIFY_FILE="$INSTALL_DIR/auto_notify_enabled"
BACKUP_DIR="$INSTALL_DIR/backup"

# Helper
error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ERROR_LOG" >&2
}
trap 'error_log "Error on line $LINENO: $BASH_COMMAND"' ERR

spinner() {
    local pid=$1
    local msg="$2"
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r[%c] $msg" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r    \r"
}

get_system_info() {
    HOSTNAME=$(hostname)
    DOMAIN=$(cat "$DOMAIN_FILE" 2>/dev/null || echo "Not set")
    IP=$(curl -s icanhazip.com || echo "Unknown")
    OS=$(lsb_release -d | cut -f2 2>/dev/null || echo "Unknown")
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' || echo "0")
    MEM=$(free -m | awk 'NR==2{printf "%s/%sMB", $3,$2 }')
    UPTIME=$(uptime -p)
    XRAY_STATUS=$(systemctl is-active jay-tunnel 2>/dev/null || echo "inactive")
    NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    TIME=$(date '+%d %b %Y | %H:%M:%S')
    [ "$XRAY_STATUS" = "active" ] && XRAY_EMOJI="🟢" || XRAY_EMOJI="🔴"
    [ "$NGINX_STATUS" = "active" ] && NGINX_EMOJI="🟢" || NGINX_EMOJI="🔴"
}

print_menu() {
    get_system_info
    clear
    cat <<EOF
╔══════════════════════════════════════════════════════════════╗
║                   XRAY CORE + REALITY MANAGER                ║
╠══════════════════════════════════════════════════════════════╣
║ 🖥️  Hostname : $HOSTNAME
║ 🌐  Domain   : $DOMAIN
║ 🏠  IP Addr  : $IP
║ ⚙️  OS       : $OS
║ 🧠  CPU Load : ${CPU_LOAD}%
║ 💾  Memory   : $MEM
║ ⏱️  Uptime   : $UPTIME
║ 🔌  Xray     : $XRAY_EMOJI $(echo $XRAY_STATUS | tr 'a-z' 'A-Z')
║ 🌍  Nginx    : $NGINX_EMOJI $(echo $NGINX_STATUS | tr 'a-z' 'A-Z')
║ 🕒  Time     : $TIME
╚══════════════════════════════════════════════════════════════╝

📦  XRAY MANAGEMENT
───────────────────────────────────────────────────────────────
 [1]  Add User SSH
 [2]  Add User VLESS (Reality)
 [3]  Add User VMESS (Reality)
 [4]  Add User TROJAN (Reality)
 [5]  View Active Users
 [6]  Restart Xray Service
 [7]  Update Xray Core

🤖  AUTOMATION & TELEGRAM BOT
───────────────────────────────────────────────────────────────
 [8]  Setup Telegram Bot Notification
 [9]  Test Telegram Notification
[10]  Enable/Disable Auto Notification

🌐  NETWORK & DOMAIN
───────────────────────────────────────────────────────────────
[11]  Domain Configuration
[12]  Cloudflare DNS Setup (API)
[13]  Custom Domain (DuckDNS + Token)
[14]  DNS Changer (1.1.1.1 / 8.8.8.8 / 9.9.9.9)
[15]  Show Port & Service Status
[16]  Check Nginx Status / Restart

🔐  SSL & SECURITY
───────────────────────────────────────────────────────────────
[17]  Renew SSL Certificate (acme.sh)
[18]  Install Custom SSL Certificate
[19]  Firewall Control (Enable / Disable)

🧰  SYSTEM TOOLS
───────────────────────────────────────────────────────────────
[20]  Speedtest (CLI)
[21]  Clear Logs & Cache
[22]  Backup & Restore Config
[23]  Change Server Banner / MOTD
[24]  Set Costume Client Banner (/banner)
[25]  Check Server Resource (htop)
[26]  Set Auto Reboot (Cron)
[27]  Reboot Server

⚙️  SERVICE CONTROL
───────────────────────────────────────────────────────────────
[28]  Restart Services Menu

───────────────────────────────────────────────────────────────
[0]   Exit

───────────────────────────────────────────────────────────────
Pilih menu [0-28]: 
EOF
}

init_system() {
    echo "[*] Updating system & installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y &
    spinner $! "Updating system..."
    apt-get install -y curl wget jq socat unzip tar git lsb-release cron net-tools \
        gnupg2 ca-certificates python3 python3-pip htop bc ntpdate ufw nginx fail2ban \
        python3-telegram python3-pip >/dev/null 2>&1 &
    spinner $! "Installing dependencies..."
    pip3 install speedtest-cli python-telegram-bot --upgrade >/dev/null 2>&1 || true
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$LOG_DIR" "$BACKUP_DIR"
    touch "$ERROR_LOG"
    echo "[OK] System initialized."
}

setup_firewall() {
    echo "[*] Setting up firewall rules (UFW)..."
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    ufw allow 8443/tcp
    ufw allow 8080/tcp
    ufw allow 8443/udp
    ufw --force enable
    ufw reload
    echo "[OK] Firewall rules applied."
}

install_xray_core() {
    echo "[*] Fetching latest Xray Core release..."
    LATEST_URL=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.assets[] | select(.name | endswith("linux-64.zip")) | .browser_download_url' | head -n1)
    if [[ -z "$LATEST_URL" ]]; then
        error_log "Failed to fetch Xray release."
        return 1
    fi
    wget -O /tmp/xray.zip "$LATEST_URL" &
    spinner $! "Downloading Xray Core..."
    unzip -o /tmp/xray.zip -d /tmp/xray &
    spinner $! "Extracting Xray..."
    install -m 755 /tmp/xray/xray "$BIN_DIR/xray"
    cp /tmp/xray/{geoip.dat,geosite.dat} "$INSTALL_DIR/" 2>/dev/null || true
    if [[ ! -f "$CONFIG_JSON" ]]; then
        cat > "$CONFIG_JSON" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "inbounds": [
    {
      "port": 8443,
      "protocol": "vless",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless"},
        "security": "reality",
        "realitySettings": {"show": false, "dest": "www.microsoft.com:443", "xver": 0, "serverNames": ["www.microsoft.com"], "privateKey": "", "publicKey": "", "shortIds": [""]}
      }
    },
    {
      "port": 2087,
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess"},
        "security": "reality",
        "realitySettings": {"show": false, "dest": "www.microsoft.com:443", "xver": 0, "serverNames": ["www.microsoft.com"], "privateKey": "", "publicKey": "", "shortIds": [""]}
      }
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan"},
        "security": "reality",
        "realitySettings": {"show": false, "dest": "www.microsoft.com:443", "xver": 0, "serverNames": ["www.microsoft.com"], "privateKey": "", "publicKey": "", "shortIds": [""]}
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
        # Generate Reality keys once
        KEYS=$("$BIN_DIR/xray" x25519)
        PRIVATE=$(echo "$KEYS" | grep Private | awk '{print $3}')
        PUBLIC=$(echo "$KEYS" | grep Public | awk '{print $3}')
        for i in 0 1 2; do
            jq --arg pk "$PRIVATE" --arg pub "$PUBLIC" \
               ".inbounds[$i].streamSettings.realitySettings.privateKey = \$pk | .inbounds[$i].streamSettings.realitySettings.publicKey = \$pub" \
               "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
        done
    fi
    cat >/etc/systemd/system/jay-tunnel.service <<EOF
[Unit]
Description=Jay Tunnel (Xray) Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/xray run -c $CONFIG_JSON
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now jay-tunnel
    echo "[OK] Xray Core installed."
}

install_nginx() {
    echo "[*] Installing Nginx..."
    apt-get install -y nginx >/dev/null 2>&1 &
    spinner $! "Installing Nginx..."
    systemctl enable --now nginx
    if [[ ! -f /etc/nginx/sites-available/jay_tunnel ]]; then
        cat >/etc/nginx/sites-available/jay_tunnel <<'EOF'
server {
    listen 443 ssl http2 reuseport;
    server_name _;

    ssl_certificate $INSTALL_DIR/jay-tunnel.crt;
    ssl_certificate_key $INSTALL_DIR/jay-tunnel.key;

    location /vless { proxy_pass http://127.0.0.1:8443; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /vmess { proxy_pass http://127.0.0.1:2087; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
    location /trojan { proxy_pass http://127.0.0.1:2083; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_set_header Host $host; }
}
EOF
        sed -i "s|\$INSTALL_DIR|$INSTALL_DIR|g" /etc/nginx/sites-available/jay_tunnel
        ln -sf /etc/nginx/sites-available/jay_tunnel /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi
    nginx -t && systemctl reload nginx
    echo "[OK] Nginx installed and configured."
}

configure_domain_ssl() {
    read -rp "Masukkan domain anda (A record ke IP server): " DOMAIN
    echo "$DOMAIN" > "$DOMAIN_FILE"
    curl https://get.acme.sh | sh -s email=admin@$DOMAIN >/dev/null 2>&1
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    WEBROOT="/var/www/html"
    mkdir -p "$WEBROOT"
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$INSTALL_DIR/jay-tunnel.key" \
        --fullchain-file "$INSTALL_DIR/jay-tunnel.crt"
    chmod 600 "$INSTALL_DIR/"*.{key,crt}
    # Update Nginx server_name
    sed -i "s/server_name .*;$/server_name $DOMAIN;/" /etc/nginx/sites-available/jay_tunnel
    nginx -t && systemctl reload nginx
    echo "[OK] SSL issued for $DOMAIN."
}

setup_panel_py() {
    echo "[*] Downloading panel.py Telegram Bot..."
    curl -sSL "$PANEL_PY_URL" -o "$PANEL_PY"
    chmod +x "$PANEL_PY"
    if ! grep -q 'JAYTUNNEL_BOT_TOKEN' /etc/environment; then
        read -rp "Masukkan TOKEN bot Telegram: " BOT_TOKEN
        echo "JAYTUNNEL_BOT_TOKEN=\"$BOT_TOKEN\"" >> /etc/environment
        source /etc/environment
    fi
    echo "Masukkan user ID Telegram admin (pisah enter, kosong selesai):"
    > "$INSTALL_DIR/telegram_admins"
    while true; do
        read -rp "User ID: " uid
        [[ -z "$uid" ]] && break
        echo "$uid" >> "$INSTALL_DIR/telegram_admins"
    done
    cat >/etc/systemd/system/jay-tunnel-panel.service <<EOF
[Unit]
Description=Jay Tunnel Telegram Panel
After=network.target

[Service]
Environment=JAYTUNNEL_BOT_TOKEN=$JAYTUNNEL_BOT_TOKEN
ExecStart=/usr/bin/python3 $PANEL_PY
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now jay-tunnel-panel
    echo "[OK] Bot Telegram aktif!"
}

send_telegram() {
    local msg="$1"
    if [[ -n "${JAYTUNNEL_BOT_TOKEN:-}" && -f "$INSTALL_DIR/telegram_admins" ]]; then
        for admin in $(cat "$INSTALL_DIR/telegram_admins"); do
            curl -s -X POST "https://api.telegram.org/bot$JAYTUNNEL_BOT_TOKEN/sendMessage" \
                -d chat_id="$admin" -d text="$msg" -d parse_mode="HTML" >/dev/null
        done
    fi
}

add_user_ssh() {
    read -rp "Username: " username
    read -rsp "Password: " password; echo
    read -rp "Masa aktif (hari): " days
    if id "$username" &>/dev/null; then echo "User sudah ada!"; return; fi
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    chage -E $(date -d "+$days days" +%Y-%m-%d) "$username"
    exp=$(date -d "+$days days" +%Y-%m-%d)
    ip=$(curl -s icanhazip.com)
    msg="SSH Created
Host: $ip
Username: $username
Password: $password
Exp: $exp"
    echo "$msg"
    [[ -f "$AUTO_NOTIFY_FILE" ]] && send_telegram "$msg"
}

add_user_vless() {
    read -rp "Username: " username
    read -rp "Masa aktif (hari): " days
    uuid=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg id "$uuid" --arg name "$username" --arg exp "$exp" \
       '.inbounds[0].settings.clients += [{"id":$id,"email":$name,"exp":$exp,"flow":"xtls-rprx-vision"}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    public=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey' "$CONFIG_JSON")
    short=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$CONFIG_JSON" | head -c 8 || echo "a1b2c3")
    vless_link="vless://$uuid@$domain:443?security=reality&encryption=none&pbk=$public&headerType=none&fp=chrome&type=ws&path=/vless&sni=$domain&sid=$short#$username"
    msg="VLESS Reality
Username: $username
Host: $domain
Port: 443
Exp: $exp
Link: $vless_link"
    echo "$msg"
    [[ -f "$AUTO_NOTIFY_FILE" ]] && send_telegram "$msg"
}

add_user_vmess() {
    read -rp "Username: " username
    read -rp "Masa aktif (hari): " days
    uuid=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg id "$uuid" --arg name "$username" --arg exp "$exp" \
       '.inbounds[1].settings.clients += [{"id":$id,"email":$name,"exp":$exp,"alterId":0}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    public=$(jq -r '.inbounds[1].streamSettings.realitySettings.publicKey' "$CONFIG_JSON")
    short=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds[0]' "$CONFIG_JSON" | head -c 8 || echo "a1b2c3")
    vmess_json="{\"v\":\"2\",\"ps\":\"$username\",\"add\":\"$domain\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"/vmess\",\"tls\":\"reality\",\"sni\":\"$domain\",\"fp\":\"chrome\",\"alpn\":\"h2\",\"pbk\":\"$public\",\"sid\":\"$short\"}"
    vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
    msg="VMESS Reality
Username: $username
Host: $domain
Port: 443
Exp: $exp
Link: $vmess_link"
    echo "$msg"
    [[ -f "$AUTO_NOTIFY_FILE" ]] && send_telegram "$msg"
}

add_user_trojan() {
    read -rp "Username: " username
    read -rp "Masa aktif (hari): " days
    password=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg pass "$password" --arg name "$username" --arg exp "$exp" \
       '.inbounds[2].settings.clients += [{"password":$pass,"email":$name,"exp":$exp}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    public=$(jq -r '.inbounds[2].streamSettings.realitySettings.publicKey' "$CONFIG_JSON")
    short=$(jq -r '.inbounds[2].streamSettings.realitySettings.shortIds[0]' "$CONFIG_JSON" | head -c 8 || echo "a1b2c3")
    trojan_link="trojan://$password@$domain:443?security=reality&pbk=$public&fp=chrome&type=ws&path=/trojan&sni=$domain&sid=$short#$username"
    msg="TROJAN Reality
Username: $username
Password: $password
Host: $domain
Port: 443
Exp: $exp
Link: $trojan_link"
    echo "$msg"
    [[ -f "$AUTO_NOTIFY_FILE" ]] && send_telegram "$msg"
}

list_users() {
    echo "=== XRAY USERS ==="
    for idx in 0 1 2; do
        protocol=$(jq -r ".inbounds[$idx].protocol" "$CONFIG_JSON")
        jq -r ".inbounds[$idx].settings.clients[]? | \"$protocol: \\(.email) Exp: \\(.exp)\"" "$CONFIG_JSON" 2>/dev/null || true
    done
    echo "=== SSH USERS ==="
    awk -F: '$3>=1000 && $1!="nobody" {print $1 " Exp: " $(chage -l $1 | grep "Account expires" | awk -F: "{print $2}" | xargs)}' /etc/passwd
}

restart_xray() {
    systemctl restart jay-tunnel
    echo "Xray restarted."
}

update_xray() {
    install_xray_core
    echo "Xray Core updated."
}

test_telegram() {
    send_telegram "Test Notification from Jay Tunnel Panel"
    echo "Test sent."
}

toggle_auto_notify() {
    if [[ -f "$AUTO_NOTIFY_FILE" ]]; then
        rm "$AUTO_NOTIFY_FILE"
        echo "Auto notification disabled."
    else
        touch "$AUTO_NOTIFY_FILE"
        echo "Auto notification enabled."
    fi
}

domain_config() {
    configure_domain_ssl
}

cloudflare_dns() {
    read -rp "Cloudflare API Token: " cf_token
    read -rp "Zone ID: " zone_id
    read -rp "Subdomain: " sub
    ip=$(curl -s icanhazip.com)
    curl -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $cf_token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$sub\",\"content\":\"$ip\",\"ttl\":120,\"proxied\":true}"
    echo "DNS record created/updated."
}

duckdns_setup() {
    read -rp "DuckDNS Token: " token
    read -rp "Subdomain: " sub
    echo "url=\"https://www.duckdns.org/update?domains=$sub&token=$token&ip=\"" | curl -k -o /dev/null
    (crontab -l 2>/dev/null; echo "*/5 * * * * curl -k -s \"https://www.duckdns.org/update?domains=$sub&token=$token&ip=\"") | crontab -
    echo "DuckDNS updated & cron set."
}

dns_changer() {
    echo "Pilih DNS:"
    echo "1) Cloudflare (1.1.1.1)"
    echo "2) Google (8.8.8.8)"
    echo "3) Quad9 (9.9.9.9)"
    read -p "Pilih: " dns_choice
    case $dns_choice in
        1) dns1="1.1.1.1"; dns2="1.0.0.1" ;;
        2) dns1="8.8.8.8"; dns2="8.8.4.4" ;;
        3) dns1="9.9.9.9"; dns2="149.112.112.112" ;;
        *) echo "Invalid"; return ;;
    esac
    cat > /etc/resolv.conf <<EOF
nameserver $dns1
nameserver $dns2
EOF
    echo "DNS changed to $dns1 / $dns2"
}

show_ports() {
    ss -tuln
    systemctl status jay-tunnel nginx ufw --no-pager
}

nginx_control() {
    systemctl status nginx --no-pager
    read -p "Restart Nginx? (y/n): " yn
    [[ $yn =~ ^[Yy]$ ]] && systemctl restart nginx && echo "Nginx restarted."
}

renew_ssl() {
    domain=$(cat "$DOMAIN_FILE")
    ~/.acme.sh/acme.sh --renew -d "$domain" --force
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file "$INSTALL_DIR/jay-tunnel.key" \
        --fullchain-file "$INSTALL_DIR/jay-tunnel.crt"
    systemctl reload nginx
    echo "SSL renewed."
}

custom_ssl() {
    read -rp "Path to .crt: " crt
    read -rp "Path to .key: " key
    cp "$crt" "$INSTALL_DIR/jay-tunnel.crt"
    cp "$key" "$INSTALL_DIR/jay-tunnel.key"
    chmod 600 "$INSTALL_DIR/"*.{crt,key}
    systemctl reload nginx
    echo "Custom SSL installed."
}

firewall_control() {
    echo "1) Enable UFW"
    echo "2) Disable UFW"
    read -p "Pilih: " fc
    case $fc in
        1) ufw --force enable; ufw reload ;;
        2) ufw disable ;;
    esac
    echo "Firewall updated."
}

speedtest_cli() {
    speedtest-cli --simple
}

clear_logs() {
    > "$ERROR_LOG"
    journalctl --vacuum-time=2weeks
    rm -rf /var/log/jay-tunnel/*
    echo "Logs cleared."
}

backup_restore() {
    echo "1) Backup"
    echo "2) Restore"
    read -p "Pilih: " br
    if [[ $br -eq 1 ]]; then
        backup_file="$BACKUP_DIR/backup_$(date +%Y%m%d).tar.gz"
        tar -czf "$backup_file" "$INSTALL_DIR" /etc/nginx/sites-available/jay_tunnel
        echo "Backup saved to $backup_file"
    else
        read -rp "Path to backup file: " restore_file
        tar -xzf "$restore_file" -C /
        systemctl restart jay-tunnel nginx
        echo "Restored."
    fi
}

change_motd() {
    read -rp "New MOTD text: " motd
    echo "$motd" > /etc/motd
    echo "MOTD updated."
}

custom_banner() {
    read -rp "Path to banner file: " banner
    mkdir -p /banner
    cp "$banner" /banner/banner.txt
    echo "Banner set. Clients can view with cat /banner/banner.txt"
}

set_auto_reboot() {
    echo "Set auto reboot every X hours (e.g., 24):"
    read -p "Hours: " hours
    (crontab -l 2>/dev/null; echo "0 */$hours * * * reboot") | crontab -
    echo "Auto reboot set."
}

reboot_server() {
    read -p "Reboot now? (y/n): " yn
    [[ $yn =~ ^[Yy]$ ]] && reboot
}

restart_services_menu() {
    echo "1) Restart Xray"
    echo "2) Restart Nginx"
    echo "3) Restart Panel Bot"
    echo "4) Restart All"
    read -p "Pilih: " rs
    case $rs in
        1) systemctl restart jay-tunnel ;;
        2) systemctl restart nginx ;;
        3) systemctl restart jay-tunnel-panel ;;
        4) systemctl restart jay-tunnel nginx jay-tunnel-panel ;;
    esac
    echo "Services restarted."
}

remove_user_menu() {
    read -rp "Username to remove: " username
    # SSH
    if id "$username" &>/dev/null; then userdel -r "$username"; echo "SSH $username removed."; fi
    # XRAY
    for idx in 0 1 2; do
        jq "(.inbounds[$idx].settings.clients) |= [ .[] | select(.email != \"$username\") ]" "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    done
    systemctl restart jay-tunnel
    echo "XRAY $username removed."
}

remove_expired() {
    today=$(date +%Y-%m-%d)
    for idx in 0 1 2; do
        jq --arg t "$today" "(.inbounds[$idx].settings.clients) |= [ .[] | select(.exp > \$t) ]" "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    done
    systemctl restart jay-tunnel
    for u in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
        exp=$(chage -l "$u" | grep "Account expires" | awk -F: '{print $2}' | xargs)
        if [[ "$exp" != "never" ]] && [[ $(date -d "$exp" +%s 2>/dev/null || echo 0) -lt $(date +%s) ]]; then
            userdel -r "$u"
        fi
    done
    echo "Expired removed."
}

menu_loop() {
    while true; do
        print_menu
        read -p "" choice
        case $choice in
            0) echo "Bye!"; exit 0 ;;
            1) add_user_ssh; read -p "Press Enter..." ;;
            2) add_user_vless; read -p "Press Enter..." ;;
            3) add_user_vmess; read -p "Press Enter..." ;;
            4) add_user_trojan; read -p "Press Enter..." ;;
            5) list_users; read -p "Press Enter..." ;;
            6) restart_xray; read -p "Press Enter..." ;;
            7) update_xray; read -p "Press Enter..." ;;
            8) setup_panel_py; read -p "Press Enter..." ;;
            9) test_telegram; read -p "Press Enter..." ;;
            10) toggle_auto_notify; read -p "Press Enter..." ;;
            11) domain_config; read -p "Press Enter..." ;;
            12) cloudflare_dns; read -p "Press Enter..." ;;
            13) duckdns_setup; read -p "Press Enter..." ;;
            14) dns_changer; read -p "Press Enter..." ;;
            15) show_ports; read -p "Press Enter..." ;;
            16) nginx_control; read -p "Press Enter..." ;;
            17) renew_ssl; read -p "Press Enter..." ;;
            18) custom_ssl; read -p "Press Enter..." ;;
            19) firewall_control; read -p "Press Enter..." ;;
            20) speedtest_cli; read -p "Press Enter..." ;;
            21) clear_logs; read -p "Press Enter..." ;;
            22) backup_restore; read -p "Press Enter..." ;;
            23) change_motd; read -p "Press Enter..." ;;
            24) custom_banner; read -p "Press Enter..." ;;
            25) htop; read -p "Press Enter to exit htop..." ;;
            26) set_auto_reboot; read -p "Press Enter..." ;;
            27) reboot_server ;;
            28) restart_services_menu; read -p "Press Enter..." ;;
            *) echo "Invalid choice."; sleep 1 ;;
        esac
        # Auto remove expired on every loop
        remove_expired >/dev/null 2>&1
    done
}

main() {
    if [[ $# -gt 0 ]]; then
        # Old CLI mode still works
        case $1 in
            add_user_vless) shift; add_user_vless "$@"; exit 0 ;;
            add_user_vmess) shift; add_user_vmess "$@"; exit 0 ;;
            add_user_trojan) shift; add_user_trojan "$@"; exit 0 ;;
            add_user_ssh) shift; add_user_ssh "$@"; exit 0 ;;
            remove_user) shift; remove_user_menu "$@"; exit 0 ;;
            list_users) list_users; exit 0 ;;
            remove_expired) remove_expired; exit 0 ;;
            info_server) get_system_info; info_server; exit 0 ;;
        esac
    fi

    if [[ ! -f "$FLAG_FILE" ]]; then
        init_system
        setup_firewall
        install_xray_core
        install_nginx
        configure_domain_ssl
        setup_panel_py
        touch "$FLAG_FILE"
        echo "=== INSTALASI SELESAI ==="
        echo "Gunakan 'jay-tunnel' untuk menu interaktif."
    fi

    # Copy script to BIN for menu access
    cp "$0" "$BIN_DIR/jay-tunnel"
    chmod +x "$BIN_DIR/jay-tunnel"

    # If run without args and installed, start menu
    [[ -f "$FLAG_FILE" ]] && menu_loop

    echo "Bot Telegram Panel aktif!"
}

info_server() {
    echo "Hostname: $(hostname)"
    echo "IP: $(curl -s icanhazip.com)"
    echo "Domain: $(cat $DOMAIN_FILE 2>/dev/null || echo 'Not set')"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Uptime: $(uptime -p)"
}

main "$@"
