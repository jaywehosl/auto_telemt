#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.4.8 (SSD Engine - Stalin Stability Drive)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Параметры и Цветовая схема
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.4.8"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Стандартный отступ (2 пробела)

BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m' # Салатовый (Рамки)
ORANGE='\033[1;38;5;214m'  # Оранжевый (Промпты >>)
SKY_BLUE='\033[1;38;5;81m' # Голубой (Индексы [ 1 ])
GREEN='\033[1;32m'         # Зеленый (Работает)
RED='\033[1;31m'           # Красный (Нет/Ошибка)
YELLOW='\033[1;33m'        # Желтый (Стоп)

L_MENU_HEADER="СТАЛИН-3000"
L_MAIN_1="управление сервисом Telemt"
L_MAIN_2="управление пользователями Telemt"
L_MAIN_3="настройки Telemt"
L_MAIN_4="управление Zapret (TPWS)"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

# Кадры пульса (Spinner)
HB_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
HB_IDX=0

# Пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Инициализация (Скрытие курсора, уборка при выходе)
tput civis
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. UI Движок (SSD Engine)
# ------------------------------------------------------------------------------

draw_header() {
    local title="$1"
    local width=44
    local padding=$(( (width - ${#title}) / 2 ))
    local extra=$(( (width - ${#title}) % 2 ))
    printf "${BOLD}${MAIN_COLOR}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║${NC}%*s%s%*s${BOLD}${MAIN_COLOR}║${NC}\n" "$padding" "" "$title" "$((padding + extra))" ""
    printf "${BOLD}${MAIN_COLOR}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Функция отрисовки статуса с пульсом
# Вызывается внутри цикла ввода, прыгает курсором на строки 5 и 6
render_status_block() {
    printf "\033[s"      # Сохранить позицию курсора (там где ввод пользователя)
    printf "\033[H\033[4B" # Прыгнуть в начало, затем на 4 строки вниз

    HB_IDX=$(( (HB_IDX + 1) % ${#HB_FRAMES[@]} ))
    local spinner="${HB_FRAMES[$HB_IDX]}"

    # Статус Telemt
    local s1 color1
    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; color1="$RED"
    elif systemctl is-active --quiet telemt; then s1="работает"; color1="$GREEN"
    else s1="остановлен"; color1="$YELLOW"; fi
    printf "${L_IND}%-16s %b%s %b%s${NC}\033[K\n" "статус Telemt:" "$color1" "$s1" "$color1" "$spinner"

    # Статус Zapret
    local s2 color2
    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="не установлен"; color2="$RED"
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; color2="$GREEN"
    else s2="остановлен"; color2="$YELLOW"; fi
    printf "${L_IND}%-16s %b%s %b%s${NC}\033[K\n" "статус Zapret:" "$color2" "$s2" "$color2" "$spinner"

    printf "\033[u" # Вернуть курсор на место ввода
}

# Глобальный обработчик ввода (Stalin Stability Drive)
# $1 - текст промпта, $2 - имя переменной
get_input() {
    local prompt_text="${L_IND}${BOLD}${ORANGE}>> $1: ${NC}"
    local current_input=""
    local char
    
    printf "%s" "$prompt_text"
    tput cnorm
    while true; do
        render_status_block
        # Читаем 1 символ с коротким таймаутом (0.1 сек) для плавной анимации
        if IFS= read -r -s -n 1 -t 0.1 char; then
            # Нажат Enter (пустая строка или null)
            if [[ -z "$char" ]]; then
                echo "" # Переход на новую строку
                break
            fi
            # Нажат Backspace (код 127 или 8)
            if [[ "$char" == $'\177' || "$char" == $'\010' ]]; then
                if [ ${#current_input} -gt 0 ]; then
                    current_input="${current_input%?}"
                    printf "\b \b" # Визуально стираем символ
                fi
            else
                current_input+="$char"
                printf "%s" "$char" # Выводим вводимый символ
            fi
        fi
    done
    eval "$2=\"$current_input\""
    tput civis
}

msg_step() {
    echo ""
    printf "${L_IND}${BOLD}${SKY_BLUE}*${NC} %-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then printf "${GREEN}[готово]${NC}\n"; else printf "${RED}[ошибка]${NC}\n"; return 1; fi
}

msg_error() { echo -e "\n${L_IND}${RED}${BOLD}!! ОШИБКА: ${NC}${BOLD}$1${NC}"; }

# ------------------------------------------------------------------------------
# 3. Логика Подменю
# ------------------------------------------------------------------------------

submenu_service() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ TELEMT"
        echo -e "\n\n" # Место под живые статусы
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}установить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 2 ]${NC} ${BOLD}перезапустить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 3 ]${NC} ${BOLD}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}назад${NC}"
        echo ""
        get_input "действие" sc
        case $sc in
            1)  echo ""; get_input "порт (443)" P_PORT; P_PORT=${P_PORT:-443}
                get_input "SNI (google.com)" P_SNI; P_SNI=${P_SNI:-google.com}
                get_input "имя админа" P_USER; P_USER=${P_USER:-admin}
                msg_step "Зависимости" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
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
                printf "\n${L_IND}${SKY_BLUE}нажмите [Enter]...${NC}"; read; continue ;;
            2) msg_step "Перезапуск" "systemctl restart telemt"; sleep 1; continue ;;
            3) msg_step "Остановка" "systemctl stop telemt"; sleep 1; continue ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"
        if [ ! -f "$CONF_FILE" ]; then echo -e "\n\n"; msg_error "Telemt не установлен."; sleep 2; return; fi
        echo -e "\n\n"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}список и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 2 ]${NC} ${BOLD}добавить пользователя${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}назад${NC}"
        echo ""
        get_input "действие" sc
        case $sc in
            1)  echo ""; mapfile -t USERS < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!USERS[@]}"; do printf "${L_IND}  ${BOLD}${SKY_BLUE}%d.${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf "\n${L_IND}${ORANGE}номер пользователя [0-назад]: ${NC}"; tput cnorm; read uidx; tput civis
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                    local target="${USERS[$((uidx-1))]}"
                    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    echo -e "\n${L_IND}${BOLD}${SKY_BLUE}Ключи для $target:${NC}"
                    for l in $LINKS; do echo -e "${L_IND}  ${BOLD}${MAIN_COLOR}${l//0.0.0.0/$IP4}${NC}"; done
                    printf "\n${L_IND}${SKY_BLUE}нажмите [Enter]...${NC}"; read
                fi; continue ;;
            2)  echo ""; get_input "имя нового пользователя" uname
                if [[ -n "$uname" ]]; then
                    echo "$uname = \"$(openssl rand -hex 16)\"" >> $CONF_FILE
                    msg_step "Обновление" "systemctl restart telemt"; sleep 1
                fi; continue ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear; draw_header "НАСТРОЙКИ TELEMT"
        if [ ! -f "$CONF_FILE" ]; then echo -e "\n\n"; msg_error "Telemt не установлен."; sleep 2; return; fi
        echo -e "\n\n"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}логи системы (journalctl)${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 2 ]${NC} ${BOLD}сменить порт${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 3 ]${NC} ${BOLD}сменить SNI домен${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}назад${NC}"
        echo ""
        get_input "действие" sc
        case $sc in
            1) echo ""; tput cnorm; journalctl -u telemt -n 50 --no-pager; tput civis
               printf "\n${L_IND}${SKY_BLUE}нажмите [Enter]...${NC}"; read; continue ;;
            2) echo ""; get_input "новый порт" np
               if [[ $np =~ ^[0-9]+$ ]]; then sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt; fi; continue ;;
            3) echo ""; get_input "новый SNI" ns
               if [ -n "$ns" ]; then sed -i "s/^tls_domain = .*/tls_domain = \"$ns\"/" $CONF_FILE && systemctl restart telemt; fi; continue ;;
            0) break ;;
        esac
    done
}

