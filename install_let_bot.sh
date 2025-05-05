#!/bin/bash
set -e

# === 用户交互式输入配置 ===
read -p "请输入 Telegram Bot Token: " BOT_TOKEN
read -p "请输入 Telegram Chat ID（用户或频道）: " CHAT_ID

# === 路径设置 ===
INSTALL_DIR="/root/let_bot"
VENV_DIR="$INSTALL_DIR/venv"
SCRIPT_FILE="$INSTALL_DIR/let_offers_bot.py"
DATA_FILE="$INSTALL_DIR/let_seen.txt"
LOG_FILE="$INSTALL_DIR/let_bot.log"
LAST_FILE="$INSTALL_DIR/last_run.txt"
PYTHON="$VENV_DIR/bin/python3"

echo "[*] 强制使用UTC时区 ..."
sudo timedatectl set-timezone UTC
sudo systemctl restart cron

echo "[*] 创建目录 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

echo "[*] 安装系统依赖 ..."
apt update
apt install -y python3 python3-venv python3-pip curl

echo "[*] 创建 Python 虚拟环境 ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "[*] 安装 Python 包 ..."
pip install --upgrade pip
pip install requests feedparser

echo "[*] 写入爬虫脚本 ..."
cat > "$SCRIPT_FILE" << EOF
#!/usr/bin/env python3
import os
import time
from datetime import datetime, timezone, timedelta
import requests
import feedparser

# === 配置 ===
BOT_TOKEN = '${BOT_TOKEN}'
CHAT_ID = '${CHAT_ID}'
INSTALL_DIR = '${INSTALL_DIR}'
DATA_FILE = os.path.join(INSTALL_DIR, 'let_seen.txt')
LOG_FILE = os.path.join(INSTALL_DIR, 'let_bot.log')
LAST_FILE = os.path.join(INSTALL_DIR, 'last_run.txt')
FEED_URL = 'https://lowendtalk.com/categories/offers/feed.rss'

def log(msg):
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, 'a') as f:
        # 使用 UTC 时间记录日志
        utc_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        f.write(f"[{utc_time}] {msg}\n")

def send_tg(text):
    api = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(api, data={'chat_id': CHAT_ID, 'text': text, 'parse_mode': 'HTML'}, timeout=10)
        if not r.ok:
            log(f"[TG错误 {r.status_code}] {r.text}")
        return r.ok
    except Exception as e:
        log(f"[TG异常] {e}")
        return False

def load_last_run():
    if os.path.exists(LAST_FILE):
        try:
            ts = datetime.strptime(open(LAST_FILE).read().strip(), "%Y-%m-%d %H:%M:%S")
            return ts.replace(tzinfo=timezone.utc)
        except Exception as e:
            log(f"[时间解析失败] {e}")
    return datetime.now(timezone.utc) - timedelta(days=1)

def save_last_run(dt):
    with open(LAST_FILE, 'w') as f:
        f.write(dt.strftime("%Y-%m-%d %H:%M:%S"))

def check_offers():
    log("开始检查 RSS Feed")
    last_run = load_last_run()
    try:
        feed = feedparser.parse(FEED_URL)
    except Exception as e:
        log(f"[解析RSS失败] {e}")
        return

    entries = feed.entries or []
    if not entries:
        log("[RSS空] 未获取到任何帖子")
        return

    seen = set()
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE) as f:
            seen = set(line.strip() for line in f)

    new = []
    for entry in entries:
        pub_struct = entry.get('published_parsed')
        if not pub_struct:
            continue
        pub_dt = datetime.fromtimestamp(time.mktime(pub_struct), tz=timezone.utc)
        if pub_dt <= last_run:
            continue
        guid = entry.get('id', entry.get('link'))
        if guid in seen:
            continue
        new.append((guid, entry.title, entry.link))

    if not new:
        log("[无新帖] 所有项目已处理过或无新发布")
    else:
        for guid, title, link in new:
            text = f"<b>{title}</b>\n{link}"
            if send_tg(text):
                log(f"[推送成功] {title}")
            else:
                log(f"[推送失败] {title}")
            seen.add(guid)
        with open(DATA_FILE, 'w') as f:
            f.write("\n".join(seen))
        save_last_run(datetime.now(timezone.utc))
        log(f"[完成] 本次推送 {len(new)} 条新帖")

if __name__ == '__main__':
    check_offers()
EOF

chmod +x "$SCRIPT_FILE"

echo "[*] 初始化 last_run.txt ..."
echo "$(date -u '+%Y-%m-%d %H:%M:%S')" > "$LAST_FILE"

echo "[*] 配置 crontab 每5分钟执行一次 ..."
CRON="*/5 * * * * $PYTHON $SCRIPT_FILE"
(crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE"; echo "$CRON") | crontab -

# ===打印当前 crontab===
echo "[DEBUG] 当前 crontab："
crontab -l

echo "[*] 初次运行测试 ..."
$PYTHON "$SCRIPT_FILE"

echo "[✓] 部署完成。
脚本路径： $SCRIPT_FILE
日志文件： $LOG_FILE
记录文件： $DATA_FILE
上次运行： $LAST_FILE"
