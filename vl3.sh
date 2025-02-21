#!/bin/bash

# Cập nhật hệ thống và cài đặt gói cần thiết
apt update && apt install -y curl unzip jq qrencode uuid-runtime imagemagick socat

# Định nghĩa biến
SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v1.11.3/sing-box-1.11.3-linux-amd64.tar.gz"
INSTALL_DIR="/usr/local/sing-box"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

# Cài đặt Sing-box v1.11.3
mkdir -p ${INSTALL_DIR}
curl -L ${SINGBOX_URL} -o sing-box.tar.gz
tar -xzf sing-box.tar.gz -C ${INSTALL_DIR} --strip-components=1
chmod +x ${INSTALL_DIR}/sing-box
rm sing-box.tar.gz

# Nhận địa chỉ IP máy chủ
SERVER_IP=$(curl -s ifconfig.me)

# Người dùng nhập tên hiển thị
read -p "Nhập tên người dùng: " USERNAME

# Tạo UUID ngẫu nhiên
UUID=$(uuidgen)

# Port ngẫu nhiên từ 10000 - 60000
PORT=$((RANDOM % 50000 + 10000))

# Fake SNI (Tên miền giả lập)
FAKE_SNI="www.amazon.com"

# Tạo khóa Reality
PRIVATE_KEY=$(${INSTALL_DIR}/sing-box generate reality-keypair)
PRIV_KEY=$(echo "$PRIVATE_KEY" | grep "PrivateKey" | awk '{print $2}')
PUB_KEY=$(echo "$PRIVATE_KEY" | grep "PublicKey" | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)  # Tạo Short ID ngẫu nhiên

# Tạo file cấu hình Reality trên Sing-box
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${FAKE_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${FAKE_SNI}",
            "server_port": 443
          },
          "private_key": "${PRIV_KEY}",
          "short_id": ["${SHORT_ID}"]
        }
      },
      "transport": {
        "type": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# Mở cổng firewall chính xác
ufw allow ${PORT}/tcp

# Tạo service systemd cho Sing-box
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Sing-box VLESS + Reality
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/sing-box run -c ${CONFIG_FILE}
Restart=always
User=root
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF

# Khởi động Sing-box
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ✅ Tạo URL VLESS + Reality
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${FAKE_SNI}&pbk=${PUB_KEY}&fp=chrome#${USERNAME}-${SERVER_IP}"

# ✅ Tạo mã QR nhỏ (-s 5), với tên in đậm dưới QR
QR_FILE="/tmp/vless_qr.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VLESS_URL}"

# ✅ Thêm tên dưới QR
convert ${QR_FILE} -gravity south -fill black -pointsize 20 -annotate +0+10 "**Reality - ${USERNAME}**" ${QR_FILE}

# ✅ Hiển thị thông tin
echo "========================================"
echo "      Cài đặt VLESS + Reality trên Sing-box v1.11.3 hoàn tất!"
echo "----------------------------------------"
echo "Tên người dùng: ${USERNAME}"
echo "VLESS URL: ${VLESS_URL}"
echo "----------------------------------------"
echo "Mã QR được lưu tại: ${QR_FILE}"
echo "Quét mã QR dưới đây để sử dụng:"
qrencode -t ANSIUTF8 "${VLESS_URL}"
echo "========================================"
