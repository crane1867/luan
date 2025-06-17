#!/bin/bash
set -e

# === 用户交互式输入配置 ===
read -p "请输入 Telegram Bot Token: " BOT_TOKEN
read -p "请输入 Telegram Chat ID（用户或频道）: " CHAT_ID

# === 路径设置 ===
INSTALL_DIR="/root/let_bot"
VENV_DIR="$INSTALL_DIR/venv"
SCRIPT_FILE="$INSTALL_DIR/let_les_offers_bot.py"
DATA_FILE="$INSTALL_DIR/let_les_seen.txt"
LOG_FILE="$INSTALL_DIR/let_les_bot.log"
LAST_FILE="$INSTALL_DIR/last_run.txt"
PYTHON="$VENV_DIR/bin/python3"

# === 强制 UTC 时区 ===
echo "[*] 设置系统时区为 UTC ..."
timedatectl set-timezone UTC || true

# === 创建工作目录 ===
echo "[*] 创建目录 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

# === 安装系统依赖 ===
echo "[*] 安装系统依赖 ..."
apt update
apt install -y python3 python3-venv python3-pip cron

# === 创建虚拟环境 ===
echo "[*] 创建 Python 虚拟环境 ..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# === 安装 Python 包 ===
echo "[*] 安装 Python 包: requests, feedparser, cloudscraper ..."
pip install --upgrade pip
pip install requests feedparser cloudscraper

# === 写入爬虫脚本 ===
echo "[*] 写入爬虫脚本 $SCRIPT_FILE ..."
cat > "$SCRIPT_FILE" <<EOF
#!/usr/bin/env python3
import os
import time
import html
from datetime import datetime, timezone, timedelta
import cloudscraper
import feedparser

# === 配置 ===
BOT_TOKEN = '$BOT_TOKEN'
CHAT_ID = '$CHAT_ID'
INSTALL_DIR = '$INSTALL_DIR'
DATA_FILE = os.path.join(INSTALL_DIR, 'let_les_seen.txt')
LOG_FILE = os.path.join(INSTALL_DIR, 'let_les_bot.log')
LAST_FILE = os.path.join(INSTALL_DIR, 'last_run.txt')
FEED_URLS = {
    'LET': 'https://lowendtalk.com/categories/offers/feed.rss',
    'LES': 'https://lowendspirit.com/categories/offers/feed.rss'
}

# 日志记录（UTC）
def log(msg):
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    utc_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    with open(LOG_FILE, 'a') as f:
        f.write(f"[{utc_time}] {msg}\n")

# HTML转义特殊字符
def escape_html(text):
    """转义HTML特殊字符，保留原有标签结构"""
    return html.escape(text).replace("&lt;b&gt;", "<b>").replace("&lt;/b&gt;", "</b>")\
        .replace("&lt;i&gt;", "<i>").replace("&lt;/i&gt;", "</i>")\
        .replace("&lt;u&gt;", "<u>").replace("&lt;/u&gt;", "</u>")\
        .replace("&lt;code&gt;", "<code>").replace("&lt;/code&gt;", "</code>")        

# 发送 Telegram 消息
def send_tg(text):
    api = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    try:
        scraper = cloudscraper.create_scraper()
        # 转义特殊字符但保留Telegram支持的HTML标签
        safe_text = escape_html(text)
        r = scraper.post(api, data={'chat_id': CHAT_ID, 'text': safe_text, 'parse_mode': 'HTML'}, timeout=15)
        
        if not r.ok:
            error_msg = r.text
            # 特殊处理400错误，提供更多调试信息
            if r.status_code == 400 and "can't parse entities" in error_msg:
                log(f"[TG详细错误 400] 消息内容: {text[:100]}...")
            log(f"[TG错误 {r.status_code}] {error_msg}")
            return False
        return True
    except Exception as e:
        log(f"[TG异常] {e}")
        return False

