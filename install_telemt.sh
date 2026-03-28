#!/bin/bash

# === ПАРАМЕТРЫ ВЕРСИИ ===
CURRENT_VERSION="1.0.1"

# Константы путей
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# Цветовая схема (Жирный шрифт + YellowGreen)
if [[ -t 1 ]]; then
    BOLD=$(tput bold)
    NORMAL=$(tput sgr0)
else
    BOLD=""
    NORMAL=""
fi

MAIN_COLOR='\033[38;5;148m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от имени root${NC}"
  exit 1
fi

# Регистрация команды 'telemt' в системе
if [ ! -f "$CLI_NAME" ]; then
    curl -sSL "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

# Функция проверки обновлений
check_updates() {
    REMOTE_VER=$(curl -sSL "${REPO_URL}?v=$(date +%s)" | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_TEXT=" ${YELLOW}(Доступно обновление до v$REMOTE_VER)${NC}"
    else
        UPDATE_TEXT=""
    fi
}

# --- ФУНКЦИИ ---

show_links() {
    echo -e "\n${BOLD}${MAIN_COLOR}=== ВАШИ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}Ошибка: Сначала установите прокси (пункт 1).${NC}"
        return
    fi
    
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]' 2>/dev/null)
    
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}Ожидание генерации ссылок...${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then
                [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then
                [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
            else
                echo -e "${BOLD}${MAIN_COLOR}$link${NC}"
            fi
        done
    fi
}

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR}--- Настройка и установка Telemt ---${NC}"
    read -p "Укажите порт (по умолчанию 443): " PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-443}
    read -p "Укажите домен маскировки (SNI, напр. google.com): " TLS_DOMAIN
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
NoNewPrivileges=true
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

# Предварительная проверка обновлений при запуске
check_updates

# --- МЕНЮ ---
while true; do
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║         МЕНЕДЖЕР TELEMT (v$CURRENT_VERSION)        ║${NC}\n"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    
    if [ ! -f "$SERVICE_FILE" ]; then
        STATUS="${BOLD}${RED}Не установлен${NC}"
    elif systemctl is-active --quiet telemt; then
        STATUS="${BOLD}${GREEN}Работает (Active)${NC}"
    else
        STATUS="${BOLD}${YELLOW}Остановлен (Inactive)${NC}"
    fi

    printf "  Статус: %b\n" "$STATUS"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}УСТАНОВИТЬ Telemt${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Проверить статус (лог)${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Показать ссылки${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}Добавить пользователя${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}Удалить пользователя${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 6 -${NC} ${BOLD}Изменить порт${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 7 -${NC} ${BOLD}Изменить SNI (домен)${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 8 -${NC} ${BOLD}Перезапустить прокси${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 9 -${NC} ${BOLD}Остановить прокси${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR}10 -${NC} ${BOLD}ОБНОВИТЬ МЕНЕДЖЕР${UPDATE_TEXT}${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR}11 -${NC} ${BOLD}УДАЛИТЬ ВСЁ (Uninstall)${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}Выход${NC}\n"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    
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
                echo -e "${BOLD}Текущие пользователи:${NC}"
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
            echo "Обновление из GitHub..."
            if curl -sSL "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
                chmod +x "$CLI_NAME"
                echo -e "${GREEN}Менеджер успешно обновлен!${NC}"
                sleep 1
                # Рестарт скрипта
                exec "$CLI_NAME"
            else
                echo -e "${RED}Ошибка при скачивании.${NC}"
                read -p "Enter..."
            fi
            ;;
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
