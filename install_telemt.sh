#!/bin/bash

# ==========================================================
# ПАРАМЕТРЫ И ВЕРСИЯ
# ==========================================================
CURRENT_VERSION="1.1.5"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# === ЦВЕТОВАЯ ПАЛИТРА ===
BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m'   # Желто-зеленый (Рамки)
ORANGE='\033[1;38;5;214m'     # Оранжевый (Вопросы)
SKY_BLUE='\033[1;38;5;81m'    # Голубой (Процессы)
GREEN='\033[1;32m'            # Зеленый (Успех)
RED='\033[1;31m'              # Красный (Ошибка)
YELLOW='\033[1;33m'           # Желтый (Внимание)

# === БЛОК ТЕКСТОВЫХ СТРОК ===
L_MENU_HEADER="МЕНЕДЖЕР TELEMT"
L_STATUS_LABEL="Статус прокси:"
L_STATUS_RUN="Работает (Active)"
L_STATUS_STOP="Остановлен (Inactive)"
L_STATUS_NONE="Не установлен"

L_MAIN_1="Управление сервисом (Установка/Старт/Стоп)"
L_MAIN_2="Управление пользователями (Ссылки/Лимиты)"
L_MAIN_3="Настройки прокси (Порт/SNI/Лог)"
L_MAIN_4="Обслуживание менеджера"
L_MAIN_0="Выход"

L_PROMPT_BACK="Назад"
L_MSG_WAIT_ENTER="Нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED="Ошибка: Прокси еще не установлен в системе!"
# ==========================================================

# Пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: Нужен root${NC}"; exit 1; fi

# --- ФУНКЦИИ ---

wait_user() {
    printf "\n${ORANGE}${BOLD}$L_MSG_WAIT_ENTER${NC}"
    read -r
}

run_step() {
    local msg="$1"
    local cmd="$2"
    printf "  ${BOLD}${SKY_BLUE}*${NC} %-35s " "$msg..."
    if eval "$cmd" > /dev/null 2>&1; then
        printf "${GREEN}[ГОТОВО]${NC}\n"
    else
        printf "${RED}[ОШИБКА]${NC}\n"
        return 1
    fi
}

check_updates() {
    REMOTE_VER=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_INFO=" \033[1;33m(Доступно v$REMOTE_VER)\033[0m"
    else UPDATE_INFO=""; fi
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${MAIN_COLOR}=== ССЫЛКИ ДЛЯ: $target_user ===${NC}"
    sleep 2
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}Ссылки не найдены. Проверьте статус прокси.${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
            else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi
        done
    fi
}

# Функция очистки только прокси (без удаления менеджера)
cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE}--- Удаление компонентов прокси ---${NC}"
    run_step "Остановка службы" "systemctl stop telemt"
    run_step "Отключение автозагрузки" "systemctl disable telemt"
    run_step "Удаление бинарника" "rm -f $BIN_PATH"
    run_step "Удаление конфигурации" "rm -rf $CONF_DIR"
    run_step "Удаление файлов пользователя" "rm -rf /opt/telemt"
    run_step "Удаление системного юнита" "rm -f $SERVICE_FILE"
    run_step "Удаление пользователя" "userdel telemt"
    run_step "Перезагрузка демонов" "systemctl daemon-reload"
    echo -e "${GREEN}${BOLD}Прокси успешно удален. Менеджер остается в системе.${NC}"
}

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR}--- Настройка и установка Telemt ---${NC}"
    read -p "$(echo -e $ORANGE"Укажите порт (443): "$NC)" P_PORT; P_PORT=${P_PORT:-443}
    read -p "$(echo -e $ORANGE"Укажите SNI (google.com): "$NC)" P_SNI; P_SNI=${P_SNI:-google.com}
    read -p "$(echo -e $ORANGE"Имя пользователя (admin): "$NC)" P_USER; P_USER=${P_USER:-admin}
    read -p "$(echo -e $ORANGE"Лимит IP (0 - безлимит): "$NC)" P_LIM; P_LIM=${P_LIM:-0}
    echo -e ""
    run_step "Установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    run_step "Загрузка бинарника" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    CMD_CONF="useradd -d /opt/telemt -m -r -U telemt 2>/dev/null || true; mkdir -p $CONF_DIR; 
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
[access.user_max_unique_ips]
$P_USER = $P_LIM
[access.users]
$P_USER = \"\$(openssl rand -hex 16)\"
EOF
    chown -R telemt:telemt $CONF_DIR"
    run_step "Создание конфига" "$CMD_CONF"
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
    run_step "Настройка службы" "$CMD_SRV"
    run_step "Запуск прокси" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    echo -e "\n${BOLD}${GREEN}Установка завершена успешно!${NC}"
    show_links "$P_USER"
}

# --- ПОДМЕНЮ ---

