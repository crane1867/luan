#!/bin/bash

# 脚本功能：iptables 快捷管理
# 作者：你的名字或组织
# 日期：2024-07-26

# 脚本保存路径
script_path="/root/iptables.sh"

# 定义一些常用函数

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "请以 root 权限运行此脚本"
        exit 1
    fi
}

# 安装 iptables
install_iptables() {
    if ! command -v iptables &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y iptables
        elif command -v yum &> /dev/null; then
            yum install -y iptables
        elif command -v dnf &> /dev/null; then
            dnf install -y iptables
        else
            echo "无法找到包管理器，请手动安装 iptables"
            exit 1
        fi
    fi
}

# 保存 iptables 规则
save_iptables_rules() {
    mkdir -p /etc/iptables
    touch /etc/iptables/rules.v4
    iptables-save > /etc/iptables/rules.v4
    # 确保重启后恢复规则 (适用于 systemd)
    if command -v systemctl &> /dev/null; then
        systemctl enable netfilter.service
        systemctl enable iptables.service
    else
        # 旧系统，使用 crontab
        check_crontab_installed
        crontab -l | grep -v 'iptables-restore' | crontab - > /dev/null 2>&1
        (crontab -l ; echo '@reboot iptables-restore < /etc/iptables/rules.v4') | crontab - > /dev/null 2>&1
    fi
}

# 检查 crontab 是否已安装
check_crontab_installed() {
    if ! command -v crontab &> /dev/null; then
        if command -v apt-get &> /dev/null; then
            apt-get install -y cron
        elif command -v yum &> /dev/null; then
            yum install -y crond
            systemctl enable crond
            systemctl start crond
        elif command -v dnf &> /dev/null; then
            dnf install -y cronie
            systemctl enable crond
            systemctl start crond
        else
            echo "无法找到 cron，请手动安装"
        fi
    fi
}

# 初始化 iptables
iptables_init() {
    install_iptables
    save_iptables_rules
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    iptables -Z

    # 允许已建立的连接和相关流量
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
}

