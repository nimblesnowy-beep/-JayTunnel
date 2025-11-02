#!/usr/bin/env bash
# ⚡ Jay Tunnel - XRAY REALITY + NGINX + SSL + TELEGRAM AUTO-INSTALLER
# Compatible: Ubuntu 22.04+, Debian 11+
# Author: YourName <your_github>
# Repo: https://github.com/nimblesnowy-beep/-JayTunnel
# Versi: 1.0

set -Eeuo pipefail

INSTALL_DIR="/etc/jay-tunnel"
BIN_DIR="/usr/local/bin"
LOG_DIR="/var/log/jay-tunnel"
FLAG_FILE="$INSTALL_DIR/.installed"
DOMAIN_FILE="$INSTALL_DIR/domain"
ENV_FILE="$INSTALL_DIR/.env"
ERROR_LOG="$LOG_DIR/installer_error.log"
SCRIPT_REPO="https://github.com/nimblesnowy-beep/-JayTunnel.git"

# --- Helper Functions ---
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

load_env() {
    [[ -f "$ENV_FILE" ]] && export $(grep -v '^#' "$ENV_FILE" | xargs)
}
set_env_var() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}='${value}'|" "$ENV_FILE"
    else
        echo "${key}='${value}'" >> "$ENV_FILE"
    fi
    export $key="$value"
}

init_system() {
    echo "[*] Updating system & installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y && apt-get upgrade -y &
    spinner "Updating system..."
    apt-get install -y curl wget jq socat unzip tar git lsb-release cron net-tools \
        gnupg2 ca-certificates python3 python3-pip htop bc ntpdate ufw >/dev/null 2>&1 &
    spinner "Installing dependencies..."
    pip3 install speedtest-cli --upgrade >/dev/null 2>&1 || true
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
    LATEST_URL=$(curl -s "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | jq -r '.assets[] | select(.name|test("Xray-linux-64.zip")) | .browser_download_url')
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
    # Default config (minimal, port 8443, proxy by nginx)
    if [[ ! -f "$INSTALL_DIR/config.json" ]]; then
cat > "$INSTALL_DIR/config.json" <<EOF
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
        "network": "tcp",
        "realitySettings": {}
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
    # Systemd service
    cat >/etc/systemd/system/jay-tunnel.service <<EOF
[Unit]
Description=Jay Tunnel (Xray) Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=$BIN_DIR/xray run -c $INSTALL_DIR/config.json
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

    location /banner {
        default_type text/plain;
        alias $INSTALL_DIR/banner.txt;
    }
    location /message {
        default_type text/plain;
        alias $INSTALL_DIR/message.txt;
    }
    location / {
        proxy_pass http://127.0.0.1:8443;
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

configure_domain() {
    read -rp "Masukkan domain anda: " DOMAIN
    echo "$DOMAIN" > "$DOMAIN_FILE"
    set_env_var "JAY_DOMAIN" "$DOMAIN"
    echo "[*] Installing acme.sh for SSL..."
    curl https://get.acme.sh | sh >/dev/null 2>&1 &
    spinner "Installing acme.sh..."
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" --force &
    spinner "Issuing SSL cert..."
    mkdir -p "$INSTALL_DIR"
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$INSTALL_DIR/jay-tunnel.key" \
        --fullchain-file "$INSTALL_DIR/jay-tunnel.crt"
    chmod 600 "$INSTALL_DIR/jay-tunnel.key" "$INSTALL_DIR/jay-tunnel.crt"
    echo "[OK] SSL issued and installed for $DOMAIN."
}

telegram_bot_setup() {
    read -rp "Masukkan Telegram Bot Token: " TG_TOKEN
    read -rp "Masukkan Telegram Chat ID: " TG_CHATID
    set_env_var "TG_TOKEN" "$TG_TOKEN"
    set_env_var "TG_CHATID" "$TG_CHATID"
    echo "[*] Telegram credentials saved to $ENV_FILE. Testing notification..."
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d chat_id="$TG_CHATID" -d text="✅ Notifikasi bot Telegram Jay Tunnel berhasil terhubung!" >/dev/null
    echo "[OK] Telegram bot setup complete."
}

automation_tasks() {
    echo "[*] Setting up automation tasks (backup, reboot, SSL renew)..."
    cat >/etc/cron.d/jay-tunnel-backup <<EOF
0 3 * * * root tar czf /etc/jay-tunnel/backup-\$(date +\%F).tar.gz -C /etc jay-tunnel
EOF
    cat >/etc/cron.d/acme_renew <<EOF
0 4 * * * root ~/.acme.sh/acme.sh --renew-all --force --ecc && systemctl reload nginx && systemctl restart jay-tunnel
EOF
    echo "[OK] Automation tasks set."
}

update_script() {
    echo "[*] Checking for script updates from GitHub..."
    if [[ ! -d "/opt/jay-tunnel" ]]; then
        git clone "$SCRIPT_REPO" /opt/jay-tunnel
    else
        cd /opt/jay-tunnel && git pull
    fi
    cp /opt/jay-tunnel/install.sh /usr/local/bin/jay-tunnel-installer.sh
    chmod +x /usr/local/bin/jay-tunnel-installer.sh
    echo "[OK] Script updated."
}

change_banner() {
    echo "───────────── CHANGE SERVER BANNER / MOTD ─────────────"
    echo "1) Edit banner (manual input)"
    echo "2) Import banner from file"
    echo "3) Reset to default"
    echo "4) View current banner"
    echo "5) Kembali"
    read -rp "Pilih [1-5]: " ch
    case $ch in
        1)
            echo "Masukkan banner baru (akhiri dengan CTRL+D):"
            cat > /etc/motd
            echo "Banner berhasil diupdate!"
            ;;
        2)
            read -rp "Masukkan path file banner (misal: /root/banner.txt): " BFILE
            if [[ -f "$BFILE" ]]; then
                cp "$BFILE" /etc/motd
                echo "Banner berhasil diimport!"
            else
                echo "File tidak ditemukan!"
            fi
            ;;
        3)
            echo "Welcome to Jay Tunnel!" > /etc/motd
            echo "Banner direset ke default."
            ;;
        4)
            echo "───────── CURRENT BANNER ─────────"
            cat /etc/motd
            echo "───────── END BANNER ─────────"
            ;;
        5)
            return
            ;;
        *)
            echo "Pilihan tidak valid!"; sleep 1
            ;;
    esac
}

