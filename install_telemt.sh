#!/bin/bash

# Константы путей
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# Цветовая схема
# 148 - это максимально близкий к #9ACD32 (YellowGreen) в палитре 256 цветов
MAIN_COLOR='\033[1;38;5;148m' 
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # Сброс цвета

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root (через sudo)${NC}"
  exit 1
fi

# Регистрация команды 'telemt'
if [ ! -f "$CLI_NAME" ]; then
    curl -sSL "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

# --- ФУНКЦИИ ---

show_links() {
    echo -e "\n${MAIN_COLOR}=== ВАШИ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}Ошибка: Файл конфигурации не найден. Сначала установите прокси.${NC}"
        return
    fi
    
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]' 2>/dev/null)
    
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}Внимание: Ссылки еще не сгенерированы. Подождите пару секунд...${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then
                [ -n "$IP4" ] && echo -e "${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then
                [ -n "$IP6" ] && echo -e "${MAIN_COLOR}${link//::/$IP6}${NC}"
            else
                echo -e "${MAIN_COLOR}$link${NC}"
            fi
        done
    fi
}

install_telemt() {
    echo -e "\n${MAIN_COLOR}--- Настройка и установка Telemt ---${NC}"
    read -p "Укажите порт (по умолчанию 443): " PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-443}
    read -p "Укажите домен маскировки (SNI, напр. google.com): " TLS_DOMAIN
    TLS_DOMAIN=${TLS_DOMAIN:-google.com}

    echo -e "${MAIN_COLOR}Установка пакетов...${NC}"
    apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq
    
    echo -e "${MAIN_COLOR}Загрузка бинарника...${NC}"
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
Description=Telemt Proxy Service
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
    
    echo -e "${GREEN}Готово! Прокси установлен.${NC}"
    sleep 2
    show_links
}

# --- МЕНЮ ---
while true; do
    clear
    echo -e "${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
    echo -e "${MAIN_COLOR}║         МЕНЕДЖЕР TELEMT (CLI)          ║${NC}"
    echo -e "${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
    
    if [ ! -f "$SERVICE_FILE" ]; then
        STATUS="${RED}Не установлен${NC}"
    elif systemctl is-active --quiet telemt; then
        STATUS="${GREEN}Работает (Active)${NC}"
    else
        STATUS="${YELLOW}Остановлен (Inactive)${NC}"
    fi

    echo -e "  Статус: $STATUS"
    echo -e "${MAIN_COLOR}------------------------------------------${NC}"
    echo -e "  ${MAIN_COLOR}1)${NC} УСТАНОВИТЬ Telemt"
    echo -e "  ${MAIN_COLOR}2)${NC} Проверить статус (лог)"
    echo -e "  ${MAIN_COLOR}3)${NC} Показать ссылки"
    echo -e "  ${MAIN_COLOR}4)${NC} Добавить пользователя"
    echo -e "  ${MAIN_COLOR}5)${NC} Удалить пользователя"
    echo -e "  ${MAIN_COLOR}6)${NC} Изменить порт"
    echo -e "  ${MAIN_COLOR}7)${NC} Изменить SNI (домен)"
    echo -e "  ${MAIN_COLOR}8)${NC} Перезапустить прокси"
    echo -e "  ${MAIN_COLOR}9)${NC} Остановить прокси"
    echo -e "  ${MAIN_COLOR}10)${NC} ОБНОВИТЬ МЕНЕДЖЕР"
    echo -e "  ${MAIN_COLOR}11)${NC} УДАЛИТЬ ВСЁ"
    echo -e "  ${MAIN_COLOR}0)${NC} Выход"
    echo -e "${MAIN_COLOR}------------------------------------------${NC}"
    read -p "Выберите действие: " choice

    case $choice in
        1) install_telemt; read -p "Нажмите Enter..." ;;
        2) [ -f "$SERVICE_FILE" ] && systemctl status telemt || echo -e "${RED}Не установлен${NC}"; read -p "Нажмите Enter..." ;;
        3) show_links; read -p "Нажмите Enter..." ;;
        4)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}Установите прокси!${NC}"; else
                read -p "Имя пользователя: " UNAME
                U_SEC=$(openssl rand -hex 16)
                echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                systemctl restart telemt
                echo -e "${GREEN}Пользователь '$UNAME' добавлен.${NC}"
                show_links
            fi
            read -p "Нажмите Enter..." ;;
        5)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}Конфиг не найден.${NC}"; else
                echo "Текущие пользователи:"
                grep -A 50 "\[access.users\]" $CONF_FILE | grep "=" | awk '{print $1}'
                read -p "Имя для удаления: " UNAME
                [ -n "$UNAME" ] && sed -i "/^$UNAME =/d" $CONF_FILE && systemctl restart telemt && echo -e "${YELLOW}Удален.${NC}"
            fi
            read -p "Нажмите Enter..." ;;
        6)
            read -p "Новый порт: " N_PORT
            if [[ $N_PORT =~ ^[0-9]+$ ]]; then
                sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE
                systemctl restart telemt && echo -e "${GREEN}Порт изменен.${NC}"
            fi
            read -p "Нажмите Enter..." ;;
        7)
            read -p "Новый SNI: " N_SNI
            [ -n "$N_SNI" ] && sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}SNI изменен.${NC}"
            read -p "Нажмите Enter..." ;;
        8) systemctl restart telemt && echo "Перезапущено"; sleep 1 ;;
        9) systemctl stop telemt && echo "Остановлено"; sleep 1 ;;
        10)
            echo "Обновление..."
            curl -sSL "$REPO_URL" -o "$CLI_NAME" && chmod +x "$CLI_NAME" && echo -e "${GREEN}Обновлено!${NC}" && exit 0 ;;
        11)
            read -p "Удалить всё? (y/n): " confirm
            if [[ $confirm == "y" ]]; then
                systemctl stop telemt 2>/dev/null && systemctl disable telemt 2>/dev/null
                rm -f $SERVICE_FILE $BIN_PATH $CLI_NAME
                rm -rf $CONF_DIR /opt/telemt
                userdel telemt 2>/dev/null
                echo -e "${RED}Удалено.${NC}"
                exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
