#!/bin/bash
set -e

echo "[*] 删除定时任务 ..."
crontab -l | grep -v "let_offers_bot.py" | crontab -

echo "[*] 删除工作目录 /root/let_bot ..."
rm -rf /root/let_bot

echo "[*] （可选）卸载系统依赖 python3-venv, python3-pip, curl ..."
read -p "是否同时卸载系统依赖？[y/N] " yn
if [[ $yn =~ ^[Yy]$ ]]; then
  apt remove --purge -y python3-venv python3-pip curl
  apt autoremove -y
fi

echo "[✓] 卸载完成。"
