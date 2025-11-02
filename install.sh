#!/usr/bin/env bash
# Jay Tunnel Production Installer - XRAY, SSH, Telegram Panel, WebSocket, gRPC, SSL, All Features
# https://github.com/nimblesnowy-beep/-JayTunnel

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

# Helper
error_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$ERROR_LOG" >&2
}
trap 'error_log "Error on line $LINENO: $BASH_COMMAND"' ERR

spinner() {
    local pid=$!
    local spin='-\|/'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r[%c] $1" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r    \r"
}

init_system() {
    echo "[*] Updating system & installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y &
    spinner "Updating system..."
    apt-get install -y curl wget jq socat unzip tar git lsb-release cron net-tools \
        gnupg2 ca-certificates python3 python3-pip htop bc ntpdate ufw nginx fail2ban \
        python3-telegram python3-pip >/dev/null 2>&1 &
    spinner "Installing dependencies..."
    pip3 install speedtest-cli python-telegram-bot --upgrade >/dev/null 2>&1 || true
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$LOG_DIR"
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
    LATEST_URL=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.assets[] | select(.name=="Xray-linux-64.zip") | .browser_download_url' | head -n1)
    if [[ -z "$LATEST_URL" ]]; then
        error_log "Failed to fetch Xray release."
        return 1
    fi
    wget -O /tmp/xray.zip "$LATEST_URL" &
    spinner "Downloading Xray Core..."
    unzip -o /tmp/xray.zip -d /tmp/xray &
    spinner "Extracting Xray..."
    install -m 755 /tmp/xray/xray "$BIN_DIR/xray"
    cp /tmp/xray/geosite.dat /tmp/xray/geoip.dat "$INSTALL_DIR/" 2>/dev/null || true
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
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" },
        "security": "tls",
        "realitySettings": {}
      }
    },
    {
      "port": 2087,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" },
        "security": "tls"
      }
    },
    {
      "port": 2083,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan" },
        "security": "tls"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
    fi
    cat >/etc/systemd/system/jay-tunnel.service <<EOF
[Unit]
Description=Jay Tunnel (Xray) Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=$BIN_DIR/xray run -c $CONFIG_JSON
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable jay-tunnel
    systemctl restart jay-tunnel
    echo "[OK] Xray Core installed."
}

