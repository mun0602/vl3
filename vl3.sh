#!/bin/bash

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
   echo "Script này cần được chạy với quyền root" 
   exit 1
fi

echo "Bắt đầu cài đặt Xray VLESS Reality..."

# Cài đặt các gói cần thiết
apt update
apt install -y unzip curl uuid-runtime qrencode socat

# Biến
XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
LOG_FILE="${INSTALL_DIR}/access.log"
ERR_FILE="${INSTALL_DIR}/error.log"

# Tạo thư mục cài đặt
mkdir -p ${INSTALL_DIR}

# Tải và cài đặt Xray
echo "Đang tải Xray-core từ GitHub..."
curl -L ${XRAY_URL} -o xray.zip
unzip -o xray.zip -d ${INSTALL_DIR}
chmod +x ${INSTALL_DIR}/xray
rm xray.zip

# Kiểm tra xray đã cài đặt thành công
if [ ! -f "${INSTALL_DIR}/xray" ]; then
    echo "Lỗi: Không thể cài đặt xray. Vui lòng kiểm tra lại URL tải về."
    exit 1
fi

echo "Xray-core đã được cài đặt tại ${INSTALL_DIR}"

# Sinh UUID và port
UUID=$(uuidgen)
PORT=443

# Nhập tên hiển thị (ps) cho cấu hình VLESS
read -p "Nhập tên hiển thị cho cấu hình (ps): " PS_NAME
PS_NAME=${PS_NAME:-"VLESS-Reality"}

# Đặt domain cố định cho Reality
REALITY_DOMAIN="bing.cn"

# Tạo thư mục và file log với quyền phù hợp
mkdir -p ${INSTALL_DIR}
touch ${LOG_FILE} ${ERR_FILE}
chmod 666 ${LOG_FILE} ${ERR_FILE}
chown -R root:root ${INSTALL_DIR}

# Tạo cặp khóa x25519 cho Reality
echo "Đang tạo cặp khóa cho Reality..."
KEYS=$(${INSTALL_DIR}/xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private" | awk -F: '{print $2}' | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public" | awk -F: '{print $2}' | tr -d ' ')

# Tạo short ID
SHORT_ID=$(openssl rand -hex 8)

# Tạo file cấu hình Xray (VLESS Reality)
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "debug",
    "access": "${LOG_FILE}",
    "error": "${ERR_FILE}"
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
          "xver": 0,
          "dest": "${REALITY_DOMAIN}:443",
          "serverNames": ["${REALITY_DOMAIN}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

echo "Đã tạo file cấu hình Xray tại ${CONFIG_FILE}"

# Kiểm tra cấu hình
echo "Kiểm tra cấu hình Xray..."
if ! ${INSTALL_DIR}/xray test -c ${CONFIG_FILE}; then
    echo "Lỗi: Cấu hình không hợp lệ. Kiểm tra lại file cấu hình."
    cat ${CONFIG_FILE}
    exit 1
fi

# Tạo systemd service
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VLESS Reality Service
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

echo "Đã tạo file service systemd tại ${SERVICE_FILE}"

# Reload systemd và khởi động service
echo "Khởi động service Xray..."
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
sleep 5

# Kiểm tra trạng thái Xray
if systemctl is-active --quiet xray; then
  echo "Xray đã khởi động thành công!"
else
  echo "Xray không khởi động được. Kiểm tra logs:"
  echo "=== Systemd Status ==="
  systemctl status xray
  echo "=== Xray Error Log ==="
  cat ${ERR_FILE}
  echo "=== Xray Access Log ==="
  cat ${LOG_FILE}
  exit 1
fi

# Lấy IP server
SERVER_IP=$(curl -s ifconfig.me)

# Mở port firewall (ufw và iptables)
echo "Mở port ${PORT} trên firewall..."
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp
  ufw allow 22/tcp
  ufw --force enable
fi
iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT

# In thông tin cấu hình cho client
echo "==== VLESS Reality ===="
echo "Address: $SERVER_IP"
echo "Port: $PORT"
echo "UUID: $UUID"
echo "Flow: xtls-rprx-vision"
echo "Network: tcp"
echo "Security: reality"
echo "Server Name: $REALITY_DOMAIN"
echo "Private Key: $PRIVATE_KEY"
echo "Public Key: $PUBLIC_KEY"
echo "Short ID: $SHORT_ID"
echo "============================"

# Tạo cấu hình VLESS URL cho client
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#${PS_NAME}"
echo "VLESS URL: $VLESS_URL"

# Tạo mã QR code cho VLESS URL
QR_FILE="/root/vless_reality_qr.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VLESS_URL}"
echo "Mã QR đã lưu tại: ${QR_FILE}"
echo "Quét mã QR dưới đây để nhập nhanh vào app:"
qrencode -t ANSIUTF8 "${VLESS_URL}"

echo "==== HƯỚNG DẪN SỬ DỤNG ===="
echo "1. Dùng v2rayN, v2rayNG, Shadowrocket (network: tcp, security: reality)."
echo "2. Quét mã QR hoặc nhập VLESS URL."
echo "3. Nếu không kết nối được, kiểm tra firewall, log Xray, và outbound server."
echo "4. Xem log truy cập: tail -f ${LOG_FILE}"
echo "============================="
