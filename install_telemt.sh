#!/bin/bash

# ==========================================================
# ПАРАМЕТРЫ И ВЕРСИЯ
# ==========================================================
CURRENT_VERSION="1.0.3"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# === БЛОК ТЕКСТОВЫХ СТРОК (ДЛЯ УДОБНОГО РЕДАКТИРОВАНИЯ) ===
L_MENU_HEADER="МЕНЕДЖЕР TELEMT"
L_STATUS_LABEL="Статус прокси:"
L_STATUS_RUN="Работает (Active)"
L_STATUS_STOP="Остановлен (Inactive)"
L_STATUS_NONE="Не установлен"

L_ITEM_1="УСТАНОВИТЬ Telemt (с нуля)"
L_ITEM_2="Проверить статус (системный лог)"
L_ITEM_3="Показать ссылки для Telegram"
L_ITEM_4="Добавить нового пользователя"
L_ITEM_5="Удалить пользователя"
L_ITEM_6="Изменить порт сервера"
L_ITEM_7="Изменить TLS домен (SNI)"
L_ITEM_8="Перезапустить прокси"
L_ITEM_9="Остановить прокси"
L_ITEM_10="ОБНОВИТЬ МЕНЕДЖЕР"
L_ITEM_11="УДАЛИТЬ ВСЁ (Uninstall)"
L_ITEM_0="Выход"

L_STEP_PKG="Установка системных пакетов"
L_STEP_BIN="Загрузка бинарника Telemt"
L_STEP_CONF="Создание конфигурации и прав"
L_STEP_SRV="Настройка Systemd сервиса"
L_STEP_START="Запуск прокси-сервера"

L_ERR_NOT_INSTALLED="Ошибка: Прокси еще не установлен в системе!"
L_ERR_PORT="Ошибка: Неверный формат порта (вводите только цифры)."
L_MSG_WAIT_ENTER="Нажмите [Enter], чтобы вернуться в меню..."
L_MSG_RESTART_OK="Прокси успешно перезапущен!"
L_MSG_STOP_OK="Прокси остановлен."
L_MSG_UPDATE_OK="Менеджер успешно обновлен! Перезапуск..."
L_MSG_DELETE_CONFIRM="Вы уверены, что хотите удалить ВСЁ? (y/n): "
# ==========================================================

# Константы путей
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"

# Цветовая схема
BOLD=$(tput bold)
MAIN_COLOR='\033[38;5;148m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите скрипт от root${NC}"
  exit 1
fi

# Регистрация команды 'telemt'
if [ ! -f "$CLI_NAME" ]; then
    curl -sSL "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

# Пауза
wait_user() {
    echo -e "\n${YELLOW}$L_MSG_WAIT_ENTER${NC}"
    read -r
}

# Функция для «чистого» выполнения шага
run_step() {
    local msg="$1"
    local cmd="$2"
    printf "  ${BOLD}${MAIN_COLOR}*${NC} %-40s " "$msg..."
    if eval "$cmd" > /dev/null 2>&1; then
        printf "${GREEN}[ГОТОВО]${NC}\n"
    else
        printf "${RED}[ОШИБКА]${NC}\n"
        return 1
    fi
}

# Проверка обновлений
check_updates() {
    REMOTE_VER=$(curl -sSL "${REPO_URL}?v=$(date +%s)" | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_INFO=" ${YELLOW}(Доступно v$REMOTE_VER)${NC}"
    else
        UPDATE_INFO=""
    fi
}

show_links() {
    echo -e "\n${BOLD}${MAIN_COLOR}=== ВАШИ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"
        return
    fi
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r '.data[].links.tls[]' 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}Ожидание генерации... (проверьте через 5 сек)${NC}"
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
    echo -e "\n${BOLD}${MAIN_COLOR}--- Установка Telemt ---${NC}"
    read -p "Порт (443): " P_PORT; P_PORT=${P_PORT:-443}
    read -p "SNI домен (google.com): " P_SNI; P_SNI=${P_SNI:-google.com}
    echo -e ""

    # 1. Пакеты (Подавляем окна needrestart)
    run_step "$L_STEP_PKG" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    
    # 2. Бинарник
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    run_step "$L_STEP_BIN" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
    # 3. Юзер и конфиг
    CMD_CONF="useradd -d /opt/telemt -m -r -U telemt 2>/dev/null; mkdir -p $CONF_DIR; 
    cat <<EOF > $CONF_FILE
[general]
use_middle_proxy = false
[general.modes]
classic = false
secure = false
tls = true
[server]
port = $P_PORT
[server.api]
enabled = true
listen = \"127.0.0.1:9091\"
[censorship]
tls_domain = \"$P_SNI\"
[access.users]
admin = \"\$(openssl rand -hex 16)\"
EOF
    chown -R telemt:telemt $CONF_DIR"
    run_step "$L_STEP_CONF" "$CMD_CONF"

    # 4. Сервис
    CMD_SRV="cat <<EOF > $SERVICE_FILE
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
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF"
    run_step "$L_STEP_SRV" "$CMD_SRV"

    # 5. Запуск
    run_step "$L_STEP_START" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"

    echo -e "\n${GREEN}Установка завершена успешно!${NC}"
    sleep 2
    show_links
}

