#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.5.1 (Fixed TUI Logic & Hierarchy)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Глобальное окружение и Стили (ГОСТ)
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.5.1"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Стандартный отступ

# Цвета (Всегда жирные)
NC='\033[0m'
BOLD='\033[1m'
C_MAIN='\033[1;38;5;148m' # Салатовый
C_ORANGE='\033[1;38;5;214m' # Оранжевый
C_SKY='\033[1;38;5;81m'   # Голубой
C_GREEN='\033[1;32m'        # Зеленый
C_RED='\033[1;31m'          # Красный
C_YELLOW='\033[1;33m'       # Желтый

# Анимация пульса
SPINNER=("|" "/" "-" "\\")
HB_IDX=0

# Тексты меню
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_T="статус Telemt:"
L_STATUS_Z="статус Zapret:"

M_MAIN_1="управление сервисом Telemt"
M_MAIN_2="управление пользователями Telemt"
M_MAIN_3="настройки Telemt"
M_MAIN_4="управление Zapret (TPWS)"
M_MAIN_5="обслуживание менеджера"
M_MAIN_0="выход"

# Пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Трап и скрытие курсора
tput civis
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}${BOLD}Ошибка: Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Движок интерфейса (UI Engine)
# ------------------------------------------------------------------------------

# Отрисовка шапки
draw_header() {
    local title="$1"
    local width=44
    local p=$(( (width - ${#title}) / 2 ))
    local e=$(( (width - ${#title}) % 2 ))
    printf "${C_MAIN}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${C_MAIN}║${NC}${BOLD}%*s%s%*s${C_MAIN}║${NC}\n" "$p" "" "$title" "$((p + e))" ""
    printf "${C_MAIN}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Блок статусов с пульсом
draw_status_block() {
    HB_IDX=$(( (HB_IDX + 1) % ${#SPINNER[@]} ))
    local sym="${SPINNER[$HB_IDX]}"
    local s1 c1 s2 c2

    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; c1="$C_RED"
    elif systemctl is-active --quiet telemt; then s1="работает"; c1="$C_GREEN"
    else s1="остановлен"; c1="$C_YELLOW"; fi

    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="не установлен"; c2="$C_RED"
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; c2="$C_GREEN"
    else s2="остановлен"; c2="$C_YELLOW"; fi

    printf "${L_IND}${BOLD}%-16s %b%s %s${NC}\033[K\n" "$L_STATUS_T" "$c1" "$s1" "$sym"
    printf "${L_IND}${BOLD}%-16s %b%s %s${NC}\033[K\n" "$L_STATUS_Z" "$c2" "$s2" "$sym"
}

# Отрисовка пункта меню (Оранжевый текст, Голубой индекс)
draw_item() {
    printf "${L_IND}${BOLD}${C_SKY}%s - ${C_ORANGE}%s${NC}\033[K\n" "$1" "$2"
}

# Умный ввод (SSD 2.1)
# $1 - промпт, $2 - имя переменной
smart_input() {
    local prompt_text="$1"
    local var_name="$2"
    local current=""
    local char
    
    # Раскраска y/n
    local p_display=$(echo -e "$prompt_text" | sed "s/y\//${C_GREEN}y${NC}\//g" | sed "s/\/n/\/${C_RED}n${NC}/g")
    
    printf "\n${L_IND}${BOLD}${C_ORANGE}>> %b: ${NC}" "$p_display"
    
    tput cnorm
    while true; do
        # Обновление статусов без мерцания через возврат курсора
        printf "\033[s" # Save
        printf "\033[H\033[2B" # Home, 2 down (начало блока статусов)
        draw_status_block
        printf "\033[u" # Restore

        if IFS= read -r -s -n 1 -t 0.1 char; then
            if [[ -z "$char" ]]; then echo ""; break; fi
            if [[ "$char" == $'\177' || "$char" == $'\010' ]]; then
                if [ ${#current} -gt 0 ]; then
                    current="${current%?}"
                    printf "\b \b"
                fi
            else
                current+="$char"; printf "%s" "$char"
            fi
        fi
    done
    tput civis
    eval "$var_name=\"$current\""
}

# Шаг выполнения (Звездочка голубая)
msg_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then 
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"
    else 
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

msg_ok() { echo -e "\n${L_IND}${BOLD}${C_GREEN}ok УСПЕХ: $1${NC}"; }
msg_err() { echo -e "\n${L_IND}${BOLD}${C_RED}!! ОШИБКА: $1${NC}"; }

# ------------------------------------------------------------------------------
# 3. Действия
# ------------------------------------------------------------------------------

check_updates() {
    local remote
    remote=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    if [[ -n "$remote" && "$remote" != "$CURRENT_VERSION" ]]; then
        UPDATE_MARKER="${C_SKY} (*)${NC}"
        REMOTE_VERSION="$remote"
        HAS_UPDATE=true
    else
        UPDATE_MARKER=""
        HAS_UPDATE=false
    fi
}

install_telemt() {
    echo ""
    smart_input "укажите порт (443)" P_PORT; P_PORT=${P_PORT:-443}
    smart_input "SNI домен (google.com)" P_SNI; P_SNI=${P_SNI:-google.com}
    smart_input "имя администратора" P_USER; P_USER=${P_USER:-admin}
    
    echo ""
    msg_step "Обновление пакетов" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    msg_step "Загрузка Telemt" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
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
    msg_step "Запуск сервиса" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    
    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$P_USER\") | .links.tls[]" 2>/dev/null)
    echo -e "\n${L_IND}${BOLD}${C_SKY}Ключи доступа:${NC}"
    for l in $LINKS; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP4}${NC}"; done
    msg_ok "Telemt установлен."
}

# ------------------------------------------------------------------------------
# 4. Подменю
# ------------------------------------------------------------------------------

submenu_service() {
    clear
    while true; do
        printf "\033[H"
        draw_header "УПРАВЛЕНИЕ TELEMT"
        echo ""; draw_status_block; echo ""
        draw_item "1" "установить Telemt"
        draw_item "2" "перезапустить службу"
        draw_item "3" "остановить службу"
        draw_item "0" "назад"
        smart_input "выберите действие" sc
        case $sc in
            1) install_telemt; smart_input "нажмите [Enter]" wait; clear ;;
            2) echo ""; msg_step "Перезапуск" "systemctl restart telemt"; sleep 1 ;;
            3) echo ""; msg_step "Остановка" "systemctl stop telemt"; sleep 1 ;;
            0) clear; break ;;
        esac
    done
}

submenu_users() {
    clear
    while true; do
        printf "\033[H"
        draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"
        echo ""; draw_status_block; echo ""
        local exists=true
        if [ ! -f "$CONF_FILE" ]; then exists=false; fi

        if [ "$exists" = true ]; then
            draw_item "1" "список пользователей"
            draw_item "2" "добавить нового"
            draw_item "0" "назад"
        else
            draw_item "0" "назад"
            echo ""; msg_err "Telemt не установлен."
        fi

        smart_input "выберите действие" sc
        case $sc in
            1)  if [ "$exists" = true ]; then
                    echo ""; mapfile -t USERS < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                    for i in "${!USERS[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d. ${C_ORANGE}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                    smart_input "номер пользователя [0-назад]" uidx
                    if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                        local target="${USERS[$((uidx-1))]}"
                        local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                        local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                        echo -e "\n${L_IND}${BOLD}${C_SKY}Ключи для $target:${NC}"
                        for l in $LINKS; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP4}${NC}"; done
                        smart_input "нажмите [Enter]" wait
                    fi
                fi; clear ;;
            2)  if [ "$exists" = true ]; then
                    smart_input "имя пользователя" uname
                    if [[ -n "$uname" ]]; then
                        echo "$uname = \"$(openssl rand -hex 16)\"" >> $CONF_FILE
                        msg_step "Обновление" "systemctl restart telemt"; sleep 1
                    fi
                fi; clear ;;
            0) clear; break ;;
        esac
    done
}

submenu_settings() {
    clear
    while true; do
        printf "\033[H"
        draw_header "НАСТРОЙКИ TELEMT"
        echo ""; draw_status_block; echo ""
        if [ ! -f "$CONF_FILE" ]; then
            draw_item "0" "назад"; echo ""; msg_err "Telemt не установлен."; smart_input "действие" sc; [ "$sc" == "0" ] && { clear; break; } || continue
        fi
        draw_item "1" "просмотр логов"
        draw_item "2" "изменить порт"
        draw_item "3" "изменить SNI"
        draw_item "0" "назад"
        smart_input "выберите действие" sc
        case $sc in
            1) echo ""; journalctl -u telemt -n 50 --no-pager; smart_input "нажмите [Enter]" wait; clear ;;
            2) smart_input "новый порт" np
               if [[ $np =~ ^[0-9]+$ ]]; then sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt; msg_ok "Порт изменен"; sleep 1; fi ;;
            3) smart_input "новый SNI" ns
               if [ -n "$ns" ]; then sed -i "s/^tls_domain = .*/tls_domain = \"$ns\"/" $CONF_FILE && systemctl restart telemt; msg_ok "SNI изменен"; sleep 1; fi ;;
            0) clear; break ;;
        esac
    done
}