submenu_service() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║           УПРАВЛЕНИЕ СЕРВИСОМ          ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}УСТАНОВИТЬ Telemt (с нуля)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Перезапустить прокси${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Остановить прокси${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        echo -e "${MAIN_COLOR}------------------------------------------${NC}"
        read -p "$(echo -e $ORANGE"Выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_telemt; wait_user ;;
            2) [ -f "$SERVICE_FILE" ] && systemctl restart telemt && echo -e "${GREEN}Ок${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            3) [ -f "$SERVICE_FILE" ] && systemctl stop telemt && echo -e "${YELLOW}Остановлено${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║        УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ       ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}Список пользователей и ссылки${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Добавить пользователя${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Удалить пользователя${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}Настроить лимит IP${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        echo -e "${MAIN_COLOR}------------------------------------------${NC}"
        read -p "$(echo -e $ORANGE"Выберите действие: "$NC)" subchoice
        case $subchoice in
            1) while true; do
                mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                clear; echo -e "${BOLD}${MAIN_COLOR}=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===${NC}"
                for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}Назад${NC}\n"
                read -p "$(echo -e $ORANGE"Номер пользователя: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    show_links "${USERS[$((U_IDX-1))]}"; wait_user
                fi
            done ;;
            2) read -p "$(echo -e $ORANGE"Имя пользователя: "$NC)" UNAME
                if [ -n "$UNAME" ]; then
                    read -p "$(echo -e $ORANGE"Лимит IP (0 - безлимит): "$NC)" ULIM; ULIM=${ULIM:-0}
                    U_SEC=$(openssl rand -hex 16)
                    sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
                    echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}Добавлен${NC}"; wait_user
                fi ;;
            3) mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                read -p "$(echo -e $ORANGE"Номер для удаления: "$NC)" U_IDX
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    DEL_NAME="${USERS[$((U_IDX-1))]}"; sed -i "/^$DEL_NAME =/d" $CONF_FILE
                    systemctl restart telemt && echo -e "${RED}Удален${NC}"; wait_user
                fi ;;
            4) mapfile -t USERS < <(grep "=" "$CONF_FILE" | grep -v "port" | grep -v "listen" | cut -d' ' -f1 | sort -u)
                for i in "${!USERS[@]}"; do
                    CUR_LIM=$(grep "^${USERS[$i]} =" $CONF_FILE | grep -v "\"" | awk '{print $3}')
                    printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC} (Лимит: ${YELLOW}%s${NC})\n" "$((i+1))" "${USERS[$i]}" "${CUR_LIM:-0}"
                done
                read -p "$(echo -e $ORANGE"Номер для лимита: "$NC)" U_IDX
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    T_USER="${USERS[$((U_IDX-1))]}"; read -p "$(echo -e $ORANGE"Новый лимит IP: "$NC)" N_LIM
                    sed -i "/^$T_USER = [0-9]/d" $CONF_FILE
                    sed -i "/\[access.user_max_unique_ips\]/a $T_USER = ${N_LIM:-0}" $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}Обновлено${NC}"; wait_user
                fi ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║            НАСТРОЙКИ ПРОКСИ            ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}Системный лог (статус)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Изменить порт${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}Изменить SNI домен${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        echo -e "${MAIN_COLOR}------------------------------------------${NC}"
        read -p "$(echo -e $ORANGE"Выберите действие: "$NC)" subchoice
        case $subchoice in
            1) systemctl status telemt; wait_user ;;
            2) read -p "$(echo -e $ORANGE"Новый порт: "$NC)" N_PORT
                if [[ $N_PORT =~ ^[0-9]+$ ]]; then
                    sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}Ок${NC}"
                else echo -e "${RED}Ошибка${NC}"; fi
                wait_user ;;
            3) read -p "$(echo -e $ORANGE"Новый SNI: "$NC)" N_SNI
                if [ -n "$N_SNI" ]; then
                    sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}Ок${NC}"
                else echo -e "${RED}Ошибка${NC}"; fi
                wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    check_updates
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}Обновить менеджер${UPDATE_INFO}${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}Удалить ТОЛЬКО прокси (сервис и конфиги)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}ПОЛНОЕ УДАЛЕНИЕ (включая менеджер)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        echo -e "${MAIN_COLOR}------------------------------------------${NC}"
        read -p "$(echo -e $ORANGE"Выберите действие: "$NC)" subchoice
        case $subchoice in
            1) echo -e "${SKY_BLUE}Обновление...${NC}"; if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
               sync; chmod +x "$CLI_NAME"; exec "$CLI_NAME";
               else echo -e "${RED}Ошибка${NC}"; wait_user; fi ;;
            2) read -p "$(echo -e $ORANGE"Удалить ТОЛЬКО прокси? (y/n): "$NC)" confirm
               [[ $confirm == "y" ]] && cleanup_proxy && wait_user ;;
            3) read -p "$(echo -e $ORANGE"Удалить ВСЁ ПОЛНОСТЬСТЬЮ? (y/n): "$NC)" confirm
               if [[ $confirm == "y" ]]; then cleanup_proxy; rm -f "$CLI_NAME"; echo -e "${RED}Всё удалено.${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# --- ГЛАВНЫЙ ЦИКЛ ---
while true; do
    check_updates
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║        %s (v%s)        ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi
    printf "  %s %b\n" "$L_STATUS_LABEL" "$STATUS"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}%s%b${NC}\n" "$L_MAIN_4" "$UPDATE_INFO"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    printf "${BOLD}${MAIN_COLOR}------------------------------------------${NC}\n"
    read -p "$(echo -e $ORANGE"Выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_manager ;;
        0) exit 0 ;;
        *) sleep 0.5 ;;
    esac
done
