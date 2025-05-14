#!/bin/bash

# Cài đặt các gói cần thiết
apt update
apt install -y unzip curl uuid-runtime qrencode

# Biến
XRAY_URL="https://dtdp.bio/wp-content/apk/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
LOG_FILE="${INSTALL_DIR}/access.log"
ERR_FILE="${INSTALL_DIR}/error.log"

# Tải và cài đặt Xray nếu chưa có
if [[ ! -f "${INSTALL_DIR}/xray" ]]; then
  mkdir -p ${INSTALL_DIR}
  curl -L ${XRAY_URL} -o xray.zip
  unzip xray.zip -d ${INSTALL_DIR}
  chmod +x ${INSTALL_DIR}/xray
  rm xray.zip
  
  # Thêm đường dẫn xray vào PATH
  echo "export PATH=\$PATH:${INSTALL_DIR}" >> /etc/profile
  source /etc/profile
fi

# Kiểm tra xray đã được cài đặt thành công
if ! command -v xray &> /dev/null; then
    echo "Lỗi: Không thể tìm thấy xray. Vui lòng kiểm tra lại quá trình cài đặt."
    exit 1
fi

# Sinh UUID và port
UUID=$(uuidgen)
PORT=443

# Nhập tên hiển thị (ps) cho cấu hình VLESS
read -p "Nhập tên hiển thị cho cấu hình (ps): " PS_NAME
PS_NAME=${PS_NAME:-"VLESS-Reality"}

# Đặt domain cố định cho Reality
REALITY_DOMAIN="bing.cn"

# Tạo file cấu hình Xray (VLESS Reality)
cat > ${CONFIG_FILE} <<EOF
{
  "log": {
    "loglevel": "info",
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
          "privateKey": "$(${INSTALL_DIR}/xray x25519)",
          "shortIds": ["$(openssl rand -hex 8)"]
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

# Tạo thư mục log nếu chưa tồn tại
touch ${LOG_FILE} ${ERR_FILE}
chmod 666 ${LOG_FILE} ${ERR_FILE}

# Tạo systemd service
cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VLESS Reality Service
After=network.target nss-lookup.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5s
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd và khởi động service
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
sleep 5

# Kiểm tra trạng thái Xray
if systemctl is-active --quiet xray; then
  echo "Xray đã khởi động thành công!"
else
  echo "Xray không khởi động được. Kiểm tra logs: journalctl -u xray -f"
  systemctl status xray
  exit 1
fi

# Lấy IP server
SERVER_IP=$(curl -s ifconfig.me)

# Mở port firewall (ufw và iptables)
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${PORT}/tcp
  ufw allow 22/tcp
  ufw --force enable
fi
iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT

# Lấy thông tin cấu hình từ file
PRIVATE_KEY=$(grep -o '"privateKey": "[^"]*' ${CONFIG_FILE} | cut -d'"' -f4)
SHORT_ID=$(grep -o '"shortIds": \["[^"]*' ${CONFIG_FILE} | cut -d'"' -f4)

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
echo "Short ID: $SHORT_ID"
echo "============================"

# Tạo cấu hình VLESS URL cho client
VLESS_URL="vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_DOMAIN}&fp=chrome&pbk=${PRIVATE_KEY}&sid=${SHORT_ID}&type=tcp#${PS_NAME}"
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
