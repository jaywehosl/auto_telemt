#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.4.5 (TUI Logic & Buffer Fix)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Окружение и Цвета
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.4.5"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Отступ

BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m' # Салатовый
ORANGE='\033[1;38;5;214m'  # Оранжевый
SKY_BLUE='\033[1;38;5;81m' # Голубой
GREEN='\033[1;32m'         # Зеленый
RED='\033[1;31m'           # Красный
YELLOW='\033[1;33m'        # Желтый

# Тексты
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_T="статус Telemt:"
L_STATUS_Z="статус Zapret:"
L_MAIN_1="управление сервисом Telemt"
L_MAIN_2="управление пользователями Telemt"
L_MAIN_3="настройки Telemt"
L_MAIN_4="управление Zapret (TPWS)"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

HB_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
HB_IDX=0

BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Инициализация терминала
tput civis
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Движок интерфейса (TUI)
# ------------------------------------------------------------------------------

# Очистка экрана вниз от курсора (убирает артефакты старых меню)
clear_buffer() {
    printf "\033[J"
}

# Возврат курсора в начало
reset_ui() {
    printf "\033[H"
}

draw_header() {
    local title="$1"
    local width=44
    local text_len=${#title}
    local padding=$(( (width - text_len) / 2 ))
    local extra=$(( (width - text_len) % 2 ))
    
    HB_IDX=$(( (HB_IDX + 1) % ${#HB_FRAMES[@]} ))
    local pulse="${SKY_BLUE}${HB_FRAMES[$HB_IDX]}${NC}"

    printf "${BOLD}${MAIN_COLOR}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║${NC}%*s%s%*s${BOLD}${MAIN_COLOR}${pulse}║${NC}\n" "$padding" "" "$title" "$((padding + extra - 1))" ""
    printf "${BOLD}${MAIN_COLOR}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

msg_status() {
    local s1 s2
    if [ ! -f "$SERVICE_FILE" ]; then s1="${RED}не установлен${NC}"
    elif systemctl is-active --quiet telemt; then s1="${GREEN}работает${NC}"
    else s1="${YELLOW}остановлен${NC}"; fi

    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="${RED}не установлен${NC}"
    elif systemctl is-active --quiet zapret-tpws; then s2="${GREEN}работает${NC}"
    else s2="${YELLOW}остановлен${NC}"; fi

    printf "${L_IND}%-16s %b\n" "$L_STATUS_T" "$s1"
    printf "${L_IND}%-16s %b\n" "$L_STATUS_Z" "$s2"
}

# Защищенный промпт (не дает стирать префикс)
msg_prompt() {
    local prompt_text="${L_IND}${BOLD}${ORANGE}>> $1: ${NC}"
    tput cnorm
    read -p "$(echo -e "$prompt_text")" "$2"
    tput civis
}

msg_step() {
    local msg="$1"
    local cmd="$2"
    printf "${L_IND}${BOLD}${SKY_BLUE}*${NC} %-35s " "$msg..."
    if eval "$cmd" > /dev/null 2>&1; then
        printf "${GREEN}[готово]${NC}\n"
    else
        printf "${RED}[ошибка]${NC}\n"
        return 1
    fi
}

msg_error() { echo -e "${L_IND}${RED}${BOLD}!! ОШИБКА: ${NC}${BOLD}$1${NC}"; }
msg_ok()    { echo -e "${L_IND}${GREEN}${BOLD}ok УСПЕХ: ${NC}${BOLD}$1${NC}"; }

# ------------------------------------------------------------------------------
# 3. Логика процессов
# ------------------------------------------------------------------------------

check_updates() {
    local remote
    remote=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    if [[ -n "$remote" && "$remote" != "$CURRENT_VERSION" ]]; then
        UPDATE_MARKER="${SKY_BLUE} (*)${NC}"
        REMOTE_VERSION="$remote"
        HAS_UPDATE=true
    else
        UPDATE_MARKER=""
        HAS_UPDATE=false
    fi
}

wait_user() {
    printf "\n${L_IND}${SKY_BLUE}${BOLD}нажмите [Enter] для продолжения...${NC}"
    tput cnorm; read -r; tput civis
}

get_user_list() {
    [ -f "$CONF_FILE" ] && sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${L_IND}${BOLD}${SKY_BLUE}Ключи доступа для ${NC}${BOLD}${MAIN_COLOR}$target_user${NC}${BOLD}${SKY_BLUE}:${NC}"
    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        msg_error "Данные не получены."
    else
        for link in $LINKS; do echo -e "${L_IND}  ${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"; done
    fi
}

# ------------------------------------------------------------------------------
# 4. Меню (Submenus)
# ------------------------------------------------------------------------------

submenu_service() {
    local sc
    clear
    while true; do
        reset_ui; draw_header "УПРАВЛЕНИЕ TELEMT"
        msg_status; echo ""
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}установить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 2 -${NC} ${BOLD}перезапустить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 3 -${NC} ${BOLD}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}назад${NC}"
        echo ""; clear_buffer
        read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> действие: ${NC}")" sc
        [ $? -gt 128 ] && continue # Пульс
        case $sc in
            1)  echo ""; msg_prompt "порт (443)" P_PORT; P_PORT=${P_PORT:-443}
                msg_prompt "SNI (google.com)" P_SNI; P_SNI=${P_SNI:-google.com}
                msg_prompt "админ" P_USER; P_USER=${P_USER:-admin}
                echo ""; msg_step "Пакеты" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
                local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
                msg_step "Загрузка" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
                mkdir -p $CONF_DIR; cat <<EOF > $CONF_FILE
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
                msg_step "Запуск" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                show_links "$P_USER"; wait_user; clear ;;
            2) echo ""; msg_step "Перезапуск" "systemctl restart telemt"; wait_user; clear ;;
            3) echo ""; msg_step "Остановка" "systemctl stop telemt"; wait_user; clear ;;
            0) clear; break ;;
        esac
    done
}

