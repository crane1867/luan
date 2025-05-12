#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建日志目录
LOG_DIR="$HOME/tmp/ws_setup_logs"
mkdir -p "$LOG_DIR"

# 创建日志文件
LOG_FILE="$LOG_DIR/ws_setup_$(date +%Y%m%d%H%M%S).log"
touch "$LOG_FILE"
echo "=== 安装日志开始 $(date) ===" > "$LOG_FILE"

# 创建配置目录和文件
CONFIG_DIR="$HOME/tmp/ws_config"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/ws_config.conf"

# 打印带颜色的信息并记录日志
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $(date +%H:%M:%S) $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $(date +%H:%M:%S) $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $(date +%H:%M:%S) $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date +%H:%M:%S) $1" >> "$LOG_FILE"
}

# 记录调试信息到日志
log_debug() {
    echo "[DEBUG] $(date +%H:%M:%S) $1" >> "$LOG_FILE"
}

# 获取用户名
username=$(whoami)
print_info "检测到用户名: $username"
log_debug "用户名: $username"

# 检查配置文件是否存在
check_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "未找到配置文件，请先执行'修改配置文件'选项"
        log_debug "配置文件不存在: $CONFIG_FILE"
        return 1
    fi
    return 0
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log_debug "已加载配置文件: $CONFIG_FILE"
        return 0
    else
        log_debug "配置文件不存在，无法加载: $CONFIG_FILE"
        return 1
    fi
}

# 检查进程状态
check_processes() {
    NODE_RUNNING=false
    NEZHA_RUNNING=false

    # 检查WebSocket服务进程
    if [ -n "$DOMAIN_DIR" ]; then
        # 检查lsnode进程
        LSNODE_PATTERN="lsnode:$DOMAIN_DIR"
        LSNODE_PID=$(ps aux | grep "$LSNODE_PATTERN" | grep -v grep | awk '{print $2}')
        if [ -n "$LSNODE_PID" ]; then
            NODE_RUNNING=true
            NODE_PID=$LSNODE_PID
            NODE_TYPE="lsnode"
            log_debug "检测到正在运行的lsnode进程，PID: $LSNODE_PID"
        else
            # 备用检查：检查node.pid文件
            if [ -f "$DOMAIN_DIR/node.pid" ]; then
                NODE_PID=$(cat "$DOMAIN_DIR/node.pid")
                if ps -p $NODE_PID > /dev/null; then
                    NODE_RUNNING=true
                    NODE_TYPE="node.pid"
                    log_debug "检测到正在运行的Node.js进程，PID: $NODE_PID"
                else
                    log_debug "node.pid文件存在但进程不存在，PID: $NODE_PID"
                fi
            fi

            # 再次尝试检查node进程
            NODE_PROCESS_PID=$(ps aux | grep "node $DOMAIN_DIR/index.js" | grep -v grep | awk '{print $2}')
            if [ -n "$NODE_PROCESS_PID" ]; then
                NODE_RUNNING=true
                NODE_PID=$NODE_PROCESS_PID
                NODE_TYPE="node"
                log_debug "检测到正在运行的node进程，PID: $NODE_PROCESS_PID"
            fi
        fi
    fi

    # 检查哪吒探针进程
    NEZHA_PID=$(pgrep -u "$USER" -f "nezha-agent")
    if [ -n "$NEZHA_PID" ]; then
        NEZHA_RUNNING=true
        log_debug "检测到正在运行的哪吒探针进程，PID: $NEZHA_PID"
    fi
}

# 显示进程状态
show_status() {
    check_processes

    print_info "进程状态："
    if [ "$NODE_RUNNING" = true ]; then
        echo "- WebSocket服务: 运行中 ($NODE_TYPE进程, PID: $NODE_PID)"
    else
        echo "- WebSocket服务: 未运行"
    fi

    if [ "$NEZHA_RUNNING" = true ]; then
        echo "- 哪吒探针: 运行中 (PID: $NEZHA_PID)"
    else
        echo "- 哪吒探针: 未运行"
    fi
}

