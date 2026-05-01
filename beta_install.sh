#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-СЕРВИСАМИ «СТАЛИН-3000»
# Версия: 1.7.0 (Honest Output Edition)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. ГОСТ (Цвета, Отступы, Пути)
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.7.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Отступ 2 пробела

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

BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

tput civis # Скрыть курсор
trap 'tput cnorm; clear; exit' INT TERM EXIT

if [ "$EUID" -ne 0 ]; then echo -e "${C_RED}${BOLD}Ошибка: Нужен root.${NC}"; exit 1; fi

# ------------------------------------------------------------------------------
# 2. UI Модули (Прямой вывод)
# ------------------------------------------------------------------------------

# Отрисовка шапки
draw_h() {
    local h="$1"
    local w=44
    local p=$(( (w - ${#h}) / 2 ))
    local e=$(( (w - ${#h}) % 2 ))
    printf "${C_FRAME}╔"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${C_FRAME}║${NC}${BOLD}%*s%s%*s${C_FRAME}║${NC}\n" "$p" "" "$h" "$((p + e))" ""
    printf "${C_FRAME}╚"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# Отрисовка статусов
draw_s() {
    S_IDX=$(( (S_IDX + 1) % ${#SPINNER[@]} ))
    local pulse="${SPINNER[$S_IDX]}"
    local s1 c1 s2 c2
    
    if [ ! -f "$SERVICE_FILE" ]; then s1="не установлен"; c1="$C_RED"; p1=""
    elif systemctl is-active --quiet telemt; then s1="работает"; c1="$C_GREEN"; p1="$pulse"
    else s1="остановлен"; c1="$C_YELLOW"; p1=""
    fi

    if [ ! -f "$Z_SERVICE" ]; then s2="не установлен"; c2="$C_RED"; p2=""
    elif systemctl is-active --quiet zapret-tpws; then s2="работает"; c2="$C_GREEN"; p2="$pulse"
    else s2="остановлен"; c2="$C_YELLOW"; p2=""
    fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s %s${NC}\033[K\n" "$c1" "$s1" "$p1"
    printf "${L_IND}${BOLD}статус Zapret: %b%s %s${NC}\033[K\n" "$c2" "$s2" "$p2"
}

# Выполнение этапа
msg_step() {
    printf "\n${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then 
        printf "${C_GREEN}[готово]${NC}"; return 0
    else 
        printf "${C_RED}[ошибка]${NC}"; return 1
    fi
}

msg_ok() { printf "\n\n${L_IND}${BOLD}${C_GREEN}ok УСПЕХ: %s${NC}\n" "$1"; }
msg_err() { printf "\n\n${L_IND}${BOLD}${C_RED}!! ОШИБКА: %s${NC}\n" "$1"; }

# ------------------------------------------------------------------------------
# 3. Ввод данных
# ------------------------------------------------------------------------------

# Главный цикл опроса клавиатуры
# $1 - Название меню, $2... - Пункты в формате "1:текст"
show_menu() {
    local head="$1"
    shift
    local menu_items=("$@")
    local choice=""

    while true; do
        printf "\033[H" # Домой
        draw_h "$head"
        printf "\n"
        draw_s
        printf "\n"
        for item in "${menu_items[@]}"; do
            printf "${L_IND}${BOLD}${C_SKY}%s - ${NC}${BOLD}${C_MENU}%s${NC}\033[K\n" "$(echo $item | cut -d: -f1)" "$(echo $item | cut -d: -f2)"
        done
        printf "\n\033[K"
        printf "${L_IND}${BOLD}${C_MENU}>> выберите раздел: ${NC}"
        
        # Ждем 1 символ с таймаутом для пульса
        read -s -n 1 -t 0.3 choice
        if [ $? -eq 0 ]; then
            [[ "$choice" =~ [0-9] ]] && echo "$choice" && return
        fi
    done
}

# Ввод текста (порта, домена и т.д.)
ask_text() {
    local val=""
    printf "\n${L_IND}${BOLD}${C_ORANGE}>> $1: ${NC}"
    tput cnorm
    read -r val
    tput civis
    echo "$val"
}

# Подтверждение y/n
ask_confirm() {
    local yn=""
    printf "\n${L_IND}${BOLD}${C_ORANGE}>> $1 [${C_GREEN}y${NC}/${C_RED}n${NC}]: ${NC}"
    tput cnorm
    read -r -n 1 yn
    tput civis
    [[ "$yn" =~ ^[Yy]$ ]] && return 0 || return 1
}

# ------------------------------------------------------------------------------
# 4. Логика Подменю
# ------------------------------------------------------------------------------

sub_service() {
    clear
    while true; do
        case $(show_menu "УПРАВЛЕНИЕ TELEMT" "1:установить Telemt" "2:перезапустить" "3:остановить" "0:назад") in
            1)  printf "\n"
                p=$(ask_text "укажите порт (443)"); p=${p:-443}
                s=$(ask_text "SNI домен"); s=${s:-google.com}
                u=$(ask_text "имя админа"); u=${u:-admin}
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
                msg_ok "Telemt развернут"
                ask_text "нажмите [Enter]"; clear ;;
            2) printf "\n"; msg_step "Перезапуск" "systemctl restart telemt"; sleep 1; clear ;;
            3) printf "\n"; msg_step "Остановка" "systemctl stop telemt"; sleep 1; clear ;;
            0) clear; break ;;
        esac
    done
}

sub_users() {
    clear
    while true; do
        if [ ! -f "$CONF_FILE" ]; then 
            show_menu "ПОЛЬЗОВАТЕЛИ TELEMT" "0:назад" > /dev/null
            msg_err "Telemt не установлен."
            [ "$(ask_text "введите 0")" == "0" ] && { clear; break; } || continue
        fi
        case $(show_menu "ПОЛЬЗОВАТЕЛИ TELEMT" "1:список и ссылки" "2:добавить" "0:назад") in
            1)  echo ""
                mapfile -t US < <(sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!US[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d.${NC} ${C_MENU}%s${NC}\n" "$((i+1))" "${US[$i]}"; done
                u_sel=$(ask_text "номер пользователя (0-назад)")
                if [[ "$u_sel" =~ ^[0-9]+$ ]] && [ "$u_sel" -gt 0 ] && [ "$u_sel" -le "${#US[@]}" ]; then
                    target="${US[$((u_sel-1))]}"
                    ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_ERR")
                    links=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    printf "\n${L_IND}${BOLD}${C_SKY}Ключи для $target:${NC}\n"
                    for l in $links; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                    ask_text "нажмите [Enter]"
                fi; clear ;;
            2)  n=$(ask_text "имя пользователя")
                [ -n "$n" ] && echo "$n = \"$(openssl rand -hex 16)\"" >> $CONF_FILE && msg_step "Обновление" "systemctl restart telemt" && sleep 1; clear ;;
            0) clear; break ;;
        esac
    done
}

sub_zapret() {
    clear
    while true; do
        case $(show_menu "УПРАВЛЕНИЕ ZAPRET" "1:установить / обновить" "2:запустить" "3:остановить" "4:удалить" "0:назад") in
            1)  printf "\n"
                msg_step "Инструменты" "apt-get update -qq && apt-get install -y build-essential git libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev -qq"
                msg_step "Загрузка" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                msg_step "Компиляция" "make -C $Z_DIR"
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
                msg_ok "Zapret активен"
                ask_text "нажмите [Enter]"; clear ;;
            2) printf "\n"; msg_step "Запуск" "systemctl start zapret-tpws"; sleep 1; clear ;;
            3) printf "\n"; msg_step "Остановка" "systemctl stop zapret-tpws"; sleep 1; clear ;;
            4) printf "\n"; if ask_confirm "удалить Zapret?"; then
                  msg_step "Удаление" "systemctl stop zapret-tpws && rm -rf $Z_DIR $Z_SERVICE"
                  sleep 1;
               fi; clear ;;
            0) clear; break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. ГЛАВНЫЙ ЦИКЛ
# ------------------------------------------------------------------------------
clear
while true; do
    # Проверка обновлений
    rem=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    [[ -n "$rem" && "$rem" != "$CURRENT_VERSION" ]] && mark="${C_SKY} (*)${NC}" || mark=""
    
    choice=$(show_menu "СТАЛИН-3000 (v$CURRENT_VERSION)" \
        "1:управление сервисом Telemt" \
        "2:управление пользователями Telemt" \
        "3:настройки Telemt" \
        "4:управление Zapret (TPWS)" \
        "5:обслуживание менеджера$mark" \
        "0:выход")

    case $choice in
        1) sub_service ;;
        2) sub_users ;;
        3) # Настройки
           clear; if [ ! -f "$CONF_FILE" ]; then 
                show_menu "НАСТРОЙКИ TELEMT" "0:назад" > /dev/null
                msg_err "Telemt не установлен."
                ask_text "нажмите [0]"
           else
                # Тело настроек (для экономии пока прямо здесь)
                while true; do
                    case $(show_menu "НАСТРОЙКИ TELEMT" "1:логи (journalctl)" "2:сменить порт" "0:назад") in
                        1) printf "\n"; tput cnorm; journalctl -u telemt -n 50 --no-pager; tput civis; ask_text "нажмите [Enter]";;
                        2) printf "\n"; np=$(ask_text "новый порт"); sed -i "s/^port = .*/port = $np/" $CONF_FILE && systemctl restart telemt;;
                        0) break ;;
                    esac
                done
           fi; clear ;;
        4) sub_zapret ;;
        5) # Обслуживание
           clear; while true; do
             case $(show_menu "ОБСЛУЖИВАНИЕ" "1:обновить менеджер" "2:полная очистка системы" "0:назад") in
                1) printf "\n"; msg_step "Обновление" "curl -sSL -f $REPO_URL -o $CLI_NAME && chmod +x $CLI_NAME"; tput cnorm; exec "$CLI_NAME" ;;
                2) printf "\n"; if ask_confirm "ПОЛНАЯ ОЧИСТКА?"; then
                     systemctl stop telemt zapret-tpws 2>/dev/null
                     rm -rf $CONF_DIR $BIN_PATH $SERVICE_FILE $Z_DIR $Z_SERVICE
                     rm -f "$CLI_NAME"
                     clear; tput cnorm; echo "Система очищена. Выход."; exit 0
                   fi; break ;;
                0) break ;;
             esac
           done; clear ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
