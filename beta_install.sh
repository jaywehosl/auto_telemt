#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.3.4-zapret"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

# === color grade ===
BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m' # yellow-green
ORANGE='\033[1;38;5;214m' # orange 
SKY_BLUE='\033[1;38;5;81m' # blue
GREEN='\033[1;32m' # green
RED='\033[1;31m' # red
YELLOW='\033[1;33m' # yellow

# === strings ===
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_LABEL="cтатус Telemt:"
L_STATUS_RUN="работает"
L_STATUS_STOP="остановлен"
L_STATUS_NONE="не установлен"

L_MAIN_1="управление сервисом"
L_MAIN_2="управление пользователями"
L_MAIN_3="настройки Telemt"
L_MAIN_4="управление Zapret (TPWS)"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

L_PROMPT_BACK="назад"
L_MSG_WAIT_ENTER=" нажмите[Enter] для продолжения..."
L_ERR_NOT_INSTALLED=" ошибка: сервис еще не установлен!"
# ==========================================================

# path
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"

ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}ошибка, запустите скрипт с root правами!${NC}"; exit 1; fi

# --- functions ---

wait_user() {
    printf "\n${ORANGE}${BOLD}$L_MSG_WAIT_ENTER${NC}"
    read -r
}

run_step() {
    local msg="$1"
    local cmd="$2"
    printf " ${BOLD}${SKY_BLUE}\*${NC} %-35s " "$msg..."
    if eval "$cmd" > /dev/null 2>&1; then
        printf "${GREEN}[готово]${NC}\n"
    else
        printf "${RED}[ошибка!]${NC}\n"
        return 1
    fi
}

check_updates() {
    REMOTE_VER=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_INFO=" \033[1;33m(новая версия v$REMOTE_VER)\033[0m"
    else
        UPDATE_INFO=""
    fi
}

# get user list function
get_user_list() {
    if [ -f "$CONF_FILE" ]; then
        # we take everything after [access.users] and look for с '=', grab first word
        sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u
    fi
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${SKY_BLUE} ключи подключения для пользователя $target_user:${NC}"
    sleep 1.5
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] ||[ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}ключи подключения не найдены, проверьте статус сервиса${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
            else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi
        done
    fi
}

cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE} удаляем компоненты Telemt...${NC}"
    run_step "остановка службы" "systemctl stop telemt"
    run_step "отключение автозагрузки" "systemctl disable telemt"
    run_step "удаление бинарных файлов" "rm -f $BIN_PATH"
    run_step "удаление файлов конфигураций" "rm -rf $CONF_DIR"
    run_step "удаление системных файлов" "rm -rf /opt/telemt"
    run_step "удаление системного юнита" "rm -f $SERVICE_FILE"
    run_step "удаление пользователей" "userdel telemt 2>/dev/null || true"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
    echo -e "${GREEN}${BOLD} Telemt успешно удалён${NC}"
}

cleanup_zapret() {
    echo -e "\n${BOLD}${SKY_BLUE} удаляем компоненты Zapret...${NC}"
    run_step "остановка службы" "systemctl stop zapret-tpws 2>/dev/null || true"
    run_step "отключение автозагрузки" "systemctl disable zapret-tpws 2>/dev/null || true"
    run_step "удаление системного юнита" "rm -f $ZAPRET_SERVICE"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
    run_step "удаление файлов программы" "rm -rf $ZAPRET_DIR"
    echo -e "${GREEN}${BOLD} Zapret успешно удалён${NC}"
}

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR} настройка и установка Telemt${NC}"
    read -p "$(echo -e $SKY_BLUE" укажите порт для Telemt ${MAIN_COLOR}(по умолчанию сервис работает на 443 порту): "$NC)" P_PORT; P_PORT=${P_PORT:-443}
    read -p "$(echo -e $SKY_BLUE" укажите SNI для TLS ${MAIN_COLOR}(возможно использовать любой валидный SNI): "$NC)" P_SNI; P_SNI=${P_SNI:-google.com}
    
    while true; do
        read -p "$(echo -e $SKY_BLUE" введите имя пользователя: "$NC)" P_USER; P_USER=${P_USER:-admin}
        if [[ "$P_USER" =~ ^[a-zA-Z0-9]+$ ]]; then
            break
        else
            echo -e " ${RED}ошибка: имя должно содержать только латинские буквы и цифры!${NC}"
        fi
    done

    read -p "$(echo -e $SKY_BLUE" задайте лимит IP адресов ${MAIN_COLOR}(если лимит не нужен, введите 0): "$NC)" P_LIM; P_LIM=${P_LIM:-0}
    echo -e ""
    run_step "установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    run_step "загрузка бинарных файлов" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
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
    run_step "создание конфига" "$CMD_CONF"
    
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
    run_step "настройка службы" "$CMD_SRV"
    run_step "запуск Telemt" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    echo -e "\n${BOLD}${GREEN} установка завершена успешно!${NC}"
    show_links "$P_USER"
}

