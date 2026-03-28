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

# 7. Запуск (Рестарт тут!)
systemctl daemon-reload
systemctl enable telemt
systemctl restart telemt

echo -e "${GREEN}Сервис перезапущен. Финализация ссылок...${NC}"

# Небольшая пауза, чтобы API проснулось
sleep 3

# 8. Определение внешних IP (v4 и v6) для замены заглушек
IP4=$(curl -4 -s --max-time 5 https://api.ipify.org || echo "")
IP6=$(curl -6 -s --max-time 5 https://api64.ipify.org || echo "")

# 9. Вывод ссылок
echo -e "\n${GREEN}=== ВАШИ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]')

if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
    echo "Ошибка: API не отвечает. Попробуй позже команду:"
    echo "curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]'"
else
    # Обработка ссылок: меняем 0.0.0.0 на v4 и :: на v6
    for link in $LINKS; do
        if [[ $link == *"server=0.0.0.0"* && -n "$IP4" ]]; then
            echo "${link//0.0.0.0/$IP4}"
        elif [[ $link == *"server=::"* ]]; then
            if [ -n "$IP6" ]; then
                echo "${link//::/$IP6}"
            else
                # Если IPv6 на сервере нет, просто не выводим битую ссылку
                continue
            fi
        else
            echo "$link"
        fi
    done
fi

echo -e "\n${GREEN}Конфиг: /etc/telemt/telemt.toml${NC}"