set_costume_client_banner() {
    BANNER_PATH="$INSTALL_DIR/banner.txt"
    if [[ ! -f "$BANNER_PATH" ]]; then
        echo "⚡ Jay Tunnel VPN Server" > "$BANNER_PATH"
    fi
    echo "───────────── SET CLIENT COSTUME BANNER (/banner) ─────────────"
    echo "Banner ini akan tampil jika client mengakses path /banner pada server (Nginx/WS/HTTP)."
    echo "Masukkan teks banner (akhiri dengan CTRL+D):"
    cat > "$BANNER_PATH"
    nginx -t && systemctl reload nginx
    echo "Banner berhasil disimpan. Akses https://$(cat $DOMAIN_FILE)/banner untuk melihat banner."
}

set_costume_client_message() {
    MESSAGE_PATH="$INSTALL_DIR/message.txt"
    if [[ ! -f "$MESSAGE_PATH" ]]; then
        echo "Selamat datang di ⚡ Jay Tunnel!" > "$MESSAGE_PATH"
    fi
    echo "───────────── SET CLIENT COSTUME MESSAGE (/message) ─────────────"
    echo "Pesan ini dapat diambil client pada path /message di server (Nginx/WS/HTTP)."
    echo "Masukkan pesan custom (akhiri dengan CTRL+D):"
    cat > "$MESSAGE_PATH"
    nginx -t && systemctl reload nginx
    echo "Pesan berhasil disimpan. Akses https://$(cat $DOMAIN_FILE)/message untuk melihat pesan."
}

backup_restore_config() {
    echo "1) Backup konfigurasi"
    echo "2) Restore konfigurasi"
    read -rp "Pilih [1-2]: " c
    if [[ $c == 1 ]]; then
        tar czf "/root/jay-tunnel-backup-$(date +%F).tar.gz" -C /etc jay-tunnel
        echo "Backup tersimpan di /root/jay-tunnel-backup-$(date +%F).tar.gz"
    elif [[ $c == 2 ]]; then
        read -rp "Path file backup: " bfile
        [[ -f "$bfile" ]] && tar xzf "$bfile" -C /etc
        echo "Restore selesai, silakan restart service jika perlu."
    fi
}

