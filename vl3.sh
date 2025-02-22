#!/bin/bash

# Cập nhật danh sách gói phần mềm (KHÔNG upgrade)
apt update

# Định nghĩa biến
XRAY_URL="https://dtdp.bio/wp-content/apk/Xray-linux-64.zip"
INSTALL_DIR="/usr/local/xray"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
CERT_DIR="/etc/xray"

# Cài đặt các gói cần thiết
apt install -y unzip curl jq qrencode uuid-runtime imagemagick socat

# Kiểm tra xem Xray đã được cài đặt chưa
if [[ -f "${INSTALL_DIR}/xray" ]]; then
    echo "Xray đã được cài đặt. Bỏ qua bước cài đặt."
else
    echo "Cài đặt Xray..."
    mkdir -p ${INSTALL_DIR}
    curl -L ${XRAY_URL} -o xray.zip
    unzip xray.zip -d ${INSTALL_DIR}
    chmod +x ${INSTALL_DIR}/xray
    rm xray.zip
fi

# Nhận địa chỉ IP máy chủ
SERVER_IP=$(curl -s ifconfig.me)

# Nhập User ID, Port, Domain, và tên người dùng
read -p "Nhập User ID VLESS (UUID, nhấn Enter để tạo ngẫu nhiên): " UUID
UUID=${UUID:-$(uuidgen)}
PORT=443
read -p "Nhập tên người dùng: " USERNAME
read -p "Nhập domain của bạn (bắt buộc có SSL): " DOMAIN

# Cài đặt chứng chỉ SSL nếu chưa có
mkdir -p ${CERT_DIR}
if [[ ! -f "${CERT_DIR}/fullchain.pem" || ! -f "${CERT_DIR}/privkey.pem" ]]; then
    echo "Cài đặt chứng chỉ SSL cho ${DOMAIN}..."
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh --issue -d ${DOMAIN} --standalone --key-file ${CERT_DIR}/privkey.pem --fullchain-file ${CERT_DIR}/fullchain.pem
fi

# Tạo file cấu hình cho Xray (VLESS + XTLS)
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
            "flow": "xtls-rprx-direct",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "tlsSettings": {
          "serverName": "${DOMAIN}",
          "certificates": [
            {
              "certificateFile": "${CERT_DIR}/fullchain.pem",
              "keyFile": "${CERT_DIR}/privkey.pem"
            }
          ]
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

# Mở cổng firewall chính xác
ufw allow ${PORT}/tcp

# Kiểm tra và tạo service systemd nếu chưa có
if [[ ! -f "${SERVICE_FILE}" ]]; then
    echo "Tạo service Xray..."
    cat > ${SERVICE_FILE} <<EOF
[Unit]
Description=Xray VLESS + XTLS Service
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_FILE}
Restart=always
User=root
LimitNOFILE=512000

[Install]
WantedBy=multi-user.target
EOF
fi

# Khởi động Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# ✅ Tạo URL VLESS + XTLS đúng chuẩn
VLESS_URL="vless://${UUID}@${DOMAIN}:${PORT}?security=xtls&encryption=none&headerType=&type=tcp#${USERNAME}"

# ✅ Tạo mã QR nhỏ hơn (-s 5), với tên in đậm dưới QR
QR_FILE="/tmp/vless_qr.png"
qrencode -o ${QR_FILE} -s 5 -m 2 "${VLESS_URL}"

# ✅ Thêm tên VLESS dưới QR
convert ${QR_FILE} -gravity south -fill black -pointsize 20 -annotate +0+10 "**${USERNAME}**" ${QR_FILE}

# ✅ Hiển thị thông tin VLESS
echo "========================================"
echo "      Cài đặt VLESS + XTLS hoàn tất!"
echo "----------------------------------------"
echo "Tên người dùng: ${USERNAME}"
echo "VLESS URL: ${VLESS_URL}"
echo "----------------------------------------"
echo "Mã QR được lưu tại: ${QR_FILE}"
echo "Quét mã QR dưới đây để sử dụng:"
qrencode -t ANSIUTF8 "${VLESS_URL}"
echo "----------------------------------------"
echo "Tên người dùng: ${USERNAME}"
echo "========================================"