# 开放指定端口
open_port() {
    local ports=($@)
    if [ ${#ports[@]} -eq 0 ]; then
        echo "请提供至少一个端口号"
        return 1
    fi

    install_iptables

    for port in "${ports[@]}"; do
        # 删除可能存在的规则
        iptables -D INPUT -p tcp --dport $port -j DROP 2>/dev/null
        iptables -D INPUT -p udp --dport $port -j DROP 2>/dev/null
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null

        # 添加打开规则
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
        iptables -A INPUT -p udp --dport $port -j ACCEPT
        echo "已打开端口 $port"
    done

    save_iptables_rules
    echo "端口已开放"
}

# 关闭指定端口
close_port() {
    local ports=($@)
    if [ ${#ports[@]} -eq 0 ]; then
        echo "请提供至少一个端口号"
        return 1
    fi

    install_iptables

    for port in "${ports[@]}"; do
        # 删除可能存在的规则
        iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null
        iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null
        iptables -D INPUT -p tcp --dport $port -j DROP 2>/dev/null
        iptables -D INPUT -p udp --dport $port -j DROP 2>/dev/null

        # 添加关闭规则
        iptables -A INPUT -p tcp --dport $port -j DROP
        iptables -A INPUT -p udp --dport $port -j DROP
        echo "已关闭端口 $port"
    done

    save_iptables_rules
    echo "端口已关闭"
}

# 开放所有端口
open_all_ports() {
    install_iptables

    # 获取当前 SSH 端口
    current_ssh_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$current_ssh_port" ]; then
        current_ssh_port=22  # 默认 SSH 端口
    fi

    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F

    # 允许已建立的连接和相关流量
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # 允许 SSH
    iptables -A INPUT -p tcp --dport $current_ssh_port -j ACCEPT

    save_iptables_rules
    echo "已开放所有端口，但保留 SSH 端口 $current_ssh_port"
}

# 关闭所有端口
close_all_ports() {
    install_iptables

    # 获取当前 SSH 端口
    current_ssh_port=$(grep -E '^ *Port [0-9]+' /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$current_ssh_port" ]; then
        current_ssh_port=22  # 默认 SSH 端口
    fi

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # 允许已建立的连接和相关流量
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # 允许本地回环
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # 允许 SSH
    iptables -A INPUT -p tcp --dport $current_ssh_port -j ACCEPT

    save_iptables_rules
    echo "已关闭所有端口，但保留 SSH 端口 $current_ssh_port"
}

# IP 白名单
allow_ip() {
    local ips=($@)
    if [ ${#ips[@]} -eq 0 ]; then
        echo "请提供至少一个IP地址或IP段"
        return 1
    fi

    install_iptables

    for ip in "${ips[@]}"; do
        # 删除可能存在的规则
        iptables -D INPUT -s $ip -j DROP 2>/dev/null
        iptables -D INPUT -s $ip -j ACCEPT 2>/dev/null

        # 添加允许规则
        iptables -A INPUT -s $ip -j ACCEPT
        echo "已放行IP $ip"
    done

    save_iptables_rules
    echo "IP已放行"
}

# IP 黑名单
block_ip() {
    local ips=($@)
    if [ ${#ips[@]} -eq 0 ]; then
        echo "请提供至少一个IP地址或IP段"
        return 1
    fi

    install_iptables

    for ip in "${ips[@]}"; do
        # 删除可能存在的规则
        iptables -D INPUT -s $ip -j ACCEPT 2>/dev/null
        iptables -D INPUT -s $ip -j DROP 2>/dev/null

        # 添加阻止规则
        iptables -A INPUT -s $ip -j DROP
        echo "已阻止IP $ip"
    done

    save_iptables_rules
    echo "IP已阻止"
}

# 允许 PING
allow_ping() {
    install_iptables

    # 删除可能存在的规则
    iptables -D INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null
    iptables -D INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null

    # 允许 PING
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT

    save_iptables_rules
    echo "已允许PING"
}

# 禁止 PING
deny_ping() {
    install_iptables

    # 删除可能存在的规则
    iptables -D INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null
    iptables -D INPUT -p icmp --icmp-type echo-request -j DROP 2>/dev/null

    # 禁止 PING
    iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
    iptables -A OUTPUT -p icmp --icmp-type echo-reply -j DROP

    save_iptables_rules
    echo "已禁止PING"
}

# 显示当前 iptables 规则
show_rules() {
    install_iptables  # 确保 iptables 已安装

    echo "当前 iptables 规则:"
    echo "------------------------------------------------------------------"
    echo "Chain\tProtocol\tSource\t\t\tPort/Target\t\tAction"
    echo "------------------------------------------------------------------"

    # 显示 INPUT 链规则
    echo -e "\nINPUT Chain:"
    iptables -L INPUT -n -v | awk '
        /^ *[0-9]+/ {
            printf "%-8s", "INPUT";
            printf "%-10s", $2;  # 协议
            printf "%-24s", $9;  # 源地址
            if ($10 ~ /dpt:/) {
                split($10, a, ":");
                printf "%-24s", "dpt:" a[2];  # 目标端口
            } else {
                printf "%-24s", "-";
            }
            printf "%-10s\n", $11; # 动作
        }
    '

    # 显示 FORWARD 链规则
    echo -e "\nFORWARD Chain:"
    iptables -L FORWARD -n -v | awk '
        /^ *[0-9]+/ {
            printf "%-8s", "FORWARD";
            printf "%-10s", $2;
            printf "%-24s", $9;
            if ($10 ~ /dpt:/) {
                split($10, a, ":");
                printf "%-24s", "dpt:" a[2];
            } else {
                printf "%-24s", "-";
            }
            printf "%-10s\n", $11;
        }
    '

    # 显示 OUTPUT 链规则
    echo -e "\nOUTPUT Chain:"
    iptables -L OUTPUT -n -v | awk '
        /^ *[0-9]+/ {
            printf "%-8s", "OUTPUT";
            printf "%-10s", $2;
            printf "%-24s", $9;
            if ($10 ~ /dpt:/) {
                split($10, a, ":");
                printf "%-24s", "dpt:" a[2];
            } else {
                printf "%-24s", "-";
            }
            printf "%-10s\n", $11;
        }
    '
    echo "------------------------------------------------------------------"
}

# 主程序
run() {
    check_root
    install_iptables

    if [ -z "$1" ]; then
        main_menu
        read -p "请选择操作: " choice
    else
        choice="$1"
        shift  # 移除第一个参数
    fi

    case $choice in
        1)
            ports="$*"  # 使用剩余的所有参数
            if [ -z "$ports" ]; then
                read -p "请输入要开放的端口 (多个端口用空格分隔): " ports
            fi
            open_port $ports
            ;;
        2)
            ports="$*"
            if [ -z "$ports" ]; then
                read -p "请输入要关闭的端口 (多个端口用空格分隔): " ports
            fi
            close_port $ports
            ;;
        3)
            open_all_ports
            ;;
        4)
            close_all_ports
            ;;
        5)
            ips="$*"
            if [ -z "$ips" ]; then
                read -p "请输入要加入白名单的 IP 或 IP 段 (多个用空格分隔): " ips
            fi
            allow_ip $ips
            ;;
        6)
            ips="$*"
            if [ -z "$ips" ]; then
                read -p "请输入要加入黑名单的 IP 或 IP 段 (多个用空格分隔): " ips
            fi
            block_ip $ips
            ;;
        7)
            allow_ping
            ;;
        8)
            deny_ping
            ;;
        9)
            show_rules
            ;;
        0)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效的选择，请重新输入"
            ;;
    esac
}

# 主菜单
main_menu() {
    clear
    echo "iptables 快捷管理脚本"
    echo "------------------------"
    echo "1.  开放指定端口"
    echo "2.  关闭指定端口"
    echo "3.  开放所有端口"
    echo "4.  关闭所有端口"
    echo "------------------------"
    echo "5.  IP白名单"
    echo "6.  IP黑名单"
    echo "------------------------"
    echo "7.  允许PING"
    echo "8.  禁止PING"
    echo "9.  显示当前规则"
    echo "------------------------"
    echo "0.  退出"
    echo "------------------------"
}

# 如果不是交互式 shell，则执行 run 函数
if [[ $- != *i* ]]; then
    run "$@"
else
    # 将脚本保存到 /root 目录
    cp "$0" "$script_path"
    chmod +x "$script_path"

    # 在安装过程中创建别名
    echo "alias ip='bash $script_path'" >> ~/.bashrc
    source ~/.bashrc
    echo "iptables 快捷管理脚本已安装到 /root/iptables.sh，可以使用 'ip' 命令。"
fi
