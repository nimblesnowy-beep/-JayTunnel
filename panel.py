import os
import subprocess
import secrets
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Updater,
    CommandHandler,
    CallbackQueryHandler,
    CallbackContext,
)

BOT_TOKEN = os.environ.get('JAYTUNNEL_BOT_TOKEN')
CONFIG_FILE = "/etc/jay-tunnel/telegram_admins"
BASH_SCRIPT = "/usr/local/bin/jay-tunnel-installer.sh"

def get_admin_ids():
    try:
        with open(CONFIG_FILE, "r") as f:
            return [int(line.strip()) for line in f if line.strip().isdigit()]
    except Exception:
        return []

def is_admin(user_id):
    return user_id in get_admin_ids()

def start(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    keyboard = [
        [InlineKeyboardButton("➕ Add VLESS", callback_data='add_vless'),
         InlineKeyboardButton("➕ Add VMESS", callback_data='add_vmess')],
        [InlineKeyboardButton("➕ Add TROJAN", callback_data='add_trojan'),
         InlineKeyboardButton("➕ Add SSH", callback_data='add_ssh')],
        [InlineKeyboardButton("➕ Add SOCKS5", callback_data='add_socks5'),
         InlineKeyboardButton("➕ Add SHADOWSOCKS", callback_data='add_ss')],
        [InlineKeyboardButton("❌ Remove User", callback_data='remove_user')],
        [InlineKeyboardButton("👥 List Users", callback_data='list_users')],
        [InlineKeyboardButton("🗑 Remove Expired", callback_data='remove_expired')],
        [InlineKeyboardButton("💾 Backup", callback_data='backup'),
         InlineKeyboardButton("♻️ Restore", callback_data='restore')],
        [InlineKeyboardButton("ℹ️ Info Server", callback_data='info_server')]
    ]
    update.message.reply_text(
        '⚡ Jay Tunnel Panel Menu:',
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

def handle_callback(update: Update, context: CallbackContext):
    query = update.callback_query
    user_id = query.from_user.id
    if not is_admin(user_id):
        query.answer("⛔️ Unauthorized!", show_alert=True)
        return
    action = query.data
    if action == 'add_vless':
        query.edit_message_text("Tambah user VLESS: /add_vless username hari")
    elif action == 'add_vmess':
        query.edit_message_text("Tambah user VMESS: /add_vmess username hari")
    elif action == 'add_trojan':
        query.edit_message_text("Tambah user TROJAN: /add_trojan username hari")
    elif action == 'add_ssh':
        query.edit_message_text("Tambah user SSH: /add_ssh username password hari")
    elif action == 'add_socks5':
        query.edit_message_text("Tambah user SOCKS5: /add_socks5 username password hari")
    elif action == 'add_ss':
        query.edit_message_text("Tambah user Shadowsocks: /add_ss username hari")
    elif action == 'remove_user':
        query.edit_message_text("Hapus user: /remove_user username")
    elif action == 'list_users':
        output = subprocess.getoutput(f"{BASH_SCRIPT} list_users")
        query.edit_message_text(f"User:\n{output}")
    elif action == 'remove_expired':
        output = subprocess.getoutput(f"{BASH_SCRIPT} remove_expired")
        query.edit_message_text(f"Expired users removed.\n{output}")
    elif action == 'backup':
        output = subprocess.getoutput(f"{BASH_SCRIPT} backup")
        query.edit_message_text(f"Backup file: {output}")
    elif action == 'restore':
        query.edit_message_text("Restore: /restore path/to/backup.tar.gz")
    elif action == 'info_server':
        output = subprocess.getoutput(f"{BASH_SCRIPT} info_server")
        query.edit_message_text(f"{output}")
    else:
        query.answer("Unknown action")

def add_vless_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 2:
        update.message.reply_text("Usage: /add_vless username hari")
        return
    username = context.args[0]
    days = context.args[1]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_vless {username} {days}")
    update.message.reply_text(output)

def add_vmess_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 2:
        update.message.reply_text("Usage: /add_vmess username hari")
        return
    username = context.args[0]
    days = context.args[1]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_vmess {username} {days}")
    update.message.reply_text(output)

def add_trojan_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 2:
        update.message.reply_text("Usage: /add_trojan username hari")
        return
    username = context.args[0]
    days = context.args[1]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_trojan {username} {days}")
    update.message.reply_text(output)

def add_ssh_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 3:
        update.message.reply_text("Usage: /add_ssh username password hari")
        return
    username = context.args[0]
    password = context.args[1]
    days = context.args[2]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_ssh {username} {password} {days}")
    update.message.reply_text(output)

def add_socks5_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 3:
        update.message.reply_text("Usage: /add_socks5 username password hari")
        return
    username = context.args[0]
    password = context.args[1]
    days = context.args[2]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_socks5 {username} {password} {days}")
    update.message.reply_text(output)

def add_ss_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 2:
        update.message.reply_text("Usage: /add_ss username hari")
        return
    username = context.args[0]
    days = context.args[1]
    output = subprocess.getoutput(f"{BASH_SCRIPT} add_user_ss {username} {days}")
    update.message.reply_text(output)

def remove_user_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 1:
        update.message.reply_text("Usage: /remove_user username")
        return
    username = context.args[0]
    output = subprocess.getoutput(f"{BASH_SCRIPT} remove_user {username}")
    update.message.reply_text(output)

def backup_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    output = subprocess.getoutput(f"{BASH_SCRIPT} backup")
    update.message.reply_text(output)

def restore_command(update: Update, context: CallbackContext):
    user_id = update.effective_user.id
    if not is_admin(user_id):
        update.message.reply_text("⛔️ Unauthorized!")
        return
    if len(context.args) < 1:
        update.message.reply_text("Usage: /restore path/to/backup.tar.gz")
        return
    path = context.args[0]
    output = subprocess.getoutput(f"{BASH_SCRIPT} restore {path}")
    update.message.reply_text(output)

def main():
    updater = Updater(BOT_TOKEN, use_context=True)
    dp = updater.dispatcher
    dp.add_handler(CommandHandler('start', start))
    dp.add_handler(CallbackQueryHandler(handle_callback))
    dp.add_handler(CommandHandler('add_vless', add_vless_command))
    dp.add_handler(CommandHandler('add_vmess', add_vmess_command))
    dp.add_handler(CommandHandler('add_trojan', add_trojan_command))
    dp.add_handler(CommandHandler('add_ssh', add_ssh_command))
    dp.add_handler(CommandHandler('add_socks5', add_socks5_command))
    dp.add_handler(CommandHandler('add_ss', add_ss_command))
    dp.add_handler(CommandHandler('remove_user', remove_user_command))
    dp.add_handler(CommandHandler('backup', backup_command))
    dp.add_handler(CommandHandler('restore', restore_command))
    updater.start_polling()
    updater.idle()

if __name__ == '__main__':
    main()
