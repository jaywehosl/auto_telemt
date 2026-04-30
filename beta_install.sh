#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.3.8"
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
L_STATUS_LABEL="статус Telemt:"
L_Z_STATUS_LABEL="статус Zapret:"
L_STATUS_RUN="работает"
L_STATUS_STOP="остановлен"
L_STATUS_NONE="не установлен"

L_MAIN_1="управление сервисом Telemt"
L_MAIN_2="управление пользователями Telemt"
L_MAIN_3="настройки Telemt"
L_MAIN_4="управление Zapret (TPWS)"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

L_PROMPT_BACK="назад"
L_MSG_WAIT_ENTER=" нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED=" ошибка: сервис Telemt еще не установлен!"
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

# --- internal helpers ---

draw_header() {
    local title="$1"
    local width=44
    local text_len=${#title}
    local padding=$(( (width - text_len) / 2 ))
    local extra=$(( (width - text_len) % 2 ))

    printf "${BOLD}${MAIN_COLOR}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║${NC}%*s%s%*s${BOLD}${MAIN_COLOR}║${NC}\n" "$padding" "" "$title" "$((padding + extra))" ""
    printf "${BOLD}${MAIN_COLOR}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Функция вывода статусов для всех меню
print_status_block() {
    local s1 s2
    if [ ! -f "$SERVICE_FILE" ]; then s1="${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then s1="${GREEN}$L_STATUS_RUN${NC}"
    else s1="${YELLOW}$L_STATUS_STOP${NC}"; fi

    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet zapret-tpws; then s2="${GREEN}$L_STATUS_RUN${NC}"
    else s2="${YELLOW}$L_STATUS_STOP${NC}"; fi

    printf " %-20s %b\n" "$L_STATUS_LABEL" "$s1"
    printf " %-20s %b\n" "$L_Z_STATUS_LABEL" "$s2"
}

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

get_user_list() {
    if [ -f "$CONF_FILE" ]; then
        sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u
    fi
}

# --- logic ---

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${SKY_BLUE} ключи подключения для пользователя $target_user:${NC}"
    sleep 0.5
    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_NOT_FOUND")
    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e " ${YELLOW}ключи не найдены, проверьте работу сервиса${NC}"
    else
        for link in $LINKS; do
            echo -e " ${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
        done
    fi
}

cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE} удаляем компоненты Telemt...${NC}"
    run_step "остановка службы" "systemctl stop telemt"
    run_step "отключение автозагрузки" "systemctl disable telemt"
    run_step "удаление бинарных файлов" "rm -f $BIN_PATH"
    run_step "удаление файлов конфигураций" "rm -rf $CONF_DIR"
    run_step "удаление системных юнитов" "rm -f $SERVICE_FILE"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
}

cleanup_zapret() {
    echo -e "\n${BOLD}${SKY_BLUE} удаляем компоненты Zapret...${NC}"
    run_step "остановка службы" "systemctl stop zapret-tpws 2>/dev/null || true"
    run_step "отключение автозагрузки" "systemctl disable zapret-tpws 2>/dev/null || true"
    run_step "удаление системного юнита" "rm -f $ZAPRET_SERVICE"
    run_step "удаление файлов программы" "rm -rf $ZAPRET_DIR"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
}

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR} настройка и установка Telemt${NC}"
    read -p " $(echo -e $SKY_BLUE"укажите порт для Telemt: "$NC)" P_PORT; P_PORT=${P_PORT:-443}
    read -p " $(echo -e $SKY_BLUE"укажите SNI для TLS: "$NC)" P_SNI; P_SNI=${P_SNI:-google.com}
    read -p " $(echo -e $SKY_BLUE"имя пользователя: "$NC)" P_USER; P_USER=${P_USER:-admin}
    
    run_step "установка зависимостей" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    run_step "загрузка бинарных файлов" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
    mkdir -p $CONF_DIR
    cat <<EOF > $CONF_FILE
[general]
use_middle_proxy = false
[general.modes]
tls = true
[server]
port = $P_PORT
[server.api]
enabled = true
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$P_SNI"
[access.users]
$P_USER = "$(openssl rand -hex 16)"
EOF
    
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Telemt Proxy
After=network-online.target
[Service]
Type=simple
ExecStart=$BIN_PATH $CONF_FILE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    run_step "запуск Telemt" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    show_links "$P_USER"
}

