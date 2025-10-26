#!/bin/bash
# ==========================================
# Debian 12 + Docker 环境下的 iptables 自动恢复脚本
# ==========================================

set -e

RULES_FILE="/etc/iptables/rules.v4"
SERVICE_FILE="/etc/systemd/system/iptables-restore.service"

echo "=== 检查 iptables 工具包 ==="
if ! command -v iptables >/dev/null 2>&1; then
    apt update -y
    apt install -y iptables
fi

echo "=== 创建规则文件目录 ==="
mkdir -p /etc/iptables

# 如果规则文件不存在，则创建一个默认模板
if [ ! -f "$RULES_FILE" ]; then
    echo "=== 未检测到规则文件，创建默认模板 ==="
    cat > "$RULES_FILE" <<'EOF'
# Default iptables rules (auto-generated)
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow established and related connections
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow ICMP (ping)
-A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# Allow SSH (22)
-A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
-A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

COMMIT
EOF
    echo "默认规则文件已创建于 $RULES_FILE"
else
    echo "检测到已有规则文件，将使用现有规则。"
fi

echo "=== 创建 systemd 服务 ==="
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Restore iptables firewall rules after network and Docker startup
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/sbin/iptables-restore /etc/iptables/rules.v4
ExecStartPost=/usr/sbin/ip6tables-restore /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 如果没有 IPv6 文件，则删除相关行
if [ ! -f "/etc/iptables/rules.v6" ]; then
    sed -i '/ExecStartPost/d' "$SERVICE_FILE"
fi

echo "=== 重新加载 systemd ==="
systemctl daemon-reload

echo "=== 启用并启动 iptables-restore 服务 ==="
systemctl enable iptables-restore.service
systemctl start iptables-restore.service

echo "=== 当前规则 ==="
iptables -L -n

echo "=== 测试服务状态 ==="
systemctl status iptables-restore.service --no-pager

echo ""
echo "✅ 已完成设置。重启后规则将自动加载（Docker 启动后恢复）。"
echo "如果需要保存当前规则，请运行："
echo "    iptables-save > /etc/iptables/rules.v4"
echo ""