# 加载上次运行时间（UTC）
def load_last_run():
    if os.path.exists(LAST_FILE):
        txt = open(LAST_FILE).read().strip()
        try:
            return datetime.strptime(txt, '%Y-%m-%d %H:%M:%S UTC').replace(tzinfo=timezone.utc)
        except Exception as e:
            log(f"[时间解析失败] {e}")
    return datetime.now(timezone.utc) - timedelta(days=1)

# 保存运行时间（UTC）
def save_last_run(dt):
    with open(LAST_FILE, 'w') as f:
        f.write(dt.strftime('%Y-%m-%d %H:%M:%S UTC'))

# 主逻辑
def check_offers():
    log("="*50)
    log("开始检查 RSS Feed")
    last_run = load_last_run()
    log(f"上次运行时间: {last_run.strftime('%Y-%m-%d %H:%M:%S UTC')}")
    
    seen = set()
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE) as f:
            seen = set(line.strip() for line in f)
    log(f"已加载 {len(seen)} 条历史记录")

    new = []
    scraper = cloudscraper.create_scraper()
    
    for forum, url in FEED_URLS.items():
        log(f"检查 {forum} 的 RSS Feed: {url}")
        try:
            resp = scraper.get(url, timeout=20)
            log(f"[{forum}] HTTP状态: {resp.status_code}")
            if resp.status_code != 200:
                log(f"[{forum} HTTP错误] 状态码 {resp.status_code}")
                continue
                
            feed = feedparser.parse(resp.content)
            log(f"[{forum}] 获取到 {len(feed.entries)} 条记录")
        except Exception as e:
            log(f"[解析{forum}的RSS失败] {str(e)}")
            continue

        entries = feed.entries or []
        if not entries:
            log(f"[{forum} RSS空] 未获取到任何帖子")
            continue

        for entry in entries:
            pub_struct = entry.get('published_parsed')
            if not pub_struct:
                continue
                
            pub_dt = datetime.fromtimestamp(time.mktime(pub_struct), tz=timezone.utc)
            if pub_dt <= last_run:
                continue
                
            guid = entry.get('guid') or entry.get('id') or entry.get('link')
            if not guid:
                guid = entry.link  # 使用链接作为备用GUID
                
            if not guid or guid in seen:
                continue
                
            # 记录找到的新条目
            log(f"[新条目] 标题: {entry.title[:50]}... | 发布时间: {pub_dt.strftime('%Y-%m-%d %H:%M:%S UTC')}")
            new.append((guid, f"[{forum}] {entry.title}", entry.link))

    if not new:
        log("[无新帖] 所有项目已处理过或无新发布")
    else:
        success_count = 0
        for guid, title, link in new:
            # 构造消息（转义会在send_tg中处理）
            text = f"<b>{title}</b>\n{link}"
            if send_tg(text):
                log(f"[推送成功] {title[:40]}...")
                seen.add(guid)
                success_count += 1
            else:
                log(f"[推送失败] {title[:40]}...")
                
        # 只保存成功发送的GUID
        if success_count > 0:
            with open(DATA_FILE, 'w') as f:
                f.write("\n".join(seen))
            save_last_run(datetime.now(timezone.utc))
        log(f"[完成] 尝试推送 {len(new)} 条，成功 {success_count} 条")

if __name__ == '__main__':
    try:
        check_offers()
    except Exception as e:
        log(f"[全局异常] {str(e)}")
EOF

chmod +x "$SCRIPT_FILE"

echo "[*] 初始化 last_run.txt ..."
echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$LAST_FILE"

echo "[*] 配置 crontab 每5分钟执行一次 ..."
CRON="*/5 * * * * $PYTHON $SCRIPT_FILE"
(crontab -l 2>/dev/null | grep -v "$SCRIPT_FILE"; echo "$CRON") | crontab -

# ===打印当前 crontab===
echo "[DEBUG] 当前 crontab："
crontab -l

echo "[*] 初次运行测试 ..."
$PYTHON "$SCRIPT_FILE"

echo "[✓] 部署完成。"
echo "脚本： $SCRIPT_FILE"
echo "日志： $LOG_FILE"
echo "记录： $DATA_FILE"
echo "最后运行时间： $LAST_FILE"
