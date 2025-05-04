#!/bin/bash
set -e

# === 配置项（直接硬编码，确保生效） ===
BOT_TOKEN="xxx"
CHAT_ID="xxx"

# === 路径设置 ===
INSTALL_DIR="/root/let_bot"
VENV_DIR="$INSTALL_DIR/venv"
SCRIPT_FILE="$INSTALL_DIR/let_offers_bot.py"
DATA_FILE="$INSTALL_DIR/let_seen.txt"
LOG_FILE="$INSTALL_DIR/let_bot.log"
PYTHON="$VENV_DIR/bin/python3"

# === 创建工作目录 ===
echo "[*] 创建目录 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

# === 安装系统依赖 ===
echo "[*] 安装 Python3, venv, pip ..."
apt update
apt install -y python3 python3-venv python3-pip curl

# === 创建虚拟环境 ===
echo "[*] 创建 Python 虚拟环境 ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# === 安装 Python 包 ===
echo "[*] 安装 requests, feedparser, beautifulsoup4 ..."
pip install --upgrade pip
pip install requests feedparser beautifulsoup4

# === 写入爬虫脚本 ===
echo "[*] 写入 let_offers_bot.py ..."
cat > "$SCRIPT_FILE" << 'EOF'
#!/usr/bin/env python3
import os
from datetime import datetime
import requests
import feedparser
from bs4 import BeautifulSoup

# === 配置（已硬编码） ===
BOT_TOKEN = 'xxx'
CHAT_ID = 'xxx'
DATA_FILE = os.path.expanduser('~/let_bot/let_seen.txt')
LOG_FILE = os.path.expanduser('~/let_bot/let_bot.log')
FEED_URL = 'https://lowendtalk.com/categories/offers/feed.rss'

# 日志函数
def log(msg):
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{datetime.now()}] {msg}\n")

# 发送 Telegram

def send_tg(text):
    api = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        r = requests.post(api,
                          data={'chat_id': CHAT_ID, 'text': text, 'parse_mode': 'HTML'},
                          timeout=10)
        if not r.ok:
            log(f"[TG错误 {r.status_code}] {r.text}")
        return r.ok
    except Exception as e:
        log(f"[TG异常] {e}")
        return False

# 主函数

def check_offers():
    log("开始检查 RSS Feed: " + FEED_URL)
    try:
        feed = feedparser.parse(FEED_URL)
    except Exception as e:
        log(f"[解析RSS失败] {e}")
        return

    entries = feed.entries
    if not entries:
        log("[RSS空] 未获取到任何帖子")
        return

    # 读取已见 GUID
    seen = set()
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE) as f:
            seen = set(line.strip() for line in f)

    # 收集新帖
    new = []
    for entry in entries:
        guid = entry.get('id', entry.get('link'))
        if guid not in seen:
            title = entry.title
            link = entry.link
            new.append((guid, title, link))

    if not new:
        log("[无新帖] 所有项目已处理过")
        return

    # 推送并记录
    for guid, title, link in new:
        text = f"<b>{title}</b>\n{link}"
        if send_tg(text):
            log(f"[推送成功] {title}")
        else:
            log(f"[推送失败] {title}")
        seen.add(guid)

    # 更新已见列表
    with open(DATA_FILE, 'w') as f:
        f.write("\n".join(seen))

    log(f"[完成] 本次推送 {len(new)} 条新帖")

if __name__ == '__main__':
    check_offers()
EOF

# === 配置定时任务 ===
echo "[*] 配置 crontab，每5分钟执行一次 ..."
CRON="*/5 * * * * $PYTHON $SCRIPT_FILE"
(crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE"; echo "$CRON") | crontab -

# === 初次测试 ===
echo "[*] 初次运行测试 ..."
env $PYTHON $SCRIPT_FILE

echo "[✓] 部署完成。
脚本： $SCRIPT_FILE
日志： $LOG_FILE
记录： $DATA_FILE"
