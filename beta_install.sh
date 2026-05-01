#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.6.1 (Steel Engine - Zero Capturing Fix)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Стили и ГОСТ (Стандарт: 2 пробела, Текст ЖИРНЫЙ)
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.6.1"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Стандартный отступ

NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m'  # Салатовый
C_MENU='\033[1;38;5;214m'   # Оранжевый
C_SKY='\033[1;38;5;81m'     # Голубой
C_GREEN='\033[1;32m'        # Зеленый
C_RED='\033[1;31m'          # Красный
C_YELLOW='\033[1;33m'       # Желтый

SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
S_IDX=0

# Системные пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Системные настройки (трапы и скрытие курсора)
tput civis
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}${BOLD}Нужен root!${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. Модуль Отрисовки (Honest Output Engine)
# ------------------------------------------------------------------------------

# Отрисовка статусов
draw_status() {
    S_IDX=$(( (S_IDX + 1) % ${#SPINNER[@]} ))
    local sym="${SPINNER[$S_IDX]}"
    local s1 c1 s2 c2
    
    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; c1="$C_RED"; sym1=" ";
    elif systemctl is-active --quiet telemt; then s1="работает"; c1="$C_GREEN"; sym1="$sym";
    else s1="остановлен"; c1="$C_YELLOW"; sym1=" "; fi

    if [ ! -f "$Z_SERVICE" ]; then s2="не установлен"; c2="$C_RED"; sym2=" ";
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; c2="$C_GREEN"; sym2="$sym";
    else s2="остановлен"; c2="$C_YELLOW"; sym2=" "; fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s %s${NC}\033[K\n" "$c1" "$s1" "$c1$sym1"
    printf "${L_IND}${BOLD}статус Zapret: %b%s %s${NC}\033[K\n" "$c2" "$s2" "$c2$sym2"
}

# Отрисовка страницы. Прямой вывод в терминал, никаких захватов в переменные!
render_view() {
    local h="$1"
    shift
    local items=("$@")
    
    printf "\033[H" # В начало экрана
    
    # Шапка
    local w=44
    local p=$(( (w - ${#h}) / 2 ))
    local e=$(( (w - ${#h}) % 2 ))
    printf "${C_FRAME}╔"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${C_FRAME}║${NC}${BOLD}%*s%s%*s${C_FRAME}║${NC}\n" "$p" "" "$h" "$((p + e))" ""
    printf "${C_FRAME}╚"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╝${NC}\n\n" # Пустая строка
    
    # Статус
    draw_status
    printf "\n" # Пустая строка
    
    # Меню
    for row in "${items[@]}"; do
        local idx=$(echo "$row" | cut -d: -f1)
        local txt=$(echo "$row" | cut -d: -f2)
        printf "${L_IND}${BOLD}${C_SKY}%s - ${C_MENU}%s${NC}\033[K\n" "$idx" "$txt"
    done
    
    # Промпт и зачистка старого хвоста
    printf "\n${L_IND}${BOLD}${C_MENU}>> %b${NC}\033[J" "$P_STR"
}

# Ввод одного символа (Выбор в меню) с крутящимся пульсом
input_choice() {
    P_STR="выберите раздел: "
    local char
    while true; do
        render_view "$VIEW_TITLE" "${VIEW_MENU[@]}"
        read -s -n 1 -t 0.3 char # Быстрое обновление для пульса
        if [ $? -eq 0 ]; then
            [[ "$char" =~ [0-9] ]] && echo "$char" && return
        fi
    done
}

# Ввод текста (без пульса, чтобы не ломать ввод)
input_text() {
    P_STR="$1"
    render_view "$VIEW_TITLE" "${VIEW_MENU[@]}"
    local val
    tput cnorm; read -r val; tput civis
    echo "$val"
}

# Пакетное уведомление о шаге
msg_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then 
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else 
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

msg_done() { printf "\n${L_IND}${BOLD}${C_GREEN}УСПЕХ: %s${NC}\n" "$1"; }

# ------------------------------------------------------------------------------
# 3. Функциональные модули
# ------------------------------------------------------------------------------

# Получение данных о версии
check_upd() {
    local rem=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    [[ -n "$rem" && "$rem" != "$CURRENT_VERSION" ]] && M_MARK="${C_SKY} (*)${NC}" || M_MARK=""
}

# Очистка за Telemt
clear_t() {
    msg_step "Остановка Telemt" "systemctl stop telemt"
    msg_step "Удаление файлов" "rm -rf $CONF_DIR $BIN_PATH $SERVICE_FILE"
    systemctl daemon-reload
}

# Очистка за Zapret
clear_z() {
    msg_step "Остановка Zapret" "systemctl stop zapret-tpws"
    msg_step "Удаление Zapret" "rm -rf $Z_DIR $Z_SERVICE"
    systemctl daemon-reload
}

# ------------------------------------------------------------------------------
# 4. Меню и логика (State Machine)
# ------------------------------------------------------------------------------

sub_service() {
    VIEW_TITLE="УПРАВЛЕНИЕ TELEMT"
    VIEW_MENU=("1:установить Telemt" "2:перезапустить" "3:остановить" "0:назад")
    while true; do
        case $(input_choice) in
            1)  printf "\n\n" # Переход в секцию вывода
                p=$(input_text "укажите порт (443)"); p=${p:-443}
                s=$(input_text "SNI домен"); s=${s:-google.com}
                u=$(input_text "имя админа"); u=${u:-admin}
                printf "\n"
                msg_step "Установка зависимостей" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
                arch=$(uname -m); lib=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$lib.tar.gz"
                msg_step "Загрузка бинарных файлов" "curl -L '$url' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
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
                msg_step "Запуск системы" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                msg_done "Telemt установлен"
                input_text "нажмите [Enter]"; clear ;;
            2) printf "\n\n"; msg_step "Перезапуск" "systemctl restart telemt"; sleep 1; clear ;;
            3) printf "\n\n"; msg_step "Остановка" "systemctl stop telemt"; sleep 1; clear ;;
            0) clear; break ;;
        esac
    done
}

sub_zapret() {
    VIEW_TITLE="УПРАВЛЕНИЕ ZAPRET"
    VIEW_MENU=("1:установить / обновить" "2:запустить" "3:остановить" "4:удалить" "0:назад")
    while true; do
        case $(input_choice) in
            1)  printf "\n\n"; 
                msg_step "Инструменты сборки" "apt-get update -qq && apt-get install -y build-essential git libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev -qq"
                msg_step "Клонирование репо" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                msg_step "Компиляция (make)" "make -C $Z_DIR"
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
                msg_step "Активация Zapret" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
                input_text "нажмите [Enter]"; clear ;;
            2) printf "\n\n"; msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1; clear ;;
            3) printf "\n\n"; msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1; clear ;;
            4) printf "\n\n"; msg_step "Удаление Zapret" "clear_z"; sleep 1; clear ;;
            0) clear; break ;;
        esac
    done
}

# --- Главный цикл ---
clear
while true; do
    check_upd
    VIEW_TITLE="СТАЛИН-3000 (v$CURRENT_VERSION)"
    VIEW_MENU=("1:управление сервисом Telemt" "2:управление пользователями" "3:настройки" "4:управление Zapret" "5:обслуживание менеджера${M_MARK}" "0:выход")
    
    case $(input_choice) in
        1) sub_service ;;
        4) sub_zapret ;;
        5) clear; VIEW_TITLE="ОБСЛУЖИВАНИЕ"
           VIEW_MENU=("1:обновить менеджер" "2:полная очистка системы" "0:назад")
           while true; do
             case $(input_choice) in
                1) printf "\n\n"; msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"; exec "$CLI_NAME" ;;
                2) printf "\n\n"; clear_t; clear_z; rm -f "$CLI_NAME"; tput cnorm; echo "Система очищена. До свидания."; exit 0 ;;
                0) clear; break ;;
             esac
           done ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