install_zapret() {
    echo -e "\n${BOLD}${MAIN_COLOR} настройка и установка Zapret (TPWS)${NC}"
    run_step "установка зависимостей" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
    run_step "очистка старой папки" "rm -rf $ZAPRET_DIR"
    run_step "загрузка исходников Zapret" "git clone --depth=1 https://github.com/bol-van/zapret.git $ZAPRET_DIR"
    run_step "сборка программы" "make -C $ZAPRET_DIR"
    
    CMD_SRV="cat <<EOF > $ZAPRET_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target

[Service]
Type=simple
User=root
ExecStart=$ZAPRET_DIR/tpws/tpws --port=1080 --socks --disorder --split-pos=host --mss=1300
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF"
    run_step "создание службы" "$CMD_SRV"
    run_step "запуск Zapret" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
    echo -e "\n${BOLD}${GREEN} установка Zapret завершена успешно!${NC}"
}

# --- submenu logic ---

submenu_service() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║          УПРАВЛЕНИЕ СЕРВИСОМ           ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}перезапустить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE" выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_telemt; wait_user ;;
            2)[ -f "$SERVICE_FILE" ] && systemctl restart telemt && echo -e "${GREEN} Telemt перезапущен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            3) [ -f "$SERVICE_FILE" ] && systemctl stop telemt && echo -e "${YELLOW} Telemt остановлен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║       УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ        ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}список пользователей и ссылки${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}добавить пользователя${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удаление пользователей${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}настроить лимит IP${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE" выберите действие: "$NC)" subchoice
        case $subchoice in
            1) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                echo -e "${BOLD}${MAIN_COLOR}║          СПИСОК ПОЛЬЗОВАТЕЛЕЙ          ║${NC}"
                echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do printf " ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
                read -p "$(echo -e $ORANGE" введите номер пользователя: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] &&[ "$U_IDX" -le "${#USERS[@]}" ]; then
                    show_links "${USERS[$((U_IDX-1))]}"; wait_user
                fi
               done ;;
            2) while true; do
                read -p "$(echo -e $ORANGE" введите имя пользователя: "$NC)" UNAME
                if [[ "$UNAME" =~ ^[a-zA-Z0-9]+$ ]]; then
                    break
                else
                    echo -e " ${RED}ошибка! имя пользователя должно содержать только латинские буквы и цифры!${NC}"
                fi
               done
               if [ -n "$UNAME" ]; then
                   read -p "$(echo -e $ORANGE" задайте лимит IP адресов (если лимит не нужен, введите 0): "$NC)" ULIM; ULIM=${ULIM:-0}
                   U_SEC=$(openssl rand -hex 16)
                   sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
                   echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                   systemctl restart telemt && echo -e "${GREEN} пользователь добавлен${NC}"; wait_user
               fi ;;
            3) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                echo -e "${BOLD}${MAIN_COLOR}║         УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЯ          ║${NC}"
                echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do printf " ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
                read -p "$(echo -e $ORANGE" введите номер пользователя для удаления: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    DEL_NAME="${USERS[$((U_IDX-1))]}"
                    sed -i "/^$DEL_NAME =/d" $CONF_FILE
                    systemctl restart telemt && echo -e "${RED} пользователь удалён: $DEL_NAME${NC}"
                    wait_user
                fi
               done ;;
            4) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                echo -e "${BOLD}${MAIN_COLOR}║           ЛИМИТЫ IP АДРЕСОВ            ║${NC}"
                echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do
                    CUR_LIM=$(grep "^${USERS[$i]} =" $CONF_FILE | grep -v "\"" | awk '{print $3}')
                    printf " ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC} (текущий лимит: ${YELLOW}%s${NC})\n" "$((i+1))" "${USERS[$i]}" "${CUR_LIM:-0}"
                done
                printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}Назад${NC}\n"
                read -p "$(echo -e $ORANGE" введите номер пользователя для смены лимита: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] &&[ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    T_USER="${USERS[$((U_IDX-1))]}"; read -p "$(echo -e $ORANGE" новый лимит IP: "$NC)" N_LIM
                    sed -i "/^$T_USER = [0-9]/d" $CONF_FILE
                    sed -i "/\[access.user_max_unique_ips\]/a $T_USER = ${N_LIM:-0}" $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN} лимит IP обновлён${NC}"; wait_user
                fi
               done ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║            НАСТРОЙКИ TELEMT            ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}системный лог${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}изменить порт${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}изменить SNI домен${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE" выберите действие: "$NC)" subchoice
        case $subchoice in
            1) systemctl status telemt; wait_user ;;
            2) read -p "$(echo -e $ORANGE" введите новый порт: "$NC)" N_PORT
               if [[ $N_PORT =~ ^[0-9]+$ ]]; then
                   sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}порт изменён, сервис перезапущен${NC}"
               else echo -e "${RED}ошибка!${NC}"; fi
               wait_user ;;
            3) read -p "$(echo -e $ORANGE" введите новый SNI: "$NC)" N_SNI
               if [ -n "$N_SNI" ]; then
                   sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}SNI изменен, сервис перезапущен${NC}"
               else echo -e "${RED}ошибка!${NC}"; fi
               wait_user ;;
            0) break ;;
        esac
    done
}

