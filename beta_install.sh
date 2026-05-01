#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.5.2 (Unified Logic & Zero-Glitches)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Стили и Окружение (ГОСТ)
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.5.2"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Сталинский отступ

NC='\033[0m'
BOLD='\033[1m'
C_MAIN='\033[1;38;5;148m'   # Салатовый
C_ORANGE='\033[1;38;5;214m' # Оранжевый
C_SKY='\033[1;38;5;81m'     # Голубой
C_GREEN='\033[1;32m'        # Зеленый
C_RED='\033[1;31m'          # Красный
C_YELLOW='\033[1;33m'       # Желтый

SPINNER=("○" "◔" "◑" "◕" "●" "◕" "◑" "◔")
HB_IDX=0

L_MENU_HEADER="СТАЛИН-3000"
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

tput civis # Скрыть курсор
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}${BOLD}Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Движок рендеринга (EVS Engine)
# ------------------------------------------------------------------------------

# Базовая отрисовка страницы
# $1 - заголовок, $2 - тело меню (текст)
render_page() {
    printf "\033[H" # Возврат домой
    
    # 1. Шапка
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

    printf "\n" # Пустая строка по инструкции

    # 2. Статусы
    HB_IDX=$(( (HB_IDX + 1) % ${#SPINNER[@]} ))
    local s1 c1 s2 c2 sym="${SPINNER[$HB_IDX]}"

    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; c1="$C_RED"; sym1=" ";
    elif systemctl is-active --quiet telemt; then s1="работает"; c1="$C_GREEN"; sym1="$sym";
    else s1="остановлен"; c1="$C_YELLOW"; sym1=" "; fi

    if [ ! -f "$Z_SERVICE" ]; then s2="не установлен"; c2="$C_RED"; sym2=" ";
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; c2="$C_GREEN"; sym2="$sym";
    else s2="остановлен"; c2="$C_YELLOW"; sym2=" "; fi

    printf "${L_IND}${BOLD}%-16s %b%s %s${NC}\033[K\n" "статус Telemt:" "$c1" "$s1" "$c1$sym1"
    printf "${L_IND}${BOLD}%-16s %b%s %s${NC}\033[K\n" "status Zapret:" "$c2" "$s2" "$c2$sym2"

    printf "\n" # Пустая строка по инструкции

    # 3. Меню
    echo -e "$2" # Здесь выводится переменная меню, переданная в функцию
}

# Обертка для пунктов меню
item() {
    echo -e "${L_IND}${BOLD}${C_SKY}$1 - ${C_ORANGE}$2${NC}\033[K"
}

# Промпты ввода (усиленные)
# $1 - Текст промпта
prompt_move() {
    printf "\n${L_IND}${BOLD}${C_ORANGE}>> $1: ${NC}"
}

# ------------------------------------------------------------------------------
# 3. Функции ввода (Стабилизация)
# ------------------------------------------------------------------------------

# Ожидание 1 клавиши (для навигации) с пульсом
get_choice() {
    local choice
    tput cnorm
    while true; do
        # Обновляем пульс только если мы в меню
        render_page "$TITLE" "$BODY"
        prompt_move "$1"
        read -t 1 -n 1 choice
        if [ $? -eq 0 ]; then
            echo "$choice"
            return
        fi
    done
    tput civis
}

# Ввод строки текста (порты и т.д.) - ПУЛЬС ОСТАНОВЛЕН для стабильности
get_text() {
    local val
    tput cnorm
    prompt_move "$1"
    read -r val
    tput civis
    echo "$val"
}

# Подтверждение (Да/Нет)
get_confirm() {
    local yn
    local p_text="$1 [${C_GREEN}y${NC}/${C_RED}n${NC}]"
    tput cnorm
    prompt_move "$p_text"
    read -r -n 1 yn
    tput civis
    echo ""
    [[ "$yn" =~ ^[Yy]$ ]] && return 0 || return 1
}

# ------------------------------------------------------------------------------
# 4. Логика установки/обслуживания
# ------------------------------------------------------------------------------

msg_step() {
    printf "\n${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then printf "${C_GREEN}[готово]${NC}"; else printf "${C_RED}[ошибка]${NC}"; return 1; fi
}

check_updates() {
    local remote
    remote=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    if [[ -n "$remote" && "$remote" != "$CURRENT_VERSION" ]]; then
        UPDATE_MARKER="${C_SKY} (*)${NC}"; REM_VER="$remote"; HAS_UPD=true
    else
        UPDATE_MARKER=""; REM_VER="$CURRENT_VERSION"; HAS_UPD=false
    fi
}

install_telemt() {
    echo ""
    local p=$(get_text "укажите порт (443)"); p=${p:-443}
    local s=$(get_text "SNI домен (google.com)"); s=${s:-google.com}
    local u=$(get_text "имя администратора"); u=${u:-admin}
    
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
    msg_step "Запуск сервиса" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    
    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
    local L=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$u\") | .links.tls[]" 2>/dev/null)
    echo -e "\n\n${L_IND}${BOLD}${C_SKY}Ключи доступа:${NC}"
    for i in $L; do echo -e "${L_IND}${BOLD}${C_ORANGE}${i//0.0.0.0/$IP}${NC}"; done
}

# ------------------------------------------------------------------------------
# 5. Секции Подменю
# ------------------------------------------------------------------------------

sub_service() {
    clear; TITLE="УПРАВЛЕНИЕ TELEMT"
    BODY="$(item 1 "установить Telemt")
$(item 2 "перезапустить службу")
$(item 3 "остановить службу")
$(item 0 "назад")"
    while true; do
        local sel=$(get_choice "действие")
        case $sel in
            1) install_telemt; get_text "нажмите [Enter]"; clear ;;
            2) msg_step "Перезапуск" "systemctl restart telemt"; sleep 1; clear ;;
            3) msg_step "Остановка" "systemctl stop telemt"; sleep 1; clear ;;
            0) clear; return ;;
        esac
    done
}