install_nginx() {
    echo "[*] Installing Nginx..."
    apt-get install -y nginx >/dev/null 2>&1 &
    spinner "Installing Nginx..."
    systemctl enable nginx
    systemctl start nginx
    if [[ ! -f /etc/nginx/sites-available/jay_tunnel ]]; then
        cat >/etc/nginx/sites-available/jay_tunnel <<EOF
server {
    listen 443 ssl http2;
    server_name $(cat $DOMAIN_FILE 2>/dev/null || echo "your.domain.com");

    ssl_certificate $INSTALL_DIR/jay-tunnel.crt;
    ssl_certificate_key $INSTALL_DIR/jay-tunnel.key;

    location /vless {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    location /vmess {
        proxy_pass http://127.0.0.1:2087;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
    location /trojan {
        proxy_pass http://127.0.0.1:2083;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF
        ln -sf /etc/nginx/sites-available/jay_tunnel /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi
    nginx -t && systemctl reload nginx
    echo "[OK] Nginx installed and configured."
}

configure_domain_ssl() {
    read -rp "Masukkan domain anda (A record ke IP server): " DOMAIN
    echo "$DOMAIN" > "$DOMAIN_FILE"
    curl https://get.acme.sh | sh >/dev/null 2>&1
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force
    mkdir -p "$INSTALL_DIR"
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$INSTALL_DIR/jay-tunnel.key" \
        --fullchain-file "$INSTALL_DIR/jay-tunnel.crt"
    chmod 600 "$INSTALL_DIR/jay-tunnel.key" "$INSTALL_DIR/jay-tunnel.crt"
    echo "[OK] SSL issued and installed for $DOMAIN."
}

setup_panel_py() {
    echo "[*] Downloading panel.py Telegram Bot..."
    mkdir -p "$INSTALL_DIR"
    curl -sSL "$PANEL_PY_URL" -o "$PANEL_PY"
    chmod +x "$PANEL_PY"
    if ! grep -q 'JAYTUNNEL_BOT_TOKEN' /etc/environment 2>/dev/null; then
        read -rp "Masukkan TOKEN bot Telegram Jay Tunnel: " BOT_TOKEN
        echo "JAYTUNNEL_BOT_TOKEN=\"$BOT_TOKEN\"" >> /etc/environment
        export JAYTUNNEL_BOT_TOKEN="$BOT_TOKEN"
    fi
    echo "Masukkan user ID Telegram yang boleh akses bot (pisah baris): "
    > "$INSTALL_DIR/telegram_admins"
    while true; do
        read -rp "User ID (kosongkan jika selesai): " uid
        [[ -z "$uid" ]] && break
        echo "$uid" >> "$INSTALL_DIR/telegram_admins"
    done
    cat >/etc/systemd/system/jay-tunnel-panel.service <<EOF
[Unit]
Description=Jay Tunnel Telegram Panel Bot
After=network.target

[Service]
Type=simple
Environment=JAYTUNNEL_BOT_TOKEN=$BOT_TOKEN
ExecStart=/usr/bin/python3 $PANEL_PY
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable jay-tunnel-panel
    systemctl restart jay-tunnel-panel
    echo "[OK] panel.py Bot Telegram aktif!"
}

add_user_vless() {
    username="$1"
    days="$2"
    uuid=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg id "$uuid" --arg name "$username" --arg exp "$exp" \
       '.inbounds[0].settings.clients += [{"id":$id,"email":$name,"exp":$exp}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    vless_link="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&path=/vless#${username}"
    msg="Jay Tunnel VLESS
Username: $username
UUID: $uuid
Host: $domain
Port: 443
Expired: $exp

Config Link:
$vless_link"
    echo "$msg"
    if [[ -n "${JAYTUNNEL_BOT_TOKEN:-}" && -f "$INSTALL_DIR/telegram_admins" ]]; then
        for admin in $(cat "$INSTALL_DIR/telegram_admins"); do
            curl -s -X POST "https://api.telegram.org/bot$JAYTUNNEL_BOT_TOKEN/sendMessage" \
                 -d chat_id="$admin" \
                 --data-urlencode text="$msg" \
                 -d parse_mode="HTML" >/dev/null
        done
    fi
}

add_user_vmess() {
    username="$1"
    days="$2"
    uuid=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg id "$uuid" --arg name "$username" --arg exp "$exp" \
       '.inbounds[1].settings.clients += [{"id":$id,"email":$name,"exp":$exp}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    # Generate VMESS JSON config and base64
    vmess_json="{\"v\":\"2\",\"ps\":\"$username\",\"add\":\"$domain\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"/vmess\",\"tls\":\"tls\"}"
    vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
    msg="Jay Tunnel VMESS
Username: $username
UUID: $uuid
Host: $domain
Port: 443
Expired: $exp

Config Link:
$vmess_link"
    echo "$msg"
    if [[ -n "${JAYTUNNEL_BOT_TOKEN:-}" && -f "$INSTALL_DIR/telegram_admins" ]]; then
        for admin in $(cat "$INSTALL_DIR/telegram_admins"); do
            curl -s -X POST "https://api.telegram.org/bot$JAYTUNNEL_BOT_TOKEN/sendMessage" \
                 -d chat_id="$admin" \
                 --data-urlencode text="$msg" \
                 -d parse_mode="HTML" >/dev/null
        done
    fi
}

add_user_trojan() {
    username="$1"
    days="$2"
    password=$(cat /proc/sys/kernel/random/uuid)
    domain=$(cat "$DOMAIN_FILE")
    exp=$(date -d "+$days days" +%Y-%m-%d)
    jq --arg pass "$password" --arg name "$username" --arg exp "$exp" \
       '.inbounds[2].settings.clients += [{"password":$pass,"email":$name,"exp":$exp}]' \
       "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    systemctl restart jay-tunnel
    trojan_link="trojan://$password@$domain:443?security=tls&type=ws&path=/trojan#$username"
    msg="Jay Tunnel TROJAN
Username: $username
Password: $password
Host: $domain
Port: 443
Expired: $exp

Config Link:
$trojan_link"
    echo "$msg"
    if [[ -n "${JAYTUNNEL_BOT_TOKEN:-}" && -f "$INSTALL_DIR/telegram_admins" ]]; then
        for admin in $(cat "$INSTALL_DIR/telegram_admins"); do
            curl -s -X POST "https://api.telegram.org/bot$JAYTUNNEL_BOT_TOKEN/sendMessage" \
                 -d chat_id="$admin" \
                 --data-urlencode text="$msg" \
                 -d parse_mode="HTML" >/dev/null
        done
    fi
}

add_user_ssh() {
    username="$1"
    password="$2"
    days="$3"
    id "$username" &>/dev/null && { echo "User sudah ada!"; return; }
    useradd -m -s /bin/bash "$username"
    echo "$username:$password" | chpasswd
    chage -E $(date -d "+$days days" +%Y-%m-%d) "$username"
    expdate=$(chage -l "$username" | grep "Account expires" | cut -d: -f2)
    ip=$(curl -s icanhazip.com)
    msg="Jay Tunnel SSH
Host: $ip
Port: 22
Username: $username
Password: $password
Expired: $expdate"
    echo "$msg"
    if [[ -n "${JAYTUNNEL_BOT_TOKEN:-}" && -f "$INSTALL_DIR/telegram_admins" ]]; then
        for admin in $(cat "$INSTALL_DIR/telegram_admins"); do
            curl -s -X POST "https://api.telegram.org/bot$JAYTUNNEL_BOT_TOKEN/sendMessage" \
                 -d chat_id="$admin" \
                 --data-urlencode text="$msg" \
                 -d parse_mode="HTML" >/dev/null
        done
    fi
}

remove_user() {
    username="$1"
    # SSH
    if id "$username" &>/dev/null; then
        userdel -r "$username"
        echo "User SSH $username dihapus."
    fi
    # XRAY (hapus dari config.json)
    for idx in 0 1 2; do
      jq "(.inbounds[$idx].settings.clients) |= map(select(.email != \"$username\"))" \
        "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    done
    systemctl restart jay-tunnel
    echo "User XRAY $username dihapus."
}

list_users() {
    echo "XRAY:"
    for idx in 0 1 2; do
      jq -r ".inbounds[$idx].settings.clients[] | \"\(.email) (\(.id // .password)) Exp: \(.exp)\"" "$CONFIG_JSON" 2>/dev/null || true
    done
    echo "SSH:"
    awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd
}

remove_expired() {
    today=$(date +%Y-%m-%d)
    for idx in 0 1 2; do
      jq --arg today "$today" "(.inbounds[$idx].settings.clients) |= map(select(.exp > \$today))" \
        "$CONFIG_JSON" > "$CONFIG_JSON.tmp" && mv "$CONFIG_JSON.tmp" "$CONFIG_JSON"
    done
    systemctl restart jay-tunnel
    for user in $(awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd); do
        exp=$(chage -l "$user" | grep "Account expires" | awk -F: '{print $2}' | xargs)
        [[ "$exp" != "never" && "$(date -d "$exp" +%s)" -lt "$(date +%s)" ]] && userdel -r "$user"
    done
    echo "Expired users removed."
}

info_server() {
    echo "Hostname: $(hostname)"
    echo "IP: $(curl -s icanhazip.com)"
    echo "Domain: $(cat $DOMAIN_FILE)"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Uptime: $(uptime -p)"
}

main() {
    if [[ $# -gt 0 ]]; then
        case $1 in
            add_user_vless) shift; add_user_vless "$@"; exit 0 ;;
            add_user_vmess) shift; add_user_vmess "$@"; exit 0 ;;
            add_user_trojan) shift; add_user_trojan "$@"; exit 0 ;;
            add_user_ssh) shift; add_user_ssh "$@"; exit 0 ;;
            remove_user) shift; remove_user "$@"; exit 0 ;;
            list_users) list_users; exit 0 ;;
            remove_expired) remove_expired; exit 0 ;;
            info_server) info_server; exit 0 ;;
        esac
    fi
    if [[ ! -f "$FLAG_FILE" ]]; then
        init_system
        setup_firewall
        install_xray_core
        install_nginx
        configure_domain_ssl
        touch "$FLAG_FILE"
    fi
    setup_panel_py
    echo "=== INSTALASI SELESAI ==="
    echo "Bot Telegram Panel sudah aktif. Silakan cek Telegram Anda!"
}

main "$@"
