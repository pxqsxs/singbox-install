#!/bin/bash

# 错误处理函数
handle_error() {
    echo "错误: $1"
    exit 1
}

# 安装 sing-box
echo "正在安装 sing-box..."
bash <(curl -fsSL https://sing-box.app/deb-install.sh) || handle_error "安装 sing-box 失败。"

# 开启 BBR 拥塞控制
echo "开启 BBR 拥塞控制算法..."
sudo modprobe tcp_bbr || handle_error "加载 BBR 模块失败。"
sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null <<EOF || handle_error "配置 BBR 失败。"
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sudo sysctl -p || handle_error "应用 BBR 配置失败。"

# 生成动态参数
echo "生成配置所需的参数..."
LISTEN_PORT=$(shuf -i 2000-65535 -n 1) || handle_error "生成监听端口失败。"
UUID=$(sing-box generate uuid) || handle_error "生成 UUID 失败。"
REALITY_KEYPAIR=$(sing-box generate reality-keypair) || handle_error "生成 Reality 密钥对失败。"
PRIVATE_KEY=$(echo "$REALITY_KEYPAIR" | grep "PrivateKey" | awk '{print $2}') || handle_error "提取私钥失败。"
PUBLIC_KEY=$(echo "$REALITY_KEYPAIR" | grep "PublicKey" | awk '{print $2}') || handle_error "提取公钥失败。"
SHORT_ID=$(sing-box generate rand --hex 8) || handle_error "生成 Short ID 失败。"

# 获取服务器的外部 IPv4 和 IPv6 地址
SERVER_IP_V4=$(curl -s ifconfig.me) || handle_error "获取 IPv4 地址失败，请检查网络连接。"
SERVER_IP_V6=$(curl -s https://v6.ifconfig.me) || handle_error "获取 IPv6 地址失败，请检查网络连接。"

# 替换现有的配置文件内容
echo "替换 /etc/sing-box/config.json 配置文件内容..."
CONFIG_PATH="/etc/sing-box/config.json"
sudo tee $CONFIG_PATH > /dev/null <<EOF || handle_error "替换配置文件失败。"
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    },
    "dns": {
        "servers": [
            {
                "tag": "cf",
                "address": "https://1.1.1.1/dns-query",
                "strategy": "ipv4_only",
                "detour": "direct"
            },
            {
                "tag": "block",
                "address": "rcode://success"
            }
        ],
        "rules": [
            {
                "geosite": [
                    "category-ads-all"
                ],
                "server": "block",
                "disable_cache": false
            }
        ],
        "final": "cf",
        "strategy": "",
        "disable_cache": false,
        "disable_expire": false
    },
    "inbounds": [
        {
            "type": "vless",
            "listen": "::",
            "listen_port": $LISTEN_PORT,
            "users": [
                {
                    "uuid": "$UUID",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "icloud.cdn-apple.com",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "icloud.cdn-apple.com",
                        "server_port": 443
                    },
                    "private_key": "$PRIVATE_KEY",
                    "short_id": [
                        "$SHORT_ID"
                    ]
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "block",
            "tag": "block"
        },
        {
            "type": "dns",
            "tag": "dns-out"
        }
    ],
    "route": {
        "geoip": {
            "path": "geoip.db",
            "download_url": "https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db",
            "download_detour": "direct"
        },
        "geosite": {
            "path": "geosite.db",
            "download_url": "https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db",
            "download_detour": "direct"
        },
        "rules": [
            {
                "protocol": "dns",
                "outbound": "dns-out"
            },
            {
                "geosite": [
                    "category-ads-all"
                ],
                "outbound": "block"
            }
        ],
        "auto_detect_interface": true,
        "final": "direct"
    },
    "experimental": {}
}
EOF

# 启动并启用 sing-box 服务
echo "启动并设置 sing-box 服务为开机自启..."
sudo systemctl start sing-box || handle_error "启动 sing-box 服务失败。"
sudo systemctl enable sing-box || handle_error "设置 sing-box 开机自启失败。"

# 输出公钥和其他关键信息
echo "----------------------------------------"
echo "Sing-box 已成功安装和配置！"
echo "IPv4 地址: $SERVER_IP_V4"
echo "IPv6 地址: $SERVER_IP_V6"
echo "UUID: $UUID"
echo "监听端口: $LISTEN_PORT"
echo "Reality 公钥: $PUBLIC_KEY"
echo "Short ID: $SHORT_ID"
echo "----------------------------------------"
