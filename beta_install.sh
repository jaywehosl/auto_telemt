#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.4.1 (Color & Logic Refined)
# ==============================================================================

# ------------------------------------------------------------------------------
# Конфигурация и Палитра
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.4.1"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Стандартный отступ

BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m' # Салатовый (Рамки, Заголовки)
ORANGE='\033[1;38;5;214m'  # Оранжевый (Ввод данных)
SKY_BLUE='\033[1;38;5;81m' # Голубой (Инфо, Шаги)
GREEN='\033[1;32m'         # Зеленый (Успех)
RED='\033[1;31m'           # Красный (Ошибки, Удаление)
YELLOW='\033[1;33m'        # Желтый (Предупреждения)

# Текстовые переменные
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_T="статус Telemt:"
L_STATUS_Z="статус Zapret:"

# Анимация "Пульс"
HEARTBEAT_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
HB_IDX=0

# Пути
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
ZAPRET_DIR="/opt/zapret"
ZAPRET_SERVICE="/etc/systemd/system/zapret-tpws.service"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Ошибка: Запуск от root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# Модуль UI (Типизация вывода)
# ------------------------------------------------------------------------------

# Шапка с анимацией
draw_header() {
    local title="$1"
    local width=44
    local text_len=${#title}
    local padding=$(( (width - text_len) / 2 ))
    local extra=$(( (width - text_len) % 2 ))
    
    HB_IDX=$(( (HB_IDX + 1) % ${#HEARTBEAT_FRAMES[@]} ))
    local pulse="${SKY_BLUE}${HEARTBEAT_FRAMES[$HB_IDX]}${NC}"

    printf "${BOLD}${MAIN_COLOR}╔"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║${NC}%*s%s%*s${BOLD}${MAIN_COLOR}║${NC} [${pulse}]\n" "$padding" "" "$title" "$((padding + extra))" ""
    printf "${BOLD}${MAIN_COLOR}╚"
    for ((i=0; i<width; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Блок статусов (Единый формат)
msg_status() {
    local s1 s2
    if [ ! -f "$SERVICE_FILE" ]; then s1="${RED}не установлен${NC}"
    elif systemctl is-active --quiet telemt; then s1="${GREEN}работает${NC}"
    else s1="${YELLOW}остановлен${NC}"; fi

    if [ ! -f "$ZAPRET_SERVICE" ]; then s2="${RED}не установлен${NC}"
    elif systemctl is-active --quiet zapret-tpws; then s2="${GREEN}работает${NC}"
    else s2="${YELLOW}остановлен${NC}"; fi

    printf "${L_IND}%-20s %b\n" "$L_STATUS_T" "$s1"
    printf "${L_IND}%-20s %b\n" "$L_STATUS_Z" "$s2"
}

# Лог действий (Шаги)
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

# Промпт ввода
msg_prompt() {
    echo -ne "\n${L_IND}${BOLD}${ORANGE}>> $1: ${NC}"
}

# Системные уведомления
msg_error() { echo -e "${L_IND}${RED}${BOLD}!! ОШИБКА: ${NC}$1"; }
msg_info()  { echo -e "${L_IND}${SKY_BLUE}${BOLD}i ИНФО: ${NC}$1"; }
msg_ok()    { echo -e "${L_IND}${GREEN}${BOLD}ok УСПЕХ: ${NC}$1"; }

# ------------------------------------------------------------------------------
# Системная логика
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
    printf "\n${L_IND}${SKY_BLUE}Нажмите [Enter] для продолжения...${NC}"
    read -r
}

get_user_list() {
    [ -f "$CONF_FILE" ] && sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${L_IND}${BOLD}${SKY_BLUE}Ключи доступа для ${MAIN_COLOR}$target_user${SKY_BLUE}:${NC}"
    local IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
    local LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        msg_error "Данные не получены. Сервис Telemt запущен?"
    else
        for link in $LINKS; do
            echo -e "${L_IND}  ${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
        done
    fi
}

# ------------------------------------------------------------------------------
# Установка и Удаление
# ------------------------------------------------------------------------------

install_telemt() {
    echo ""
    msg_info "Первичная настройка Telemt"
    echo -ne "${L_IND}  Порт (443): "; read P_PORT; P_PORT=${P_PORT:-443}
    echo -ne "${L_IND}  SNI домен:  "; read P_SNI; P_SNI=${P_SNI:-google.com}
    echo -ne "${L_IND}  Имя админа: "; read P_USER; P_USER=${P_USER:-admin}
    echo ""
    
    msg_step "Установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    
    local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    
    msg_step "Загрузка бинарных файлов" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
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
    msg_step "Запуск системы" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    show_links "$P_USER"
}

install_zapret() {
    echo ""
    msg_step "Установка build-essential" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
    msg_step "Загрузка исходников" "rm -rf $ZAPRET_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $ZAPRET_DIR"
    msg_step "Компиляция проекта" "make -C $ZAPRET_DIR"
    
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
    msg_step "Активация Zapret" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
}

# ------------------------------------------------------------------------------
# Интерфейс Подменю
# ------------------------------------------------------------------------------

submenu_service() {
    while true; do
        clear; draw_header "СЕРВИС TELEMT"
        msg_status; echo ""
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 1 -${NC} установить Telemt"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 2 -${NC} перезапустить службу"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 3 -${NC} остановить службу"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} назад"
        msg_prompt "действие"; read sc
        case $sc in
            1) install_telemt; wait_user ;;
            2) msg_step "Перезапуск" "systemctl restart telemt"; wait_user ;;
            3) msg_step "Остановка" "systemctl stop telemt"; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"
        msg_status; echo ""
        if [ ! -f "$CONF_FILE" ]; then msg_error "Telemt не установлен."; wait_user; break; fi
        
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 1 -${NC} список пользователей"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 2 -${NC} добавить пользователя"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} назад"
        msg_prompt "действие"; read sc
        case $sc in
            1) mapfile -t USERS < <(get_user_list)
               echo ""
               for i in "${!USERS[@]}"; do printf "${L_IND}  ${SKY_BLUE}%d.${NC} %s\n" "$((i+1))" "${USERS[$i]}"; done
               msg_prompt "номер пользователя [${SKY_BLUE}0-назад${NC}]"; read uidx
               if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#USERS[@]}" ]; then
                   show_links "${USERS[$((uidx-1))]}" && wait_user
               elif [ "$uidx" == "0" ]; then continue; fi ;;
            2) echo -ne "${L_IND}  Имя нового пользователя: "; read uname
               if [[ -n "$uname" ]]; then
                   echo "$uname = \"$(openssl rand -hex 16)\"" >> $CONF_FILE
                   msg_step "Обновление конфигурации" "systemctl restart telemt"
               fi; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear; draw_header "НАСТРОЙКИ TELEMT"
        msg_status; echo ""
        if [ ! -f "$CONF_FILE" ]; then msg_error "Telemt не установлен."; wait_user; break; fi
        
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 1 -${NC} просмотр логов"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 2 -${NC} сменить порт"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 3 -${NC} сменить SNI"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} назад"
        msg_prompt "действие"; read sc
        case $sc in
            1) journalctl -u telemt -n 50 --no-pager; wait_user ;;
            2) echo -ne "${L_IND}  Новый порт: "; read np
               if [[ $np =~ ^[0-9]+$ ]]; then sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt; msg_ok "Порт изменен"; fi; wait_user ;;
            3) echo -ne "${L_IND}  Новый SNI:  "; read ns
               if [ -n "$ns" ]; then sed -i "s/^tls_domain = .*/tls_domain = \"$ns\"/" $CONF_FILE && systemctl restart telemt; msg_ok "SNI изменен"; fi; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_zapret() {
    while true; do
        clear; draw_header "ZAPRET (TPWS)"
        msg_status; echo ""
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 1 -${NC} установить / обновить"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 2 -${NC} запустить службу"
        echo -e "${L_IND}${BOLD}${MAIN_COLOR} 3 -${NC} остановить службу"
        echo -e "${L_IND}${BOLD}${RED} 4 -${NC} удалить из системы"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} назад"
        msg_prompt "действие"; read sc
        case $sc in
            1) install_zapret; wait_user ;;
            2) msg_step "Запуск" "systemctl start zapret-tpws"; wait_user ;;
            3) msg_step "Остановка" "systemctl stop zapret-tpws"; wait_user ;;
            4) echo -ne "${L_IND}  Удалить Zapret? [y/n]: "; read confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && msg_step "Удаление" "systemctl stop zapret-tpws; rm -rf $ZAPRET_DIR $ZAPRET_SERVICE; systemctl daemon-reload" && wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        clear; draw_header "ОБСЛУЖИВАНИЕ"
        msg_status; echo ""
        if [ "$HAS_UPDATE" = true ]; then
            echo -e "${L_IND}${BOLD}${SKY_BLUE} 1 -${NC} ОБНОВИТЬ МЕНЕДЖЕР ДО ${BOLD}${GREEN}$REMOTE_VERSION${NC}"
        fi
        echo -e "${L_IND}${BOLD}${RED} 2 -${NC} удалить Telemt"
        echo -e "${L_IND}${BOLD}${RED} 3 -${NC} полная очистка системы"
        echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} назад"
        msg_prompt "действие"; read sc
        case $sc in
            1) if [ "$HAS_UPDATE" = true ]; then
                   msg_step "Загрузка обновления" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"
                   msg_ok "Обновлено. Перезапуск..."; sleep 1; exec "$CLI_NAME"
               fi ;;
            2) echo -ne "${L_IND}  Удалить Telemt? [y/n]: "; read confirm
               [[ "$confirm" =~ ^[Yy]$ ]] && msg_step "Очистка" "systemctl stop telemt; rm -rf $CONF_DIR $SERVICE_FILE $BIN_PATH" && wait_user ;;
            3) echo -ne "${L_IND}  ${RED}ВЫПОЛНИТЬ ПОЛНУЮ ОЧИСТКУ? [y/n]: ${NC}"; read confirm
               if [[ "$confirm" =~ ^[Yy]$ ]]; then
                   systemctl stop telemt zapret-tpws 2>/dev/null
                   rm -rf $CONF_DIR $ZAPRET_DIR $ZAPRET_SERVICE $SERVICE_FILE $BIN_PATH
                   systemctl daemon-reload; rm -f "$CLI_NAME"
                   echo -e "\n${L_IND}${RED}${BOLD}Система очищена. Скрипт удален.${NC}"; exit 0
               fi ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Точка входа
# ------------------------------------------------------------------------------
while true; do
    check_updates
    clear; draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    msg_status; echo ""

    echo -e "${L_IND}${BOLD}${MAIN_COLOR} 1 -${NC} $L_MAIN_1"
    echo -e "${L_IND}${BOLD}${MAIN_COLOR} 2 -${NC} $L_MAIN_2"
    echo -e "${L_IND}${BOLD}${MAIN_COLOR} 3 -${NC} $L_MAIN_3"
    echo -e "${L_IND}${BOLD}${MAIN_COLOR} 4 -${NC} $L_MAIN_4"
    echo -e "${L_IND}${BOLD}${MAIN_COLOR} 5 -${NC} $L_MAIN_5${UPDATE_MARKER}"
    echo -e "${L_IND}${BOLD}${SKY_BLUE} 0 -${NC} $L_MAIN_0"
    
    msg_prompt "выберите раздел"
    read -t 2 mainchoice # Таймаут 2 сек для обновления анимации Пульса
    
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_zapret ;;
        5) submenu_manager ;;
        0) clear; exit 0 ;;
    esac
done
