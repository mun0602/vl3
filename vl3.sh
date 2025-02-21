#!/bin/bash

# Cập nhật hệ thống
apt update && apt install -y curl unzip jq qrencode uuid-runtime

# Định nghĩa biến
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"

# Cài đặt Xray
mkdir -p ${INSTALL_DIR}
curl -L ${XRAY_URL} -o xray.zip
unzip xray.zip -d ${INSTALL_DIR}
chmod +x ${INSTALL_DIR}/xray
rm xray.zip

# Nhận địa chỉ IP máy chủ
SERVER_IP=$(curl -s ifconfig.me)

# Tạo UUID ngẫu nhiên
UUID=$(uuidgen)

# Port ngẫu nhiên từ 10000 - 60000
PORT=$((RANDOM % 50000 + 10000))

# Fake SNI (Tên miền giả lập)
FAKE_SNI="www.cloudflare.com"

# Tạo khóa Reality
PRIVATE_KEY=$(${INSTALL_DIR}/xray x25519)
PRIV_KEY=$(echo "$PRIVATE_KEY" | awk '{print $3}')
PUB_KEY=$(echo "$PRIVATE_KEY" | awk '{print $6}')

# Tạo file cấu hình Reality
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${FAKE_SNI}:443",
          "xver": 0,
          "serverNames": [
            "${FAKE_SNI}"
          ],
          "privateKey": "${PRIV_KEY}",
          "shortIds": ["${UUID:0:8}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# Mở cổng firewall
ufw allow ${PORT}/tcp

# Tạo service systemd
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VLESS + Reality
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=always
User=root
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF

# Khởi động Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# Tạo URL VLESS + Reality
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?security=reality&pbk=${PUB_KEY}&sid=${UUID:0:8}&fp=chrome&sni=${FAKE_SNI}&type=tcp&flow=xtls-rprx-vision#Reality"

# Tạo mã QR nhỏ (-s 5), với tên in đậm dưới QR
QR_FILE="/tmp/vless_qr.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VLESS_URL}"

# Thêm tên dưới QR
convert ${QR_FILE} -gravity south -fill black -pointsize 20 -annotate +0+10 "**Reality**" ${QR_FILE}

# Hiển thị thông tin
echo "========================================"
echo "      Cài đặt VLESS + Reality hoàn tất!"
echo "----------------------------------------"
echo "VLESS URL: ${VLESS_URL}"
echo "----------------------------------------"
echo "Mã QR được lưu tại: ${QR_FILE}"
echo "Quét mã QR dưới đây để sử dụng:"
qrencode -t ANSIUTF8 "${VLESS_URL}"
echo "========================================"