submenu_users() {
    local sc
    clear
    while true; do
        reset_ui; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"
        msg_status; echo ""
        if [ ! -f "$CONF_FILE" ]; then msg_error "Telemt не установлен."; wait_user; clear; break; fi
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}список и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 2 -${NC} ${BOLD}добавить пользователя${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}назад${NC}"
        echo ""; clear_buffer
        read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> действие: ${NC}")" sc
        [ $? -gt 128 ] && continue
        case $sc in
            1) mapfile -t USERS < <(get_user_list)
               echo ""
               for i in "${!USERS[@]}"; do printf "${L_IND}  ${BOLD}${SKY_BLUE}%d.${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
               msg_prompt "номер [0-назад]" uidx
               if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                   show_links "${USERS[$((uidx-1))]}" && wait_user
               fi; clear ;;
            2) echo ""; msg_prompt "имя" uname
               if [[ -n "$uname" ]]; then
                   echo "$uname = \"$(openssl rand -hex 16)\"" >> $CONF_FILE
                   msg_step "Обновление" "systemctl restart telemt"
               fi; wait_user; clear ;;
            0) clear; break ;;
        esac
    done
}

submenu_settings() {
    local sc
    clear
    while true; do
        reset_ui; draw_header "НАСТРОЙКИ TELEMT"
        msg_status; echo ""
        if [ ! -f "$CONF_FILE" ]; then msg_error "Telemt не установлен."; wait_user; clear; break; fi
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}логи системы${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 2 -${NC} ${BOLD}сменить порт${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 3 -${NC} ${BOLD}сменить SNI домен${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}назад${NC}"
        echo ""; clear_buffer
        read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> действие: ${NC}")" sc
        [ $? -gt 128 ] && continue
        case $sc in
            1) echo ""; journalctl -u telemt -n 50 --no-pager; wait_user; clear ;;
            2) echo ""; msg_prompt "новый порт" np
               if [[ $np =~ ^[0-9]+$ ]]; then sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt; msg_ok "Порт изменен"; fi; wait_user; clear ;;
            3) echo ""; msg_prompt "новый SNI" ns
               if [ -n "$ns" ]; then sed -i "s/^tls_domain = .*/tls_domain = \"$ns\"/" $CONF_FILE && systemctl restart telemt; msg_ok "SNI изменен"; fi; wait_user; clear ;;
            0) clear; break ;;
        esac
    done
}

