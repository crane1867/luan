#!/bin/bash
set -e

# === 交互式输入配置项 ===
read -p "请输入 Telegram Bot Token: " BOT_TOKEN
read -p "请输入 Telegram Chat ID: " CHAT_ID

# === 路径设置 ===
INSTALL_DIR="/root/let_bot"
VENV_DIR="$INSTALL_DIR/venv"
SCRIPT_FILE="$INSTALL_DIR/let_offers_bot.py"
DATA_FILE="$INSTALL_DIR/let_seen.txt"
LOG_FILE="$INSTALL_DIR/let_bot.log"
LAST_FILE="$INSTALL_DIR/last_run.txt"
PYTHON="$VENV_DIR/bin/python3"

# === 环境准备 ===
echo "[*] 创建目录 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

echo "[*] 安装系统依赖 ..."
apt update
apt install -y python3 python3-venv python3-pip curl

echo "[*] 创建并激活 Python 虚拟环境 ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "[*] 安装 Python 包 ..."
pip install --upgrade pip
pip install requests feedparser

# === 写入爬虫脚本 ===
echo "[*] 写入 $SCRIPT_FILE ..."
cat > "$SCRIPT_FILE" << EOF
#!/usr/bin/env python3
import os, time
from datetime import datetime, timedelta
import requests, feedparser

# === 配置（使用环境变量） ===
BOT_TOKEN = os.getenv('BOT_TOKEN', '${BOT_TOKEN}')
CHAT_ID = os.getenv('CHAT_ID', '${CHAT_ID}')
INSTALL_DIR = '${INSTALL_DIR}'
DATA_FILE = os.path.join(INSTALL_DIR, 'let_seen.txt')
LOG_FILE = os.path.join(INSTALL_DIR, 'let_bot.log')
LAST_FILE = os.path.join(INSTALL_DIR, 'last_run.txt')
FEED_URL = 'https://lowendtalk.com/categories/offers/feed.rss'

# 日志记录
def log(msg):
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
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

# 加载上次运行时间
def load_last_run():
    if os.path.exists(LAST_FILE):
        ts = float(open(LAST_FILE).read().strip())
        return datetime.fromtimestamp(ts)
    return datetime.now() - timedelta(days=1)

# 保存当前运行时间
def save_last_run(dt):
    with open(LAST_FILE, 'w') as f:
        f.write(str(dt.timestamp()))

# 主逻辑
def check_offers():
    log("开始检查 RSS Feed")
    last_run = load_last_run()
    # 处理完成后再更新，避免中途中断
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
        pub_dt = datetime.fromtimestamp(time.mktime(pub_struct))
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
        save_last_run(datetime.now())
        log(f"[完成] 本次推送 {len(new)} 条新帖")

if __name__ == '__main__':
    check_offers()
EOF

# === 设置环境变量文件 ===
echo "export BOT_TOKEN='${BOT_TOKEN}'" > "$INSTALL_DIR/env.sh"
echo "export CHAT_ID='${CHAT_ID}'" >> "$INSTALL_DIR/env.sh"

# === 配置定时任务 ===
echo "[*] 配置 crontab 每5分钟执行一次 ..."
CRON="*/5 * * * * source $INSTALL_DIR/env.sh && $PYTHON $SCRIPT_FILE"
(crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE"; echo "$CRON") | crontab -

# === 初始化 last_run 文件 ===
echo "[*] 初始化 last_run.txt ..."
echo "$(date +%s)" > "$LAST_FILE"

# === 初次测试 ===
echo "[*] 初次运行脚本进行测试 ..."
source "$INSTALL_DIR/env.sh"
$PYTHON "$SCRIPT_FILE"

echo "[✓] 部署完成。
脚本： $SCRIPT_FILE
日志： $LOG_FILE
记录： $DATA_FILE
最后运行时间文件： $LAST_FILE"
