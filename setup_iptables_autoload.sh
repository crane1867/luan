#!/usr/bin/env bash
# Debian 12 终极稳定版：systemd 内嵌恢复 iptables（不生成额外脚本）
# 设计目标：
#   - 只负责恢复防火墙规则
#   - 通过 Before=docker.service 保证 Docker 启动前已完成
#   - 不在 unit 里 stop/start docker，避免死锁
#   - 支持卸载
#
# 用法：
#   安装： sudo ./systemd-inline-iptables-docker-debian12.sh
#   卸载： sudo ./systemd-inline-iptables-docker-debian12.sh uninstall

set -e

SERVICE_NAME="iptables-inline-docker-restore.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
RULE_DIR="/etc/iptables"

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 运行" >&2
  exit 1
fi

if [ "${1:-}" = "uninstall" ]; then
  echo "正在卸载 ${SERVICE_NAME} ..."
  systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl daemon-reload
  echo "卸载完成 ✅"
  exit 0
fi

# ---------- 安装流程 ----------

if [ ! -f "$RULE_DIR/rules.v4" ] && [ ! -f "$RULE_DIR/rules.v6" ]; then
  echo "未检测到规则文件："
  echo "  $RULE_DIR/rules.v4 / rules.v6"
  echo "请先执行："
  echo "  mkdir -p /etc/iptables"
  echo "  iptables-save  > /etc/iptables/rules.v4"
  echo "  ip6tables-save > /etc/iptables/rules.v6   # IPv6 可选"
  exit 1
fi

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Restore iptables rules before Docker (final)
After=network-online.target
Wants=network-online.target
Before=docker.service

[Service]
Type=oneshot
TimeoutSec=60

# 恢复 IPv4（若存在）
ExecStart=/bin/sh -c '[ -f /etc/iptables/rules.v4 ] && /sbin/iptables-restore < /etc/iptables/rules.v4 || true'

# 恢复 IPv6（若存在）
ExecStart=/bin/sh -c '[ -f /etc/iptables/rules.v6 ] && command -v /sbin/ip6tables-restore >/dev/null 2>&1 && /sbin/ip6tables-restore < /etc/iptables/rules.v6 || true'

RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

cat <<EOF

安装完成 ✅（终极稳定版）

systemd 服务：$SERVICE_NAME 已启用。

设计说明：
- 本服务只恢复规则，不控制 Docker
- 通过 Before=docker.service 确保 Docker 在其之后启动
- 不会产生循环依赖或卡住启动

测试：
  systemctl start $SERVICE_NAME
  journalctl -u $SERVICE_NAME

卸载方式：
  sudo ./${0##*/} uninstall

EOF
