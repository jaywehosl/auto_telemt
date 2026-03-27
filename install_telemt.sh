#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Telemt Auto-Installer ===${NC}"

# 1. Проверка на root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Этот скрипт должен быть запущен от имени root${NC}" 
   exit 1
fi

# 2. Сбор данных от пользователя
read -p "Введите порт для прокси (по умолчанию 443): " PROXY_PORT </dev/tty
PROXY_PORT=${PROXY_PORT:-443}

read -p "Введите домен для маскировки (SNI, например google.com): " TLS_DOMAIN </dev/tty
TLS_DOMAIN=${TLS_DOMAIN:-google.com}

read -p "Сколько пользователей создать? " USER_COUNT </dev/tty
if ! [[ "$USER_COUNT" =~ ^[0-9]+$ ]] ; then
   echo -e "${RED}Ошибка: введите число.${NC}"; exit 1
fi

USER_NAMES=()
for ((i=1; i<=USER_COUNT; i++)); do
    read -p "Введите имя для пользователя #$i: " UNAME </dev/tty
    USER_NAMES+=("$UNAME")
done

# 3. Установка зависимостей
echo -e "${GREEN}Установка зависимостей (curl, jq, openssl)...${NC}"
apt-get update -qq
apt-get install -y curl jq openssl libcap2-bin -qq

# 4. Скачивание бинарного файла (определяем архитектуру)
ARCH=$(uname -m)
case $ARCH in
    x86_64) BIN_URL="https://github.com/telemt/telemt/releases/latest/download/telemt-linux-amd64" ;;
    aarch64) BIN_URL="https://github.com/telemt/telemt/releases/latest/download/telemt-linux-arm64" ;;
    *) echo -e "${RED}Архитектура $ARCH не поддерживается.${NC}"; exit 1 ;;
esac

echo -e "${GREEN}Скачивание telemt...${NC}"
curl -L "$BIN_URL" -o /usr/bin/telemt
chmod +x /usr/bin/telemt
# Позволяем бинарнику слушать низкие порты без root
setcap cap_net_bind_service=+ep /usr/bin/telemt

# 5. Создание системного пользователя
id -u telemt &>/dev/null || useradd -r -s /bin/false telemt

# 6. Создание директорий и конфига
mkdir -p /etc/telemt
cat <<EOF > /etc/telemt/telemt.toml
[server]
listen = "0.0.0.0:$PROXY_PORT"
tls_domain = "$TLS_DOMAIN"

[api]
listen = "127.0.0.1:9091"

[access.users]
EOF

# Генерация секретов для пользователей
for NAME in "${USER_NAMES[@]}"; do
    SECRET=$(openssl rand -hex 16)
    echo "    $NAME = \"$SECRET\"" >> /etc/telemt/telemt.toml
done

# 7. Создание Systemd сервиса
cat <<EOF > /etc/systemd/system/telemt.service
[Unit]
Description=Telemt Proxy Service
After=network.target

[Service]
Type=simple
User=telemt
Group=telemt
ExecStart=/usr/bin/telemt -c /etc/telemt/telemt.toml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 8. Запуск
echo -e "${GREEN}Запуск сервиса...${NC}"
systemctl daemon-reload
systemctl enable telemt
systemctl restart telemt

# 9. Формирование ссылок
echo -e "\n${GREEN}=== Установка завершена! ===${NC}"
IP=$(curl -s https://ifconfig.me)
HEX_DOMAIN=$(echo -n "$TLS_DOMAIN" | xxd -p | tr -d '\n')

echo -e "Ваши ссылки для подключения:\n"

for NAME in "${USER_NAMES[@]}"; do
    # Получаем секрет из конфига для этого юзера
    USER_SECRET=$(grep -W "$NAME =" /etc/telemt/telemt.toml | cut -d'"' -f2)
    # Формат ссылки для FakeTLS: ee + secret + hex_domain
    FULL_SECRET="ee${USER_SECRET}${HEX_DOMAIN}"
    echo -e "Пользователь: ${RED}$NAME${NC}"
    echo -e "https://t.me/proxy?server=$IP&port=$PROXY_PORT&secret=$FULL_SECRET"
    echo -e "tg://proxy?server=$IP&port=$PROXY_PORT&secret=$FULL_SECRET\n"
done

echo -e "${GREEN}Проверить статус: systemctl status telemt${NC}"
echo -e "${GREEN}Конфиг: /etc/telemt/telemt.toml${NC}"
