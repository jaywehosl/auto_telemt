#!/bin/bash

# Константы
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите от root (sudo)${NC}"
  exit 1
fi

# Самокопирование в систему при запуске
if [ ! -f "$CLI_NAME" ]; then
    # Если запущен через пайп или из другого места - сохраняем как команду 'telemt'
    curl -sSL "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

# --- ФУНКЦИИ ---

show_links() {
    echo -e "\n${GREEN}=== ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}Конфиг не найден. Сначала установите Telemt.${NC}"
        return
    fi
    
    IP4=$(curl -4 -s --max-time 3 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 3 https://api64.ipify.org || echo "")
    
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]' 2>/dev/null)
    
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}API не отвечает. Попробуйте перезапустить сервис или подождать 5 сек.${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then
                [ -n "$IP4" ] && echo "${link//0.0.0.0/$IP4}"
            elif [[ $link == *"server=::"* ]]; then
                [ -n "$IP6" ] && echo "${link//::/$IP6}"
            else
                echo "$link"
            fi
        done
    fi
}

install_telemt() {
    echo -e "${YELLOW}--- Установка Telemt ---${NC}"
    read -p "Введите порт (по умолчанию 443): " PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-443}
    read -p "Введите TLS домен (SNI) (по умолчанию google.com): " TLS_DOMAIN
    TLS_DOMAIN=${TLS_DOMAIN:-google.com}

    apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq
    
    ARCH=$(uname -m)
    LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    
    curl -L "$URL" | tar -xz
    mv telemt $BIN_PATH && chmod +x $BIN_PATH
    
    useradd -d /opt/telemt -m -r -U telemt 2>/dev/null
    mkdir -p $CONF_DIR

    cat <<EOF > $CONF_FILE
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
admin = "$(openssl rand -hex 16)"
EOF
    chown -R telemt:telemt $CONF_DIR

    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Telemt Proxy
After=network-online.target
[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=$BIN_PATH $CONF_FILE
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable telemt
    systemctl restart telemt
    echo -e "${GREEN}Установка завершена!${NC}"
    sleep 2
    show_links
}

# --- ОСНОВНОЕ МЕНЮ ---
while true; do
    clear
    echo -e "${GREEN}====================================${NC}"
    echo -e "${GREEN}       МЕНЕДЖЕР TELEMT CLI          ${NC}"
    echo -e "${GREEN}====================================${NC}"
    
    # Проверка статуса для индикации в меню
    if systemctl is-active --quiet telemt; then
        STATUS="${GREEN}Работает${NC}"
    else
        STATUS="${RED}Остановлен/Не установлен${NC}"
    fi

    echo -e "Статус: $STATUS"
    echo -e "------------------------------------"
    echo "1) УСТАНОВИТЬ Telemt (с нуля)"
    echo "2) Статус сервиса (systemctl status)"
    echo "3) Показать ссылки для Telegram"
    echo "4) Добавить нового пользователя"
    echo "5) Удалить пользователя"
    echo "6) Изменить порт сервера"
    echo "7) Изменить TLS домен (SNI)"
    echo "8) Перезапустить прокси"
    echo "9) Остановить прокси"
    echo "10) ОБНОВИТЬ МЕНЕДЖЕР (из GitHub)"
    echo "11) УДАЛИТЬ ВСЁ (Uninstall)"
    echo "0) Выход"
    echo -e "------------------------------------"
    read -p "Выберите пункт: " choice

    case $choice in
        1) install_telemt ;;
        2) systemctl status telemt; read -p "Нажмите Enter для возврата..." ;;
        3) show_links; read -p "Нажмите Enter для возврата..." ;;
        4)
            read -p "Имя пользователя: " UNAME
            U_SEC=$(openssl rand -hex 16)
            echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
            systemctl restart telemt
            echo -e "${GREEN}Добавлен: $UNAME${NC}"
            show_links
            read -p "Нажмите Enter для возврата..."
            ;;
        5)
            echo "Пользователи в конфиге:"
            grep -A 50 "\[access.users\]" $CONF_FILE | grep "=" | awk '{print $1}'
            read -p "Кого удалить?: " UNAME
            sed -i "/^$UNAME =/d" $CONF_FILE
            systemctl restart telemt
            echo -e "${RED}Удален: $UNAME${NC}"
            read -p "Enter..."
            ;;
        6)
            read -p "Новый порт: " N_PORT
            sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE
            systemctl restart telemt
            echo -e "${GREEN}Порт изменен на $N_PORT${NC}"
            read -p "Enter..."
            ;;
        7)
            read -p "Новый SNI (apple.com): " N_SNI
            sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE
            systemctl restart telemt
            echo -e "${GREEN}SNI изменен на $N_SNI${NC}"
            read -p "Enter..."
            ;;
        8) systemctl restart telemt; echo "Перезапущено"; sleep 1 ;;
        9) systemctl stop telemt; echo "Остановлено"; sleep 1 ;;
        10)
            echo "Обновление скрипта..."
            curl -sSL "$REPO_URL" -o "$CLI_NAME"
            chmod +x "$CLI_NAME"
            echo -e "${GREEN}Менеджер обновлен! Перезапустите команду 'telemt'${NC}"
            exit 0
            ;;
        11)
            read -p "Удалить всё? (y/n): " confirm
            if [[ $confirm == "y" ]]; then
                systemctl stop telemt && systemctl disable telemt
                rm -f $SERVICE_FILE $BIN_PATH $CLI_NAME
                rm -rf $CONF_DIR /opt/telemt
                userdel telemt 2>/dev/null
                echo -e "${RED}Всё удалено.${NC}"
                exit 0
            fi
            ;;
        0) exit 0 ;;
        *) echo "Неверный ввод"; sleep 1 ;;
    esac
done
