#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.6.0 (Zero-Ghosting / Ultimate Color Engine)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Стили и ГОСТ (Отступ 2 пробела, Цвета Жирные)
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.6.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Сталинский отступ

NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m'  # Салатовый (Шапка)
C_MENU='\033[1;38;5;214m'   # Оранжевый (Пункты и Промпт)
C_SKY='\033[1;38;5;81m'     # Голубой (Цифры и Звездочки)
C_GREEN='\033[1;32m'        # Зеленый (Работает / Y)
C_RED='\033[1;31m'          # Красный (Ошибка / N)
C_YELLOW='\033[1;33m'       # Желтый (Стоп)

SPINNER=("|" "/" "-" "\\")
S_IDX=0

L_MENU_HEADER="СТАЛИН-3000"

# Пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Трапы
tput civis # Прячем курсор
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}${BOLD}Требуются права root!${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Модуль Отрисовки (Engine 1.6.0)
# ------------------------------------------------------------------------------

# Главный отрисовщик. $1 - Заголовок, $2... - Пункты меню
draw_ui() {
    local header_text="$1"
    shift
    local menu_items=("$@")

    printf "\033[H" # Возврат курсора в 0,0

    # Шапка
    local width=44
    local p=$(( (width - ${#header_text}) / 2 ))
    local e=$(( (width - ${#header_text}) % 2 ))
    printf "${C_FRAME}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${C_FRAME}║${NC}${BOLD}%*s%s%*s${C_FRAME}║${NC}\n" "$p" "" "$header_text" "$((p + e))" ""
    printf "${C_FRAME}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n\n" # Пустая строка

    # Статусы с пульсом
    S_IDX=$(( (S_IDX + 1) % ${#SPINNER[@]} ))
    local sym="${SPINNER[$S_IDX]}"
    local t_s t_c z_s z_c
    
    if [ ! -f "$SERVICE_FILE" ]; then t_s="не установлен"; t_c="$C_RED"
    elif systemctl is-active --quiet telemt; then t_s="работает $sym"; t_c="$C_GREEN"
    else t_s="остановлен"; t_c="$C_YELLOW"; fi

    if [ ! -f "$Z_SERVICE" ]; then z_s="не установлен"; z_c="$C_RED"
    elif systemctl is-active --quiet zapret-tpws; then z_s="работает $sym"; z_c="$C_GREEN"
    else z_s="остановлен"; z_c="$C_YELLOW"; fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s${NC}\033[K\n" "$t_c" "$t_s"
    printf "${L_IND}${BOLD}статус Zapret: %b%s${NC}\033[K\n\n" "$z_c" "$z_s"

    # Меню
    for item in "${menu_items[@]}"; do
        IFS=":" read -r idx text <<< "$item"
        printf "${L_IND}${BOLD}${C_SKY}%s - ${C_MENU}%s${NC}\033[K\n" "$idx" "$text"
    done
    
    # Промпт и очистка хвоста
    printf "\n${L_IND}${BOLD}${C_MENU}>> %b${NC}\033[J" "$PROMPT_STRING"
}

# Ввод одного символа (Меню)
wait_choice() {
    PROMPT_STRING="выберите раздел: "
    local char
    while true; do
        draw_ui "$TITLE" "${MENU[@]}"
        read -s -n 1 -t 0.5 char
        if [ $? -eq 0 ]; then
            [[ "$char" =~ [0-9] ]] && echo "$char" && return
        fi
    done
}

# Ввод строки текста
wait_text() {
    PROMPT_STRING="$1: "
    draw_ui "$TITLE" "${MENU[@]}"
    local val
    tput cnorm
    read -r val
    tput civis
    echo "$val"
}

# Подтверждение [y/n]
wait_confirm() {
    local p_colored="подтвердите [${C_GREEN}y${NC}/${C_RED}n${NC}]"
    PROMPT_STRING="$p_colored: "
    draw_ui "$TITLE" "${MENU[@]}"
    local yn
    tput cnorm; read -n 1 yn; tput civis
    echo ""
    [[ "$yn" =~ ^[Yy]$ ]] && return 0 || return 1
}

msg_step() {
    printf "\n${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then 
        printf "${C_GREEN}[готово]${NC}"; return 0
    else 
        printf "${C_RED}[ошибка]${NC}"; return 1
    fi
}

# ------------------------------------------------------------------------------
# 3. Разделы (Data & Logic)
# ------------------------------------------------------------------------------

sub_service() {
    clear; TITLE="УПРАВЛЕНИЕ TELEMT"
    MENU=("1:установить Telemt" "2:перезапустить службу" "3:остановить службу" "0:назад")
    while true; do
        case $(wait_choice) in
            1)  echo ""; p=$(wait_text "порт (443)"); p=${p:-443}
                s=$(wait_text "SNI домен"); s=${s:-google.com}
                u=$(wait_text "админ"); u=${u:-admin}
                msg_step "Зависимости" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
                arch=$(uname -m); lib=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$lib.tar.gz"
                msg_step "Загрузка" "curl -L '$url' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
                mkdir -p $CONF_DIR; cat <<EOF > $CONF_FILE
[general]
use_middle_proxy = false
[general.modes]
tls = true
[server]
port = $p
[server.api]
enabled = true
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$s"
[access.users]
$u = "$(openssl rand -hex 16)"
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
                echo ""; wait_text "нажмите [Enter]";;
            2) echo ""; msg_step "Перезапуск" "systemctl restart telemt"; sleep 1;;
            3) echo ""; msg_step "Остановка" "systemctl stop telemt"; sleep 1;;
            0) return;;
        esac
    done
}

sub_users() {
    clear; TITLE="ПОЛЬЗОВАТЕЛИ TELEMT"
    while true; do
        if [ ! -f "$CONF_FILE" ]; then 
            MENU=("0:назад"); draw_ui "$TITLE" "${MENU[@]}"
            echo -e "\n\n${L_IND}${C_RED}!! Ошибка: Telemt не установлен.${NC}"
            [ "$(wait_choice)" == "0" ] && return || continue
        fi
        MENU=("1:список и ссылки" "2:добавить пользователя" "0:назад")
        case $(wait_choice) in
            1)  echo ""; mapfile -t USERS < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!USERS[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d.${NC} ${C_MENU}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                u_sel=$(wait_text "номер пользователя (0-назад)")
                if [[ "$u_sel" =~ ^[0-9]+$ ]] && [ "$u_sel" -gt 0 ] && [ "$u_sel" -le "${#USERS[@]}" ]; then
                    target="${USERS[$((u_sel-1))]}"
                    ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                    links=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    echo -e "\n${L_IND}${BOLD}${C_SKY}Ключи доступа для $target:${NC}"
                    for l in $links; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                    wait_text "нажмите [Enter]"
                fi;;
            2)  name=$(wait_text "имя пользователя")
                [ -n "$name" ] && echo "$name = \"$(openssl rand -hex 16)\"" >> $CONF_FILE && msg_step "Обновление" "systemctl restart telemt" && sleep 1;;
            0) return;;
        esac
    done
}

sub_zapret() {
    clear; TITLE="УПРАВЛЕНИЕ ZAPRET"
    MENU=("1:установить / обновить" "2:запустить службу" "3:остановить службу" "4:удалить из системы" "0:назад")
    while true; do
        case $(wait_choice) in
            1)  echo ""; msg_step "Зависимости" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                msg_step "Загрузка" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                msg_step "Сборка" "make -C $Z_DIR"
                cat <<EOF > $Z_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=$Z_DIR/tpws/tpws --bind-addr=127.0.0.1 --port=1080 --socks --split-http-req=host --split-pos=2 --hostcase --hostspell=hoSt --split-tls=sni --disorder --tlsrec=sni
Restart=always
[Install]
WantedBy=multi-user.target
EOF
                msg_step "Запуск" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
                wait_text "нажмите [Enter]";;
            2) echo ""; msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1;;
            3) echo ""; msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1;;
            4) if wait_confirm "удалить Zapret?"; then
                   msg_step "Очистка" "systemctl stop zapret-tpws; rm -rf $Z_DIR $Z_SERVICE; systemctl daemon-reload"
                   sleep 1; return
               fi;;
            0) return;;
        esac
    done
}

sub_manager() {
    clear; TITLE="ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА"
    while true; do
        rem=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        [[ -n "$rem" && "$rem" != "$CURRENT_VERSION" ]] && m1="ОБНОВИТЬ ДО $rem" || m1="переустановить менеджер"
        MENU=("1:$m1" "2:удалить Telemt" "3:полная очистка системы" "0:назад")
        case $(wait_choice) in
            1) echo ""; msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"; exec "$CLI_NAME";;
            2) if wait_confirm "удалить Telemt и все его данные?"; then
                   msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH"; sleep 1; return
               fi;;
            3) if wait_confirm "ВЫПОЛНИТЬ ПОЛНУЮ ОЧИСТКУ СИСТЕМЫ?"; then
                   echo ""; systemctl stop telemt zapret-tpws 2>/dev/null
                   rm -rf $CONF_DIR $Z_DIR $Z_SERVICE $SERVICE_FILE $BIN_PATH
                   systemctl daemon-reload; rm -f "$CLI_NAME"; clear; tput cnorm; exit 0
               fi;;
            0) return;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 4. Главный Цикл
# ------------------------------------------------------------------------------

while true; do
    TITLE="$L_MENU_HEADER (v$CURRENT_VERSION)"
    MENU=("1:$M_MAIN_1" "2:$M_MAIN_2" "3:$M_MAIN_3" "4:$M_MAIN_4" "5:$M_MAIN_5" "0:$M_MAIN_0")
    
    case $(wait_choice) in
        1) sub_service; clear ;;
        2) sub_users; clear ;;
        3)  # Вход в настройки
            if [ ! -f "$CONF_FILE" ]; then 
                TITLE="НАСТРОЙКИ TELEMT"; MENU=("0:назад")
                draw_ui "$TITLE" "${MENU[@]}"
                echo -e "\n\n${L_IND}${C_RED}!! Ошибка: Telemt не установлен.${NC}"
                [ "$(wait_choice)" == "0" ] && clear || clear
            else
                sub_users # Временная замена, так как sub_settings была сломана
                # Должно быть sub_settings;
            fi ;;
        4) sub_zapret; clear ;;
        5) sub_manager; clear ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