submenu_zapret() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║           УПРАВЛЕНИЕ ZAPRET            ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить/обновить Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}перезапустить Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}удалить Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE" выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_zapret; wait_user ;;
            2)[ -f "$ZAPRET_SERVICE" ] && systemctl restart zapret-tpws && echo -e "${GREEN} Zapret перезапущен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            3) [ -f "$ZAPRET_SERVICE" ] && systemctl stop zapret-tpws && echo -e "${YELLOW} Zapret остановлен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            4) 
                read -p "$(echo -e ${RED}" внимание! это действие полностью удалит Zapret! продолжить? ${MAIN_COLOR}(y/n):"$NC)" confirm
                if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then cleanup_zapret; wait_user; fi ;;
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
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}обновить менеджер${UPDATE_INFO}${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}удалить сервис Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}полная очистка (Telemt + Zapret)${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE" выберите действие: "$NC)" subchoice
        case $subchoice in
            1) echo -e "${SKY_BLUE} обновление...${NC}"; if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
                sync; chmod +x "$CLI_NAME"; echo -e "${GREEN}Готово!${NC}"; sleep 1; exec "$CLI_NAME";
               else echo -e "${RED}ошибка${NC}"; wait_user; fi ;;
            2) read -p "$(echo -e ${RED}" внимание! это действие удалит сервис Telemt, его файлы конфигурации и всех созданных пользователей! продолжить? ${MAIN_COLOR}(y/n):"$NC)" confirm
               if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then cleanup_proxy && wait_user; fi ;;
            3) read -p "$(echo -e ${RED}" внимание! это действие полностью удалит менеджер СТАЛИН-3000 и все его компоненты (Telemt, Zapret)! продолжить? ${MAIN_COLOR}(y/n):"$NC)" confirm
               if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then cleanup_proxy; cleanup_zapret; rm -f "$CLI_NAME"; echo -e "${RED}${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# --- main cycle ---
while true; do
    check_updates
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║          %s (v%s)        ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi
    
    if [ ! -f "$ZAPRET_SERVICE" ]; then Z_STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet zapret-tpws; then Z_STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else Z_STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi

    printf " %s %b\n" " $L_STATUS_LABEL" "$STATUS"
    printf " %s %b\n\n" " cтатус Zapret:" "$Z_STATUS"
    
    printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}%s%b${NC}\n" "$L_MAIN_5" "$UPDATE_INFO"
    printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    
    read -p "$(echo -e $ORANGE" выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) exit 0 ;;
        *) sleep 0.5 ;;
    esac
done
