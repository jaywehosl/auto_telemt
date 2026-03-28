#!/bin/bash

# Цвета
GREEN='\033[0;32m'
NC='\033[0m'
echo -e "${GREEN}=== Telemt Auto-Installer ===${NC}"

# Проверка на root
if [ "$EUID" -ne 0 ]; then
  echo "Запусти скрипт от имени root (sudo !)"
  exit
fi

# 1. Сбор данных
read -p "Введите порт для прокси (по умолчанию 443): " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-443}

read -p "Введите TLS домен (SNI) (по умолчанию google.com): " TLS_DOMAIN
TLS_DOMAIN=${TLS_DOMAIN:-google.com}

read -p "Сколько пользователей создать? (по умолчанию 1): " USER_COUNT
USER_COUNT=${USER_COUNT:-1}

# 2. Установка зависимостей
echo "Установка зависимостей..."
apt-get update -qq
apt-get install -y curl jq tar openssl net-tools -qq

# 3. Скачивание бинарника
echo "Скачивание Telemt..."
ARCH=$(uname -m)
LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"

curl -L "$URL" | tar -xz
mv telemt /bin
chmod +x /bin/telemt

# 4. Создание пользователя и папок
useradd -d /opt/telemt -m -r -U telemt 2>/dev/null
mkdir -p /etc/telemt

# 5. Генерация конфигурации
echo "Генерация конфига..."
CONFIG_PATH="/etc/telemt/telemt.toml"

cat <<EOF > $CONFIG_PATH
[general]
use_middle_proxy = false

[general.modes]
classic = false
secure = false
tls = true

[server]
port = $PROXY_PORT

[server.api]
enabled = true
listen = "127.0.0.1:9091"

[censorship]
tls_domain = "$TLS_DOMAIN"

[access.users]
EOF

for i in $(seq 1 $USER_COUNT); do
    SECRET=$(openssl rand -hex 16)
    echo "user$i = \"$SECRET\"" >> $CONFIG_PATH
done

chown -R telemt:telemt /etc/telemt

# 6. Создание Systemd сервиса
echo "Настройка Systemd..."
cat <<EOF > /etc/systemd/system/telemt.service
[Unit]
Description=Telemt Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/bin/telemt /etc/telemt/telemt.toml
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 7. Запуск
systemctl daemon-reload
systemctl enable telemt
systemctl restart telemt

echo -e "${GREEN}Сервис запущен! Ожидание инициализации сети...${NC}"
sleep 4 # Даем время бинарнику определить свои IP

# 8. Вывод ссылок (Исправленный парсинг)
echo -e "\n${GREEN}=== ВАШИ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]')

if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
    echo "Ошибка: API не выдало ссылки. Проверьте: systemctl status telemt"
else
    # Если IP все еще 0.0.0.0 (бывает на некоторых VPS), подставляем вручную
    PUBLIC_IP=$(curl -s https://api.ipify.org)
    echo "$LINKS" | sed "s/0.0.0.0/$PUBLIC_IP/g"
fi

echo -e "\n${GREEN}Конфиг: /etc/telemt/telemt.toml${NC}"