# Предварительная проверка
check_updates

# --- ЦИКЛ МЕНЮ ---
while true; do
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║         %s (v%s)        ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi

    printf "  %s %b\n" "$L_STATUS_LABEL" "$STATUS"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_1"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_2"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_3"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_4"
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_5"
    printf "  ${BOLD}${MAIN_COLOR} 6 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_6"
    printf "  ${BOLD}${MAIN_COLOR} 7 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_7"
    printf "  ${BOLD}${MAIN_COLOR} 8 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_8"
    printf "  ${BOLD}${MAIN_COLOR} 9 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_9"
    printf "  ${BOLD}${MAIN_COLOR}10 -${NC} ${BOLD}%s%s${NC}\n" "$L_ITEM_10" "$UPDATE_INFO"
    printf "  ${BOLD}${MAIN_COLOR}11 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_11"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}%s${NC}\n" "$L_ITEM_0"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    
    read -p "Выберите действие: " choice

    case $choice in
        1) install_telemt; wait_user ;;
        2) 
            if [ -f "$SERVICE_FILE" ]; then systemctl status telemt; else echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; fi
            wait_user ;;
        3) show_links; wait_user ;;
        4)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; else
                read -p "Имя нового пользователя: " UNAME
                U_SEC=$(openssl rand -hex 16)
                echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                systemctl restart telemt && echo -e "${GREEN}Пользователь '$UNAME' добавлен.${NC}"
                show_links
            fi
            wait_user ;;
        5)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; else
                echo -e "${BOLD}Текущие пользователи:${NC}"
                grep -A 50 "\[access.users\]" $CONF_FILE | grep "=" | awk '{print $1}'
                read -p "Имя для удаления: " UNAME
                [ -n "$UNAME" ] && sed -i "/^$UNAME =/d" $CONF_FILE && systemctl restart telemt && echo -e "${YELLOW}Удален.${NC}"
            fi
            wait_user ;;
        6)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; else
                read -p "Новый порт: " N_PORT
                if [[ $N_PORT =~ ^[0-9]+$ ]]; then
                    sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}Порт изменен.${NC}"
                else echo -e "${RED}$L_ERR_PORT${NC}"; fi
            fi
            wait_user ;;
        7)
            if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; else
                read -p "Новый SNI: " N_SNI
                [ -n "$N_SNI" ] && sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}SNI изменен.${NC}"
            fi
            wait_user ;;
        8) 
            if [ -f "$SERVICE_FILE" ]; then 
                systemctl restart telemt && echo -e "${GREEN}$L_MSG_RESTART_OK${NC}"
            else echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; fi
            wait_user ;;
        9) 
            if [ -f "$SERVICE_FILE" ]; then
                systemctl stop telemt && echo -e "${YELLOW}$L_MSG_STOP_OK${NC}"
            else echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; fi
            wait_user ;;
        10)
            echo "Обновление из GitHub..."
            if curl -sSL "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
                chmod +x "$CLI_NAME"
                echo -e "${GREEN}$L_MSG_UPDATE_OK${NC}"
                sleep 1; exec "$CLI_NAME"
            else echo -e "${RED}Ошибка обновления.${NC}"; wait_user; fi ;;
        11)
            read -p "$L_MSG_DELETE_CONFIRM" confirm
            if [[ $confirm == "y" ]]; then
                systemctl stop telemt 2>/dev/null && systemctl disable telemt 2>/dev/null
                rm -f $SERVICE_FILE $BIN_PATH $CLI_NAME; rm -rf $CONF_DIR /opt/telemt
                userdel telemt 2>/dev/null && echo -e "${RED}Удалено.${NC}"; exit 0
            fi ;;
        0) exit 0 ;;
    esac
done