install_zapret() {
    echo -e "\n${BOLD}${MAIN_COLOR} сборка и установка Zapret${NC}"
    run_step "установка зависимостей" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
    run_step "очистка старой папки" "rm -rf $ZAPRET_DIR"
    run_step "клонирование репозитория" "git clone --depth=1 https://github.com/bol-van/zapret.git $ZAPRET_DIR"
    run_step "сборка (make)" "make -C $ZAPRET_DIR"
    
    cat <<EOF > $ZAPRET_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=$ZAPRET_DIR/tpws/tpws --bind-addr=127.0.0.1 --port=1080 --socks --split-http-req=host --split-pos=2 --hostcase --hostspell=hoSt --split-tls=sni --disorder --tlsrec=sni
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    run_step "запуск службы" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
}

# --- menus ---

submenu_service() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ СЕРВИСОМ TELEMT"
        print_status_block; echo ""
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}перезапустить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p " $(echo -e $ORANGE"выберите действие: "$NC)" sc
        case $sc in
            1) install_telemt; wait_user ;;
            2) run_step "перезапуск" "systemctl restart telemt"; wait_user ;;
            3) run_step "остановка" "systemctl stop telemt"; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ"
        print_status_block; echo ""
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}список пользователей и ссылки${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}добавить пользователя${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p " $(echo -e $ORANGE"выберите действие: "$NC)" sc
        case $sc in
            1) mapfile -t USERS < <(get_user_list)
               for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
               read -p " $(echo -e $SKY_BLUE"номер пользователя (0-назад): "$NC)" uidx
               if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                   show_links "${USERS[$((uidx-1))]}" && wait_user
               elif [ "$uidx" == "0" ]; then continue; fi ;;
            2) read -p " $(echo -e $SKY_BLUE"имя нового пользователя: "$NC)" uname
               if [[ -n "$uname" ]]; then
                   echo "$uname = \"$(openssl rand -hex 16)\"" >> $CONF_FILE && run_step "обновление конфига" "systemctl restart telemt"
               fi; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear; draw_header "НАСТРОЙКИ TELEMT"
        print_status_block; echo ""
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}системный лог (journalctl)${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}изменить порт${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}изменить SNI домен${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p " $(echo -e $ORANGE"выберите действие: "$NC)" sc
        case $sc in
            1) journalctl -u telemt -n 50 --no-pager; wait_user ;;
            2) read -p " $(echo -e $SKY_BLUE"новый порт: "$NC)" N_PORT
               if [[ $N_PORT =~ ^[0-9]+$ ]]; then sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && run_step "применение" "systemctl restart telemt"; fi; wait_user ;;
            3) read -p " $(echo -e $SKY_BLUE"новый SNI: "$NC)" N_SNI
               if [ -n "$N_SNI" ]; then sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && run_step "применение" "systemctl restart telemt"; fi; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_zapret() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ ZAPRET (TPWS)"
        print_status_block; echo ""
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить/обновить Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}запустить службу Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить службу Zapret${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}удалить Zapret из системы${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p " $(echo -e $ORANGE"выберите действие: "$NC)" sc
        case $sc in
            1) install_zapret; wait_user ;;
            2) run_step "запуск" "systemctl start zapret-tpws"; wait_user ;;
            3) run_step "остановка" "systemctl stop zapret-tpws"; wait_user ;;
            4) read -p " $(echo -e $RED"полностью удалить Zapret? (y/n): "$NC)" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && cleanup_zapret && wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        clear; draw_header "ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА"
        print_status_block; echo ""
        printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}удалить Telemt${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}полная очистка (Telemt + Zapret)${NC}\n"
        printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p " $(echo -e $ORANGE"выберите действие: "$NC)" sc
        case $sc in
            1) read -p " $(echo -e $RED"удалить Telemt и его данные? (y/n): "$NC)" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && cleanup_proxy && wait_user ;;
            2) read -p " $(echo -e $RED"полная очистка (все сервисы и менеджер)? (y/n): "$NC)" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && cleanup_proxy && cleanup_zapret && rm -f "$CLI_NAME" && echo -e " ${RED}Система очищена. Выход...${NC}" && exit 0 ;;
            0) break ;;
        esac
    done
}

# --- main cycle ---
while true; do
    clear; draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    print_status_block; echo ""

    printf " ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}$L_MAIN_5${NC}\n"
    printf " ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    
    read -p " $(echo -e $ORANGE"выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) exit 0 ;;
    esac
done