submenu_zapret() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ ZAPRET"
        echo -e "\n\n"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}установить / обновить${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 2 ]${NC} ${BOLD}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 3 ]${NC} ${BOLD}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${RED}[ 4 ]${NC} ${BOLD}удалить из системы${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}назад${NC}"
        echo ""
        get_input "действие" sc
        case $sc in
            1)  msg_step "Зависимости" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
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
                sleep 2; continue ;;
            2) msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1; continue ;;
            3) msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1; continue ;;
            4) echo ""; get_input "удалить Zapret? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && msg_step "Удаление" "systemctl stop zapret-tpws; rm -rf $ZAPRET_DIR $ZAPRET_SERVICE; systemctl daemon-reload"; sleep 1
               continue ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        clear; draw_header "ОБСЛУЖИВАНИЕ"
        echo -e "\n\n"
        local remote=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        if [[ -n "$remote" && "$remote" != "$CURRENT_VERSION" ]]; then
            echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}ОБНОВИТЬ ДО ${GREEN}$remote${NC}"
        else
            echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}переустановить менеджер${NC}"
        fi
        echo -e "${L_IND}${BOLD}${RED}[ 2 ]${NC} ${BOLD}удалить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${RED}[ 3 ]${NC} ${BOLD}полная очистка системы${NC}"
        echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}назад${NC}"
        echo ""
        get_input "действие" sc
        case $sc in
            1) msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"
               tput cnorm; exec "$CLI_NAME" ;;
            2) echo ""; get_input "удалить Telemt? [y/n]" confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH"; sleep 1; continue ;;
            3) echo ""; get_input "ПОЛНАЯ ОЧИСТКА? [y/n]" confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   systemctl stop telemt zapret-tpws 2>/dev/null
                   rm -rf $CONF_DIR $ZAPRET_DIR $ZAPRET_SERVICE $SERVICE_FILE $BIN_PATH
                   systemctl daemon-reload; rm -f "$CLI_NAME"; clear; tput cnorm; exit 0
               fi; continue ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 4. Главный цикл
# ------------------------------------------------------------------------------

while true; do
    clear
    draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    echo -e "\n\n" # Резерв под статусы
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 1 ]${NC} ${BOLD}${L_MAIN_1}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 2 ]${NC} ${BOLD}${L_MAIN_2}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 3 ]${NC} ${BOLD}${L_MAIN_3}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 4 ]${NC} ${BOLD}${L_MAIN_4}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 5 ]${NC} ${BOLD}${L_MAIN_5}${NC}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE}[ 0 ]${NC} ${BOLD}${L_MAIN_0}${NC}"
    echo ""
    
    get_input "выберите раздел" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) clear; tput cnorm; exit 0 ;;
        *) continue ;;
    esac
done
