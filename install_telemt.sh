#!/bin/bash

# ==========================================================
# ПАРАМЕТРЫ И ВЕРСИЯ
# ==========================================================
CURRENT_VERSION="1.1.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# === БЛОК ТЕКСТОВЫХ СТРОК (РУСИФИКАЦИЯ) ===
L_MENU_HEADER="МЕНЕДЖЕР TELEMT"
L_STATUS_LABEL="Статус прокси:"
L_STATUS_RUN="Работает (Active)"
L_STATUS_STOP="Остановлен (Inactive)"
L_STATUS_NONE="Не установлен"

# Категории главного меню
L_CAT_1="Управление пользователями"
L_CAT_2="Управление сервисом (Запуск/Стоп)"
L_CAT_3="Настройки прокси (Порт/SNI/Лог)"
L_CAT_4="Обслуживание менеджера"
L_CAT_0="Выход"

# Подменю Пользователи
L_USR_1="Список пользователей и ссылки"
L_USR_2="Добавить нового пользователя"
L_USR_3="Удалить пользователя"
L_USR_4="Настроить лимит IP адресов"

L_PROMPT_BACK="0 - Назад"
L_MSG_WAIT_ENTER="Нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED="Ошибка: Прокси еще не установлен в системе!"
L_MSG_UPDATE_OK="Менеджер успешно обновлен! Перезапуск..."
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
    curl -sSL -f "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

wait_user() {
    echo -e "\n${YELLOW}$L_MSG_WAIT_ENTER${NC}"
    read -r
}

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

check_updates() {
    REMOTE_VER=$(curl -sSL -f "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_INFO=" (Доступно v$REMOTE_VER)"
    else
        UPDATE_INFO=""
    fi
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${MAIN_COLOR}=== ССЫЛКИ ДЛЯ: $target_user ===${NC}"
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}Ссылки не найдены. Проверьте статус сервиса.${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
            else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi
        done
    fi
}

# --- ПОДМЕНЮ 1: ПОЛЬЗОВАТЕЛИ ---
submenu_users() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║        УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ       ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_USR_1${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_USR_2${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_USR_3${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_USR_4${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "Выберите действие: " subchoice
        
        case $subchoice in
            1) # Список и ссылки
                while true; do
                    mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                    clear; echo -e "${BOLD}${MAIN_COLOR}=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===${NC}"
                    for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                    echo -e "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}"
                    read -p "Номер пользователя для ссылок: " U_IDX
                    [[ "$U_IDX" == "0" ]] && break
                    if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                        show_links "${USERS[$((U_IDX-1))]}"; wait_user
                    fi
                done ;;
            2) # Добавить
                read -p "Имя нового пользователя: " UNAME
                if [ -n "$UNAME" ]; then
                    read -p "Лимит IP (0 - безлимит): " ULIM; ULIM=${ULIM:-0}
                    U_SEC=$(openssl rand -hex 16)
                    sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
                    echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}Пользователь '$UNAME' добавлен.${NC}"
                    wait_user
                fi ;;
            3) # Удалить
                mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                read -p "Номер для удаления: " U_IDX
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    DEL_NAME="${USERS[$((U_IDX-1))]}"
                    sed -i "/^$DEL_NAME =/d" $CONF_FILE
                    systemctl restart telemt && echo -e "${RED}Удален: $DEL_NAME${NC}"
                    wait_user
                fi ;;
            4) # Лимит IP
                mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                for i in "${!USERS[@]}"; do
                    # Ищем строку лимита (где нет кавычек)
                    CUR_LIM=$(grep "^${USERS[$i]} =" $CONF_FILE | grep -v "\"" | awk '{print $3}')
                    printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC} (Лимит: ${YELLOW}%s${NC})\n" "$((i+1))" "${USERS[$i]}" "${CUR_LIM:-0}"
                done
                read -p "Номер для смены лимита: " U_IDX
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    T_USER="${USERS[$((U_IDX-1))]}"
                    read -p "Новый лимит IP (0 - безлимит): " N_LIM
                    sed -i "/^$T_USER = [0-9]/d" $CONF_FILE
                    sed -i "/\[access.user_max_unique_ips\]/a $T_USER = ${N_LIM:-0}" $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}Лимит обновлен.${NC}"
                    wait_user
                fi ;;
            0) break ;;
        esac
    done
}