submenu_zapret() {
    clear
    while true; do
        printf "\033[H"
        draw_header "УПРАВЛЕНИЕ ZAPRET"
        echo ""; draw_status_block; echo ""
        draw_item "1" "установить / обновить"
        draw_item "2" "запустить службу"
        draw_item "3" "остановить службу"
        draw_item "4" "удалить из системы"
        draw_item "0" "назад"
        smart_input "выберите действие" sc
        case $sc in
            1)  echo ""; msg_step "Зависимости" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                msg_step "Загрузка Zapret" "rm -rf $ZAPRET_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $ZAPRET_DIR"
                msg_step "Компиляция" "make -C $ZAPRET_DIR"
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
                smart_input "нажмите [Enter]" wait; clear ;;
            2) echo ""; msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1 ;;
            3) echo ""; msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) smart_input "удалить Zapret? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && echo "" && msg_step "Удаление" "systemctl stop zapret-tpws; rm -rf $ZAPRET_DIR $ZAPRET_SERVICE; systemctl daemon-reload" && sleep 1
               clear; break ;;
            0) clear; break ;;
        esac
    done
}

submenu_manager() {
    clear
    while true; do
        printf "\033[H"
        draw_header "ОБСЛУЖИВАНИЕ"
        echo ""; draw_status_block; echo ""
        if [ "$HAS_UPDATE" = true ]; then draw_item "1" "обновить до $REMOTE_VERSION"; else draw_item "1" "переустановить менеджер"; fi
        draw_item "2" "удалить Telemt"
        draw_item "3" "полная очистка системы"
        draw_item "0" "назад"
        smart_input "выберите действие" sc
        case $sc in
            1) echo ""; msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"
               tput cnorm; exec "$CLI_NAME" ;;
            2) smart_input "удалить Telemt? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && echo "" && msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH" && sleep 1; clear ;;
            3) smart_input "ПОЛНАЯ ОЧИСТКА? [y/n]" confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   echo ""; systemctl stop telemt zapret-tpws 2>/dev/null
                   rm -rf $CONF_DIR $ZAPRET_DIR $ZAPRET_SERVICE $SERVICE_FILE $BIN_PATH
                   systemctl daemon-reload; rm -f "$CLI_NAME"; clear; tput cnorm; exit 0
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
    printf "\033[H"
    draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    echo ""; draw_status_block; echo ""
    
    draw_item "1" "$M_MAIN_1"
    draw_item "2" "$M_MAIN_2"
    draw_item "3" "$M_MAIN_3"
    draw_item "4" "$M_MAIN_4"
    draw_item "5" "${M_MAIN_5}${UPDATE_MARKER}"
    draw_item "0" "$M_MAIN_0"
    
    smart_input "выберите раздел" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