# 引导用户创建Node.js应用
guide_nodejs_creation() {
    print_info "请按照以下步骤在控制面板中创建Node.js应用程序:"
    echo "1. 进入控制面板 -> Node.js APP"
    echo "2. 点击\"创建应用程序\""
    echo "3. Node.js版本: 选择最新版本"
    echo "4. Application root: domains/$1/public_html"
    echo "5. Application startup file: index.js"
    echo "6. 点击\"创建\"按钮"
    echo ""
    print_info "创建完成后，请重新运行此脚本"
    log_debug "引导用户创建Node.js应用: $1"
}

# 修改配置文件
modify_config() {
    print_info "修改配置文件..."
    log_debug "用户选择: 修改配置文件"

    # 检查domains目录
    domains_dir="/home/$username/domains"
    if [ ! -d "$domains_dir" ]; then
        print_error "未找到domains目录: $domains_dir"
        log_debug "domains目录不存在: $domains_dir"
        return 1
    fi

    # 列出所有域名目录
    print_info "正在扫描域名目录..."
    domains=()
    for dir in "$domains_dir"/*; do
        if [ -d "$dir" ]; then
            domain_name=$(basename "$dir")
            domains+=("$domain_name")
            log_debug "找到域名目录: $domain_name"
        fi
    done

    # 显示域名列表
    if [ ${#domains[@]} -eq 0 ]; then
        print_warning "未找到任何域名目录，请手动输入域名"
        log_debug "未找到任何域名目录"
        read -p "请输入您的域名 (例如: example.com): " domain
        log_debug "用户输入域名: $domain"
    else
        echo "检测到以下域名:"
        for i in "${!domains[@]}"; do
            echo "[$i] ${domains[$i]}"
        done

        echo "[m] 手动输入其他域名"
        read -p "请选择域名 [0-$((${#domains[@]}-1))/m]: " domain_choice
        log_debug "用户选择: $domain_choice"

        if [[ "$domain_choice" == "m" ]]; then
            read -p "请输入您的域名 (例如: example.com): " domain
            log_debug "用户手动输入域名: $domain"
        elif [[ "$domain_choice" =~ ^[0-9]+$ ]] && [ "$domain_choice" -ge 0 ] && [ "$domain_choice" -lt ${#domains[@]} ]; then
            domain="${domains[$domain_choice]}"
            print_info "已选择域名: $domain"
            log_debug "用户从列表选择域名: $domain"
        else
            print_error "无效选择！"
            log_debug "用户输入了无效选择: $domain_choice"
            return 1
        fi
    fi

    # 确认域名目录是否存在
    domain_dir="/home/$username/domains/$domain/public_html"
    if [ ! -d "$domain_dir" ]; then
        print_error "域名目录 $domain_dir 不存在！"
        print_info "请检查您的域名是否正确，或者域名是否已经在控制面板中创建。"
        log_debug "域名目录不存在: $domain_dir"
        return 1
    fi

    print_info "域名目录: $domain_dir"
    log_debug "确认域名目录: $domain_dir"

    # 检查Node.js应用是否已创建
    NODE_ENV_PATH="/home/$username/nodevenv/domains/$domain/public_html"
    if [ ! -d "$NODE_ENV_PATH" ]; then
        print_warning "未检测到Node.js应用环境，请先创建Node.js应用"
        guide_nodejs_creation "$domain"
        return 1
    fi

    # 询问节点名称
    read -p "请输入节点名称 (默认: hostvps): " node_name
    node_name=${node_name:-"hostvps"}
    log_debug "用户设置节点名称: $node_name"

    # 询问端口号
    read -p "请输入监听端口 (默认: 3000): " port
    port=${port:-3000}
    log_debug "用户设置端口: $port"

    # UUID处理
    read -p "是否自动生成UUID? (Y/n, 默认: Y): " auto_uuid
    auto_uuid=${auto_uuid:-"Y"}
    log_debug "用户选择UUID生成方式: $auto_uuid"

    if [[ $auto_uuid =~ ^[Yy]$ ]]; then
        # 生成UUID
        if command -v uuidgen > /dev/null; then
            uuid=$(uuidgen)
        else
            # 如果没有uuidgen，使用其他方式生成UUID
            uuid=$(cat /proc/sys/kernel/random/uuid)
        fi
        print_info "自动生成的UUID: $uuid"
        log_debug "自动生成UUID: $uuid"
    else
        read -p "请输入UUID: " uuid
        if [ -z "$uuid" ]; then
            print_error "UUID不能为空！"
            log_debug "用户未提供UUID，退出脚本"
            return 1
        fi
        log_debug "用户输入UUID: $uuid"
    fi

    # 询问哪吒探针信息（可选）
    read -p "请输入哪吒服务器地址 (例如: nz.example.com:5555，可选): " nezha_server
    log_debug "用户输入哪吒服务器地址: $nezha_server"

    if [ -n "$nezha_server" ]; then
        read -p "请输入哪吒客户端密钥 (可选): " nezha_key
        log_debug "用户输入哪吒客户端密钥"

        # 询问是否使用TLS
        read -p "是否使用TLS连接哪吒服务器? (Y/n, 默认: Y): " use_tls
        use_tls=${use_tls:-"Y"}
        if [[ $use_tls =~ ^[Yy]$ ]]; then
            nezha_tls=true
            log_debug "用户选择使用TLS连接"
        else
            nezha_tls=false
            log_debug "用户选择不使用TLS连接"
        fi
    else
        nezha_key=""
        nezha_tls=true
    fi

    # 保存配置到文件
    cat > "$CONFIG_FILE" << EOF
# WebSocket服务配置
DOMAIN="$domain"
DOMAIN_DIR="$domain_dir"
NODE_NAME="$node_name"
PORT="$port"
UUID="$uuid"

# 哪吒探针配置
NEZHA_SERVER="$nezha_server"
NEZHA_KEY="$nezha_key"
NEZHA_TLS="$nezha_tls"
EOF
    chmod 600 "$CONFIG_FILE"
    log_debug "已保存配置到 $CONFIG_FILE"

    print_success "配置文件已保存！"
    return 0
}

# 启动WebSocket代理服务
start_websocket() {
    print_info "启动WebSocket代理服务..."
    log_debug "用户选择: 启动WebSocket代理服务"

    # 检查配置文件
    if ! check_config; then
        return 1
    fi

    # 加载配置
    load_config

    # 检查Node.js应用是否已创建
    NODE_ENV_PATH="/home/$username/nodevenv/domains/$DOMAIN/public_html"
    if [ ! -d "$NODE_ENV_PATH" ]; then
        print_warning "未检测到Node.js应用环境，请先创建Node.js应用"
        guide_nodejs_creation "$DOMAIN"
        return 1
    fi

    # 创建index.js文件
    print_info "创建index.js文件..."
    cat > "$DOMAIN_DIR/index.js" << EOF
const http = require('http');
const fs = require('fs');
const { Buffer } = require('buffer');
const net = require('net');
const { WebSocket, createWebSocketStream } = require('ws');

// 配置参数
const UUID = process.env.UUID || '$UUID';    // UUID用于验证连接
const DOMAIN = process.env.DOMAIN || '$DOMAIN';    // 域名
const SUB_PATH = process.env.SUB_PATH || 'sub';     // 获取节点的订阅路径
const NAME = process.env.NAME || '$NODE_NAME';  // 节点名称
const PORT = process.env.PORT || $PORT;     // http和ws服务端口

const httpServer = http.createServer((req, res) => {
    // 记录请求信息，帮助调试
    console.log(\`收到请求: \${req.method} \${req.url}\`);

    // 处理/sub路径，不区分大小写
    if (req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('It works!\\nNodeJS ' + process.versions.node + '\\n');
    } else if (req.url.toLowerCase() === \`/\${SUB_PATH.toLowerCase()}\`) {
        console.log('处理订阅请求...');
        console.log(\`UUID: \${UUID}, DOMAIN: \${DOMAIN}, NAME: \${NAME}\`);

        const nodeName = NAME || 'NodeWS';
        const vlessURL = \`vless://\${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=\${DOMAIN}&type=ws&host=\${DOMAIN}&path=%2F#\${nodeName}\`;

        console.log(\`生成的VLESS URL: \${vlessURL}\`);
        const base64Content = Buffer.from(vlessURL).toString('base64');
        console.log(\`Base64编码后: \${base64Content}\`);

        res.writeHead(200, {
            'Content-Type': 'text/plain',
            'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0'
        });
        res.end(base64Content + '\\n');
    } else if (req.url === '/status') {
        // 添加状态检查端点
        const { exec } = require('child_process');
        exec('ps aux | grep -v grep | grep "node\\\\|nezha-agent"', (error, stdout) => {
            res.writeHead(200, { 'Content-Type': 'text/plain' });
            res.end(\`服务状态:\\n\${stdout}\\n\`);
        });
    } else if (req.url === '/debug') {
        // 添加调试端点
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end(\`调试信息:
UUID: \${UUID}
DOMAIN: \${DOMAIN}
SUB_PATH: \${SUB_PATH}
NAME: \${NAME}
PORT: \${PORT}
\`);
    } else {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found\\n');
    }
});

const wss = new WebSocket.Server({ server: httpServer });
const uuid = UUID.replace(/-/g, "");
wss.on('connection', ws => {
    ws.once('message', msg => {
        const [VERSION] = msg;
        const id = msg.slice(1, 17);
        if (!id.every((v, i) => v == parseInt(uuid.substr(i * 2, 2), 16))) return;
        let i = msg.slice(17, 18).readUInt8() + 19;
        const port = msg.slice(i, i += 2).readUInt16BE(0);
        const ATYP = msg.slice(i, i += 1).readUInt8();
        const host = ATYP == 1 ? msg.slice(i, i += 4).join('.') :
            (ATYP == 2 ? new TextDecoder().decode(msg.slice(i + 1, i += 1 + msg.slice(i, i + 1).readUInt8())) :
                (ATYP == 3 ? msg.slice(i, i += 16).reduce((s, b, i, a) => (i % 2 ? s.concat(a.slice(i - 1, i + 1)) : s), []).map(b => b.readUInt16BE(0).toString(16)).join(':') : ''));
        ws.send(new Uint8Array([VERSION, 0]));
        const duplex = createWebSocketStream(ws);
        net.connect({ host, port }, function () {
            this.write(msg.slice(i));
            duplex.on('error', () => { }).pipe(this).on('error', () => { }).pipe(duplex);
        }).on('error', () => { });
    }).on('error', () => { });
});

httpServer.listen(PORT, () => {
    console.log(\`Server is running on port \${PORT}\`);
});
EOF
    log_debug "已创建index.js文件"

    # 创建package.json
    print_info "创建package.json文件..."
    cat > "$DOMAIN_DIR/package.json" << EOF
{
  "name": "node-ws",
  "version": "1.0.0",
  "description": "WebSocket Server",
  "main": "index.js",
  "author": "eoovve",
  "repository": "https://github.com/eoovve/node-ws",
  "license": "MIT",
  "private": false,
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "ws": "^8.14.2"
  },
  "engines": {
    "node": ">=14"
  }
}
EOF
    log_debug "已创建package.json文件"

    # 停止现有进程
    check_processes
    if [ "$NODE_RUNNING" = true ]; then
        print_info "停止现有WebSocket服务进程..."
        kill $NODE_PID
        log_debug "已停止WebSocket服务进程，PID: $NODE_PID"
    fi

    # 获取Node.js虚拟环境激活脚本
    NODE_VERSIONS=( $(ls -d "$NODE_ENV_PATH"/* 2>/dev/null | grep -o '[0-9]*$' | sort -nr) )
    if [ ${#NODE_VERSIONS[@]} -gt 0 ]; then
        SELECTED_VERSION="${NODE_VERSIONS[0]}"
        NODE_ENV_ACTIVATE="$NODE_ENV_PATH/$SELECTED_VERSION/bin/activate"
        print_info "使用Node.js版本: $SELECTED_VERSION"
        log_debug "选择的Node.js版本: $SELECTED_VERSION, 激活脚本: $NODE_ENV_ACTIVATE"

        # 安装依赖并启动服务
        print_info "安装依赖并启动服务..."
        cd "$DOMAIN_DIR"
        source "$NODE_ENV_ACTIVATE"
        npm install

        # 启动Node.js应用
        nohup node index.js > node.log 2>&1 &
        echo $! > node.pid
        print_success "WebSocket服务已启动，PID: $(cat node.pid)"
        log_debug "已启动WebSocket服务，PID: $(cat node.pid)"
    else
        print_error "未找到Node.js版本，请确保已正确创建Node.js应用"
        log_debug "未找到Node.js版本"
        return 1
    fi

    return 0
}

# 启动哪吒探针
start_nezha() {
    print_info "启动哪吒探针..."
    log_debug "用户选择: 启动哪吒探针"

    # 检查配置文件
    if ! check_config; then
        return 1
    fi

    # 加载配置
    load_config

    # 检查哪吒探针配置
    if [ -z "$NEZHA_SERVER" ] || [ -z "$NEZHA_KEY" ]; then
        print_warning "哪吒探针配置不完整，请先修改配置文件"
        log_debug "哪吒探针配置不完整: NEZHA_SERVER=$NEZHA_SERVER, NEZHA_KEY=$NEZHA_KEY"
        return 1
    fi

    # 停止现有哪吒探针进程
    check_processes
    if [ "$NEZHA_RUNNING" = true ]; then
        print_info "停止现有哪吒探针进程..."
        kill $NEZHA_PID
        log_debug "已停止哪吒探针进程，PID: $NEZHA_PID"
    fi

    # 下载agent.sh（如果不存在）
    if [ ! -f "$HOME/agent.sh" ]; then
        print_info "下载哪吒探针安装脚本..."
        cd "$HOME"
        curl -L https://raw.githubusercontent.com/mqiancheng/host-node-ws/refs/heads/main/agent.sh -o agent.sh && chmod +x agent.sh
        log_debug "成功下载agent.sh并设置执行权限"
    fi

    # 启动哪吒探针
    print_info "启动哪吒探针..."
    cd "$HOME"
    env NZ_SERVER="$NEZHA_SERVER" NZ_TLS=$NEZHA_TLS NZ_UUID="$UUID" NZ_CLIENT_SECRET="$NEZHA_KEY" ./agent.sh > /dev/null 2>&1 &
    log_debug "已启动哪吒探针"

    # 等待探针启动
    sleep 2
    check_processes
    if [ "$NEZHA_RUNNING" = true ]; then
        print_success "哪吒探针已启动，PID: $NEZHA_PID"
    else
        print_warning "哪吒探针可能未正常启动，请检查日志"
    fi

    return 0
}

# 强制重新安装
force_reinstall() {
    print_info "准备强制重新安装..."
    log_debug "用户选择: 强制重新安装"

    read -p "此操作将删除所有现有文件和进程，确定继续? (y/N, 默认: N): " confirm_reinstall
    confirm_reinstall=${confirm_reinstall:-"N"}
    log_debug "用户确认重新安装: $confirm_reinstall"

    if [[ ! $confirm_reinstall =~ ^[Yy]$ ]]; then
        print_info "已取消重新安装。"
        log_debug "用户取消重新安装"
        return 1
    fi

    # 加载配置（如果存在）
    if [ -f "$CONFIG_FILE" ]; then
        load_config
    fi

    # 停止并清理现有安装
    print_info "正在清理现有安装..."

    # 停止WebSocket服务进程
    check_processes
    if [ "$NODE_RUNNING" = true ]; then
        print_info "停止WebSocket服务进程..."
        kill $NODE_PID
        log_debug "已停止WebSocket服务进程，PID: $NODE_PID"
    fi

    # 停止哪吒探针
    if [ "$NEZHA_RUNNING" = true ]; then
        print_info "停止哪吒探针进程..."
        kill $NEZHA_PID
        log_debug "已停止哪吒探针进程，PID: $NEZHA_PID"
    fi

    # 卸载哪吒探针
    if [ -f "$HOME/agent.sh" ]; then
        cd "$HOME"
        ./agent.sh uninstall
        print_info "已卸载哪吒探针"
        log_debug "执行agent.sh uninstall卸载哪吒探针"
    fi

    # 删除文件
    print_info "删除现有文件..."
    log_debug "开始删除文件"

    if [ -n "$DOMAIN_DIR" ] && [ -d "$DOMAIN_DIR" ]; then
        if [ -f "$DOMAIN_DIR/index.js" ]; then
            rm "$DOMAIN_DIR/index.js"
            log_debug "已删除 index.js"
        fi

        if [ -f "$DOMAIN_DIR/package.json" ]; then
            rm "$DOMAIN_DIR/package.json"
            log_debug "已删除 package.json"
        fi

        if [ -f "$DOMAIN_DIR/node.pid" ]; then
            rm "$DOMAIN_DIR/node.pid"
            log_debug "已删除 node.pid"
        fi

        if [ -f "$DOMAIN_DIR/node.log" ]; then
            rm "$DOMAIN_DIR/node.log"
            log_debug "已删除 node.log"
        fi
    fi

    if [ -f "$HOME/agent.sh" ]; then
        rm "$HOME/agent.sh"
        log_debug "已删除 agent.sh"
    fi

    if [ -f "$CONFIG_FILE" ]; then
        rm "$CONFIG_FILE"
        log_debug "已删除配置文件 $CONFIG_FILE"
    fi

    if [ -d "$HOME/nezha" ]; then
        rm -rf "$HOME/nezha"
        log_debug "已删除 nezha 目录"
    fi

    # 清理日志文件夹
    rm -rf "$LOG_DIR"
    mkdir -p "$LOG_DIR"
    log_debug "已清理日志文件夹 $LOG_DIR"

    print_success "清理完成！"
    return 0
}

# 主菜单
show_menu() {
    clear
    echo "========================================"
    echo "      WebSocket服务器部署工具 v1.0      "
    echo "========================================"
    echo ""

    # 显示进程状态
    show_status

    echo ""
    echo "请选择操作："
    echo "1. 修改配置文件"
    echo "2. 启动WebSocket代理服务"
    echo "3. 启动哪吒探针"
    echo "4. 退出脚本"
    echo "5. 强制重新安装（清除现有安装）"
    echo ""

    read -p "请输入选项 [1-5]: " option
    log_debug "用户选择操作: $option"

    case $option in
        1)
            modify_config
            ;;
        2)
            start_websocket
            ;;
        3)
            start_nezha
            ;;
        4)
            print_info "退出脚本。"
            log_debug "用户选择退出脚本"
            exit 0
            ;;
        5)
            force_reinstall
            ;;
        *)
            print_error "无效选项，请重新选择。"
            log_debug "用户输入了无效选项: $option"
            ;;
    esac

    # 操作完成后暂停
    echo ""
    read -p "按Enter键继续..." dummy

    # 返回主菜单
    show_menu
}

# 主函数
main() {
    # 显示欢迎信息
    clear
    echo "========================================"
    echo "      WebSocket服务器部署工具 v1.0      "
    echo "========================================"
    echo ""
    print_info "欢迎使用WebSocket服务器部署工具！"
    print_info "此工具可以帮助您快速部署WebSocket服务和哪吒探针。"
    echo ""

    # 显示主菜单
    show_menu
}

# 执行主函数
main