submenu_zapret() {
    local sc
    clear
    while true; do
        reset_ui; draw_header "УПРАВЛЕНИЕ ZAPRET"
        msg_status; echo ""
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}установить / обновить${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 2 -${NC} ${BOLD}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 3 -${NC} ${BOLD}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${RED} 4 -${NC} ${BOLD}удалить из системы${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}назад${NC}"
        echo ""; clear_buffer
        read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> действие: ${NC}")" sc
        [ $? -gt 128 ] && continue
        case $sc in
            1)  echo ""; msg_step "Зависимости" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                msg_step "Загрузка" "rm -rf $ZAPRET_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $ZAPRET_DIR"
                msg_step "Сборка" "make -C $ZAPRET_DIR"
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
                msg_step "Активация" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
                wait_user; clear ;;
            2) echo ""; msg_step "Запуск" "systemctl start zapret-tpws"; wait_user; clear ;;
            3) echo ""; msg_step "Остановка" "systemctl stop zapret-tpws"; wait_user; clear ;;
            4) echo ""; msg_prompt "удалить Zapret? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && echo "" && msg_step "Удаление" "systemctl stop zapret-tpws; rm -rf $ZAPRET_DIR $ZAPRET_SERVICE; systemctl daemon-reload" && wait_user; clear ;;
            0) clear; break ;;
        esac
    done
}

submenu_manager() {
    local sc
    clear
    while true; do
        reset_ui; draw_header "ОБСЛУЖИВАНИЕ"
        msg_status; echo ""
        if [ "$HAS_UPDATE" = true ]; then
            echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}обновить до ${GREEN}$REMOTE_VERSION${NC}"
        else
            echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}переустановить менеджер${NC}"
        fi
        echo -e "${L_IND}${BOLD}${RED} 2 -${NC} ${BOLD}удалить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${RED} 3 -${NC} ${BOLD}полная очистка системы${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}назад${NC}"
        echo ""; clear_buffer
        read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> действие: ${NC}")" sc
        [ $? -gt 128 ] && continue
        case $sc in
            1) echo ""; msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"
               msg_ok "Готово. Перезапуск..."; sleep 1; exec "$CLI_NAME" ;;
            2) echo ""; msg_prompt "удалить Telemt? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && echo "" && msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH" && wait_user; clear ;;
            3) echo ""; msg_prompt "ПОЛНАЯ ОЧИСТКА? [y/n]" confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   echo ""; systemctl stop telemt zapret-tpws 2>/dev/null
                   rm -rf $CONF_DIR $ZAPRET_DIR $ZAPRET_SERVICE $SERVICE_FILE $BIN_PATH
                   systemctl daemon-reload; rm -f "$CLI_NAME"
                   echo -e "${L_IND}${RED}${BOLD}Система очищена.${NC}"; exit 0
               fi ;;
            0) clear; break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. Главный цикл
# ------------------------------------------------------------------------------
clear
while true; do
    check_updates
    reset_ui; draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    msg_status; echo ""
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ${BOLD}${L_MAIN_1}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 2 -${NC} ${BOLD}${L_MAIN_2}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 3 -${NC} ${BOLD}${L_MAIN_3}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 4 -${NC} ${BOLD}${L_MAIN_4}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 5 -${NC} ${BOLD}${L_MAIN_5}${NC}${UPDATE_MARKER}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} ${BOLD}${L_MAIN_0}${NC}"
    echo ""; clear_buffer
    read -t 2 -p "$(echo -e "${L_IND}${BOLD}${ORANGE}>> выберите раздел: ${NC}")" mainchoice
    [ $? -gt 128 ] && continue # Перерисовка по таймауту для пульса

    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