add_user_ssh() { echo "(Stub) Tambah User SSH"; }
add_user_vless() { echo "(Stub) Tambah User VLESS"; }
add_user_vmess() { echo "(Stub) Tambah User VMESS"; }
add_user_trojan() { echo "(Stub) Tambah User TROJAN"; }
view_active_users() { echo "(Stub) Lihat User Aktif"; }
test_telegram_notification() { 
    load_env
    [[ -z "${TG_TOKEN:-}" || -z "${TG_CHATID:-}" ]] && { echo "Config tidak ditemukan!"; return; }
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d chat_id="$TG_CHATID" -d text="🧩 Test notifikasi dari Jay Tunnel" >/dev/null && echo "Terkirim!"
}
toggle_auto_notification() { echo "(Stub) Toggle Auto Notif"; }
cloudflare_dns_setup() { echo "(Stub) Cloudflare DNS Setup"; }
duckdns_setup() { echo "(Stub) DuckDNS Setup"; }
dns_changer() { echo "(Stub) Ubah DNS"; }
show_port_service_status() { ss -tulnp | less; }
check_nginx_status() { systemctl status nginx; }
renew_ssl() { ~/.acme.sh/acme.sh --renew-all --force --ecc && systemctl reload nginx && systemctl restart jay-tunnel; }
install_custom_ssl() { echo "(Stub) Install Custom SSL"; }
firewall_control() { echo "(Stub) Firewall Control"; }
speedtest_cli() { speedtest-cli; }
clear_logs_cache() { rm -rf $LOG_DIR/*; echo "Logs cleared."; }
change_motd() { nano /etc/motd; }
set_auto_reboot() { echo "(Stub) Set Auto Reboot"; }
restart_services_menu() { systemctl restart jay-tunnel nginx; echo "Services restarted."; }

menu_interactive() {
    load_env
    DOMAIN_SHOW=$(cat $DOMAIN_FILE 2>/dev/null || echo "Not Set")
    XRAY_STATUS=$(systemctl is-active jay-tunnel | sed 's/active/🟢 RUNNING/;s/inactive/🔴 STOPPED/')
    NGINX_STATUS=$(systemctl is-active nginx | sed 's/active/🟢 RUNNING/;s/inactive/🔴 STOPPED/')
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    MEMORY=$(free -m | awk '/Mem:/ {printf "%sMB / %sMB", $3, $2}')
    UPTIME=$(uptime -p | sed 's/up //')
    IP_ADDR=$(curl -s ipv4.icanhazip.com)
    OS_DESC=$(lsb_release -d | cut -f2)
    TIME_NOW=$(date '+%d %b %Y | %H:%M:%S')

    cat <<EOF
╔══════════════════════════════════════════════════════════════╗
║                        ⚡ JAY TUNNEL                         ║
╠══════════════════════════════════════════════════════════════╣
║ 🖥️  Hostname : $(hostname)
║ 🌐  Domain   : $DOMAIN_SHOW
║ 🏠  IP Addr  : $IP_ADDR
║ ⚙️  OS       : $OS_DESC
║ 🧠  CPU Load : $CPU_LOAD%
║ 💾  Memory   : $MEMORY
║ ⏱️  Uptime   : $UPTIME
║ 🔌  JayTunnel: $XRAY_STATUS
║ 🌍  Nginx    : $NGINX_STATUS
║ 🕒  Time     : $TIME_NOW
╚══════════════════════════════════════════════════════════════╝

📦  XRAY MANAGEMENT
───────────────────────────────────────────────────────────────
 [1]  Add User SSH
 [2]  Add User VLESS (Reality)
 [3]  Add User VMESS (Reality)
 [4]  Add User TROJAN (Reality)
 [5]  View Active Users
 [6]  Restart JayTunnel Service
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
[25]  Set Costume Client Message
[26]  Check Server Resource (htop)
[27]  Set Auto Reboot (Cron)
[28]  Reboot Server

⚙️  SERVICE CONTROL
───────────────────────────────────────────────────────────────
[29]  Restart Services Menu

───────────────────────────────────────────────────────────────
[0]   Exit

───────────────────────────────────────────────────────────────
Pilih menu [0-29]:
EOF

    read -rp ">> " menu
    case $menu in
        1) add_user_ssh ;;
        2) add_user_vless ;;
        3) add_user_vmess ;;
        4) add_user_trojan ;;
        5) view_active_users ;;
        6) systemctl restart jay-tunnel && echo "JayTunnel restarted." ;;
        7) install_xray_core ;;
        8) telegram_bot_setup ;;
        9) test_telegram_notification ;;
        10) toggle_auto_notification ;;
        11) configure_domain ;;
        12) cloudflare_dns_setup ;;
        13) duckdns_setup ;;
        14) dns_changer ;;
        15) show_port_service_status ;;
        16) check_nginx_status ;;
        17) renew_ssl ;;
        18) install_custom_ssl ;;
        19) firewall_control ;;
        20) speedtest_cli ;;
        21) clear_logs_cache ;;
        22) backup_restore_config ;;
        23) change_banner ;;
        24) set_costume_client_banner ;;
        25) set_costume_client_message ;;
        26) htop ;;
        27) set_auto_reboot ;;
        28) reboot ;;
        29) restart_services_menu ;;
        0) exit 0 ;;
        *) echo "Menu tidak valid!"; sleep 1 ;;
    esac
    read -n1 -rp "Tekan [Enter] untuk kembali ke menu..." _
    menu_interactive
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "Run as root!" && exit 1
    fi
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$LOG_DIR"
    touch "$ERROR_LOG"
    if [[ ! -f "$FLAG_FILE" ]]; then
        init_system
        setup_firewall
        install_xray_core
        install_nginx
        configure_domain
        automation_tasks
        touch "$FLAG_FILE"
    fi
    update_script
    menu_interactive
}

main "$@"