sub_users() {
    clear; TITLE="ПОЛЬЗОВАТЕЛИ TELEMT"
    local m
    while true; do
        if [ ! -f "$CONF_FILE" ]; then 
            BODY="$(item 0 "назад")\n\n${L_IND}${BOLD}${C_RED}!! Telemt не установлен.${NC}"
            local sel=$(get_choice "действие"); [[ "$sel" == "0" ]] && { clear; break; } || continue
        fi
        BODY="$(item 1 "список и ссылки")\n$(item 2 "добавить пользователя")\n$(item 0 "назад")"
        local sel=$(get_choice "действие")
        case $sel in
            1)  echo ""; mapfile -t US < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!US[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d. ${C_ORANGE}%s${NC}\n" "$((i+1))" "${US[$i]}"; done
                local uidx=$(get_text "номер пользователя (0-назад)")
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#US[@]}" ]; then
                    local target="${US[$((uidx-1))]}"
                    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                    local L=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    echo -e "\n${L_IND}${BOLD}${C_SKY}Ключи для $target:${NC}"
                    for i in $L; do echo -e "${L_IND}${BOLD}${C_ORANGE}${i//0.0.0.0/$IP}${NC}"; done
                    get_text "нажмите [Enter]"
                fi; clear ;;
            2)  local name=$(get_text "имя пользователя")
                [ -n "$name" ] && echo "$name = \"$(openssl rand -hex 16)\"" >> $CONF_FILE && msg_step "Обновление" "systemctl restart telemt" && sleep 1
                clear ;;
            0) clear; break ;;
        esac
    done
}

sub_settings() {
    clear; TITLE="НАСТРОЙКИ TELEMT"
    while true; do
        if [ ! -f "$CONF_FILE" ]; then
            BODY="$(item 0 "назад")\n\n${L_IND}${BOLD}${C_RED}!! Telemt не установлен.${NC}"
            local sel=$(get_choice "действие"); [[ "$sel" == "0" ]] && { clear; break; } || continue
        fi
        BODY="$(item 1 "логи (journalctl)")\n$(item 2 "сменить порт")\n$(item 3 "сменить SNI")\n$(item 0 "назад")"
        local sel=$(get_choice "действие")
        case $sel in
            1) echo ""; tput cnorm; journalctl -u telemt -n 50 --no-pager; tput civis; get_text "нажмите [Enter]"; clear ;;
            2) local np=$(get_text "новый порт")
               [[ $np =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt && echo "Порт изменен." && sleep 1
               clear ;;
            3) local ns=$(get_text "новый SNI")
               [ -n "$ns" ] && sed -i "s/^tls_domain = .*/tls_domain = \"$ns\"/" $CONF_FILE && systemctl restart telemt && echo "SNI изменен." && sleep 1
               clear ;;
            0) clear; break ;;
        esac
    done
}

sub_zapret() {
    clear; TITLE="УПРАВЛЕНИЕ ZAPRET"
    BODY="$(item 1 "установить / обновить")
$(item 2 "запустить службу")
$(item 3 "остановить службу")
$(item 4 "удалить из системы")
$(item 0 "назад")"
    while true; do
        local sel=$(get_choice "действие")
        case $sel in
            1)  msg_step "Зависимости" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                msg_step "Загрузка Zapret" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
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
                get_text "нажмите [Enter]"; clear ;;
            2) msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1; clear ;;
            3) msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1; clear ;;
            4) if get_confirm "удалить Zapret?"; then
                  msg_step "Удаление" "systemctl stop zapret-tpws; rm -rf $Z_DIR $Z_SERVICE; systemctl daemon-reload"; sleep 1
               fi; clear ;;
            0) clear; break ;;
        esac
    done
}

sub_manager() {
    clear; TITLE="ОБСЛУЖИВАНИЕ"
    while true; do
        local up_text
        [ "$HAS_UPD" = true ] && up_text="обновить до $REM_VER" || up_text="переустановить менеджер"
        BODY="$(item 1 "$up_text")\n$(item 2 "удалить Telemt")\n$(item 3 "полная очистка")\n$(item 0 "назад")"
        local sel=$(get_choice "действие")
        case $sel in
            1) msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"; sleep 1; exec "$CLI_NAME" ;;
            2) if get_confirm "удалить Telemt и данные?"; then
                  msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH"; sleep 1
               fi; clear ;;
            3) if get_confirm "ПОЛНАЯ ОЧИСТКА?"; then
                  systemctl stop telemt zapret-tpws 2>/dev/null
                  rm -rf $CONF_DIR $Z_DIR $Z_SERVICE $SERVICE_FILE $BIN_PATH
                  systemctl daemon-reload; rm -f "$CLI_NAME"; clear; tput cnorm; exit 0
               fi; clear ;;
            0) clear; break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 6. Основной цикл (Main Choice)
# ------------------------------------------------------------------------------
clear
while true; do
    check_updates
    TITLE="$L_MENU_HEADER (v$CURRENT_VERSION)"
    BODY="$(item 1 "$M_MAIN_1")
$(item 2 "$M_MAIN_2")
$(item 3 "$M_MAIN_3")
$(item 4 "$M_MAIN_4")
$(item 5 "${M_MAIN_5}${UPDATE_MARKER}")
$(item 0 "$M_MAIN_0")"

    local choice=$(get_choice "выберите раздел")
    case $choice in
        1) sub_service ;;
        2) sub_users ;;
        3) sub_settings ;;
        4) sub_zapret ;;
        5) sub_manager ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