# --- ПОДМЕНЮ 2: СЕРВИС ---
submenu_service() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║           УПРАВЛЕНИЕ СЕРВИСОМ          ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}УСТАНОВИТЬ Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Перезапустить прокси${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Остановить прокси${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "Выберите действие: " subchoice
        case $subchoice in
            1) # Полная установка
                read -p "Порт (443): " P_PORT; P_PORT=${P_PORT:-443}
                read -p "SNI домен (google.com): " P_SNI; P_SNI=${P_SNI:-google.com}
                read -p "Имя первого юзера: " P_USER; P_USER=${P_USER:-admin}
                read -p "Лимит IP (0 - безл): " P_LIM; P_LIM=${P_LIM:-0}
                run_step "Пакеты" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
                ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
                run_step "Бинарник" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
                useradd -d /opt/telemt -m -r -U telemt 2>/dev/null; mkdir -p $CONF_DIR
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
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$P_SNI"

[access.user_max_unique_ips]
$P_USER = $P_LIM

[access.users]
$P_USER = "$(openssl rand -hex 16)"
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
                run_step "Запуск" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                wait_user ;;
            2) [ -f "$SERVICE_FILE" ] && systemctl restart telemt && echo "Ок" || echo "$L_ERR_NOT_INSTALLED"; wait_user ;;
            3) [ -f "$SERVICE_FILE" ] && systemctl stop telemt && echo "Ок" || echo "$L_ERR_NOT_INSTALLED"; wait_user ;;
            0) break ;;
        esac
    done
}

# --- ПОДМЕНЮ 3: НАСТРОЙКИ ---
submenu_settings() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║            НАСТРОЙКИ ПРОКСИ            ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}Системный лог (статус)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Изменить порт${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Изменить SNI домен${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "Выберите действие: " subchoice
        case $subchoice in
            1) [ -f "$SERVICE_FILE" ] && systemctl status telemt || echo "$L_ERR_NOT_INSTALLED"; wait_user ;;
            2) read -p "Новый порт: " N_PORT; sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && systemctl restart telemt; wait_user ;;
            3) read -p "Новый SNI: " N_SNI; sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt; wait_user ;;
            0) break ;;
        esac
    done
}

# --- ГЛАВНОЕ МЕНЮ ---
check_updates
while true; do
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║        %s (v%s)        ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi
    printf "  %s %b\n" "$L_STATUS_LABEL" "$STATUS"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_CAT_1${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_CAT_2${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_CAT_3${NC}\n"
    if [ -n "$UPDATE_INFO" ]; then
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}%s ${YELLOW}%s${NC}\n" "$L_CAT_4" "$UPDATE_INFO"
    else printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_CAT_4${NC}\n"; fi
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_CAT_0${NC}\n"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    read -p "Выберите раздел: " mainchoice
    case $mainchoice in
        1) submenu_users ;;
        2) submenu_service ;;
        3) submenu_settings ;;
        4) # Менеджер
            clear; echo -e "${BOLD}${MAIN_COLOR}=== ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА ===${NC}"
            echo -e "1 - Обновить скрипт\n2 - УДАЛИТЬ ВСЁ\n0 - Назад"
            read -p "Действие: " mchoice
            [[ "$mchoice" == "1" ]] && curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME" && chmod +x "$CLI_NAME" && exec "$CLI_NAME"
            [[ "$mchoice" == "2" ]] && systemctl stop telemt; rm -rf $SERVICE_FILE $BIN_PATH $CLI_NAME $CONF_DIR /opt/telemt; exit 0
            ;;
        0) exit 0 ;;
    esac
done
