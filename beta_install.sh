#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.4.9 (Color Standards & Intuitive Input)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Окружение и Цветовая Палитра
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.4.9"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Глобальный отступ интерфейса

BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m' # Салатовый (Рамки, Скобки)
ORANGE='\033[1;38;5;214m'  # Оранжевый (Пункты меню, Промпты)
SKY_BLUE='\033[1;38;5;81m' # Голубой (Индексы цифр)
WHITE='\033[1;37m'         # Чистый белый (Жирный текст инфо)
GREEN='\033[1;32m'         # Зеленый (Работает / Да)
RED='\033[1;31m'           # Красный (Нет / Ошибка)
YELLOW='\033[1;33m'        # Желтый (Внимание)

L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_T="статус Telemt:"
L_STATUS_Z="статус Zapret:"

HB_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
HB_IDX=0

# Системные пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Трап для чистого выхода (восстанавливает курсор)
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Движок интерфейса (SSD Engine)
# ------------------------------------------------------------------------------

# Универсальный заголовок
draw_header() {
    local title="$1"
    local width=44
    local p=$(( (width - ${#title}) / 2 ))
    local e=$(( (width - ${#title}) % 2 ))
    printf "${BOLD}${MAIN_COLOR}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║${NC}%*s%s%*s${BOLD}${MAIN_COLOR}║${NC}\n" "$p" "" "$title" "$((p + e))" ""
    printf "${BOLD}${MAIN_COLOR}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Отрисовка статусов с цветным пульсом (прыгает курсором)
render_pulse_status() {
    printf "\033[s"        # Сохранить курсор
    printf "\033[H\033[4B" # Домой, потом 4 строки вниз

    HB_IDX=$(( (HB_IDX + 1) % ${#HB_FRAMES[@]} ))
    local sp="${HB_FRAMES[$HB_IDX]}"

    local s1 c1
    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; c1="$RED"
    elif systemctl is-active --quiet telemt; then s1="работает"; c1="$GREEN"
    else s1="остановлен"; c1="$YELLOW"; fi
    printf "${L_IND}%-16s %b%s %b%s${NC}\033[K\n" "$L_STATUS_T" "$c1" "$s1" "$c1" "$sp"

    local s2 c2
    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="не установлен"; c2="$RED"
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; c2="$GREEN"
    else s2="остановлен"; c2="$YELLOW"; fi
    printf "${L_IND}%-16s %b%s %b%s${NC}\033[K\n" "$L_STATUS_Z" "$c2" "$s2" "$c2" "$sp"

    printf "\033[u" # Вернуть курсор
}

# Stalin Stability Drive (SSD) - Посимвольное чтение ввода с пульсом
get_input() {
    local prompt_text="$1"
    local var_name="$2"
    local current=""
    local char
    
    # Раскраска y/n если они есть в тексте промпта
    local colored_prompt=$(echo -e "$prompt_text" | sed "s/y\//${GREEN}y${NC}\//g" | sed "s/\/n/${NC}\/${RED}n${NC}/g")
    
    printf "${L_IND}${BOLD}${ORANGE}>> %b: ${NC}" "$colored_prompt"
    tput cnorm
    while true; do
        render_pulse_status
        if IFS= read -r -s -n 1 -t 0.1 char; then
            if [[ -z "$char" ]]; then # Enter
                echo ""
                break
            fi
            if [[ "$char" == $'\177' || "$char" == $'\010' ]]; then # Backspace
                if [ ${#current} -gt 0 ]; then
                    current="${current%?}"
                    printf "\b \b"
                fi
            else
                current+="$char"
                printf "%s" "$char"
            fi
        fi
    done
    eval "$var_name=\"$current\""
    tput civis
}

msg_step() {
    echo ""
    printf "${L_IND}${BOLD}${SKY_BLUE}*${NC} %-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then printf "${GREEN}[готово]${NC}\n"; else printf "${RED}[ошибка]${NC}\n"; return 1; fi
}

# ------------------------------------------------------------------------------
# 3. Вспомогательная логика
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

# ------------------------------------------------------------------------------
# 4. Подменю
# ------------------------------------------------------------------------------

# Шаблон отрисовки пунктов (для экономии кода)
# $1 - номер, $2 - текст
print_item() {
    printf "${L_IND}${BOLD}${MAIN_COLOR}[ ${SKY_BLUE}%s ${MAIN_COLOR}]${NC} ${BOLD}${ORANGE}%s${NC}\n" "$1" "$2"
}

submenu_service() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ TELEMT"
        echo -e "\n\n" # Статусы
        print_item "1" "установить Telemt"
        print_item "2" "перезапустить службу"
        print_item "3" "остановить службу"
        print_item "0" "назад"
        echo ""
        get_input "действие" sc
        case $sc in
            1)  echo ""; get_input "порт (443)" P_PORT; P_PORT=${P_PORT:-443}
                get_input "SNI (google.com)" P_SNI; P_SNI=${P_SNI:-google.com}
                get_input "имя админа" P_USER; P_USER=${P_USER:-admin}
                msg_step "Пакеты" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
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
                wait_user; continue ;;
            2) msg_step "Перезапуск" "systemctl restart telemt"; sleep 1; continue ;;
            3) msg_step "Остановка" "systemctl stop telemt"; sleep 1; continue ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"
        if [ ! -f "$CONF_FILE" ]; then echo -e "\n\n"; echo -e "${L_IND}${RED}!! Telemt не установлен.${NC}"; sleep 2; return; fi
        echo -e "\n\n"
        print_item "1" "список и ссылки"
        print_item "2" "добавить пользователя"
        print_item "0" "назад"
        echo ""
        get_input "действие" sc
        case $sc in
            1)  echo ""; mapfile -t USERS < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!USERS[@]}"; do printf "${L_IND}  ${BOLD}${SKY_BLUE}%d.${NC} ${WHITE}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                echo ""; get_input "номер пользователя [0-назад]" uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                    local target="${USERS[$((uidx-1))]}"
                    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    echo -e "\n${L_IND}${WHITE}Ключи доступа для $target:${NC}"
                    for l in $LINKS; do echo -e "${L_IND}  ${MAIN_COLOR}${l//0.0.0.0/$IP4}${NC}"; done
                    wait_user
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
        if [ ! -f "$CONF_FILE" ]; then echo -e "\n\n"; echo -e "${L_IND}${RED}!! Telemt не установлен.${NC}"; sleep 2; return; fi
        echo -e "\n\n"
        print_item "1" "логи системы (journalctl)"
        print_item "2" "сменить порт"
        print_item "3" "сменить SNI домен"
        print_item "0" "назад"
        echo ""
        get_input "действие" sc
        case $sc in
            1) echo ""; tput cnorm; journalctl -u telemt -n 50 --no-pager; tput civis; wait_user; continue ;;
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
        print_item "1" "установить / обновить"
        print_item "2" "запустить службу"
        print_item "3" "остановить службу"
        print_item "4" "удалить из системы"
        print_item "0" "назад"
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
                wait_user; continue ;;
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
        if [ "$HAS_UPDATE" = true ]; then
            print_item "1" "ОБНОВИТЬ ДО $REMOTE_VERSION"
        else
            print_item "1" "переустановить менеджер"
        fi
        print_item "2" "удалить Telemt"
        print_item "3" "полная очистка системы"
        print_item "0" "назад"
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
# 5. Главный Цикл
# ------------------------------------------------------------------------------

while true; do
    check_updates
    clear
    draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    echo -e "\n\n" # Резерв под статусы
    print_item "1" "$L_MAIN_1"
    print_item "2" "$L_MAIN_2"
    print_item "3" "$L_MAIN_3"
    print_item "4" "$L_MAIN_4"
    print_item "5" "${L_MAIN_5}${UPDATE_MARKER}"
    print_item "0" "$L_MAIN_0"
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
