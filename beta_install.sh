#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.5.1"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

# === color grade ===
BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m'
ORANGE='\033[1;38;5;214m'
SKY_BLUE='\033[1;38;5;81m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'

# === strings ===
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_LABEL="cтатус Telemt:"
L_STATUS_RUN="работает"
L_STATUS_STOP="остановлен"
L_STATUS_NONE="не установлен"

L_MAIN_1="управление сервисом"
L_MAIN_2="управление пользователями"
L_MAIN_3="настройки Telemt"
L_MAIN_4="IP-IP туннели для XRAY"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

L_PROMPT_BACK="назад"
L_MSG_WAIT_ENTER="       нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED="       ошибка: сервис еще не установлен!"

# path
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"

# Tunnel Paths
TUN_NAME="tun0"
TUN_RUN_SCRIPT="/usr/local/bin/ipip-run.sh"
TUN_SERVICE="/etc/systemd/system/ipip-tunnel.service"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}ошибка, запустите скрипт с root правами!${NC}"; exit 1; fi

# --- base functions ---

wait_user() {
    printf "\n${ORANGE}${BOLD}$L_MSG_WAIT_ENTER${NC}"
    read -r
}

run_step() {
    local msg="$1"
    local cmd="$2"
    printf "  ${BOLD}${SKY_BLUE}*${NC} %-35s " "$msg..."
    if eval "$cmd" > /dev/null 2>&1; then
        printf "${GREEN}[готово]${NC}\n"
    else
        printf "${RED}[ошибка!]${NC}\n"
        return 1
    fi
}

check_updates() {
    REMOTE_VER=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then
        UPDATE_INFO=" \033[1;33m(новая версия v$REMOTE_VER)\033[0m"
    else
        UPDATE_INFO=""
    fi
}

get_user_list() {
    if [ -f "$CONF_FILE" ]; then
        sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u
    fi
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${SKY_BLUE}       ключи подключения для пользователя $target_user:${NC}"
    sleep 1.5
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}ключи подключения не найдены, проверьте статус сервиса${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
            elif [[ $link == *"server=::"* ]]; then [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
            else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi
        done
    fi
}

# --- Telemt installation ---

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка и установка Telemt${NC}"
    read -p "$(echo -e $SKY_BLUE"  укажите порт для Telemt ${MAIN_COLOR}(по умолчанию 443): "$NC)" P_PORT; P_PORT=${P_PORT:-443}
    read -p "$(echo -e $SKY_BLUE"  укажите SNI для TLS ${MAIN_COLOR}(например, google.com): "$NC)" P_SNI; P_SNI=${P_SNI:-google.com}
    
    while true; do
        read -p "$(echo -e $SKY_BLUE"  введите имя пользователя: "$NC)" P_USER; P_USER=${P_USER:-admin}
        if [[ "$P_USER" =~ ^[a-zA-Z0-9]+$ ]]; then break
        else echo -e "      ${RED}ошибка: только латиница и цифры!${NC}"; fi
    done

    read -p "$(echo -e $SKY_BLUE"  лимит IP ${MAIN_COLOR}(0 - без лимита): "$NC)" P_LIM; P_LIM=${P_LIM:-0}
    
    run_step "установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    run_step "загрузка бинарных файлов" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    
    CMD_CONF="useradd -d /opt/telemt -m -r -U telemt 2>/dev/null || true; mkdir -p $CONF_DIR; 
    cat <<EOF > $CONF_FILE
[general]
use_middle_proxy = false
[general.modes]
classic = false
secure = false
tls = true
[server]
port = $P_PORT
[server.api]
enabled = true
listen = \"127.0.0.1:9091\"
[censorship]
tls_domain = \"$P_SNI\"
[access.user_max_unique_ips]
$P_USER = $P_LIM
[access.users]
$P_USER = \"\$(openssl rand -hex 16)\"
EOF
    chown -R telemt:telemt $CONF_DIR"
    run_step "создание конфига" "$CMD_CONF"
    
    CMD_SRV="cat <<EOF > $SERVICE_FILE
[Unit]
Description=Telemt Proxy
After=network-online.target
[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=$BIN_PATH $CONF_FILE
Restart=on-failure
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF"
    run_step "настройка службы" "$CMD_SRV"
    run_step "запуск Telemt" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    echo -e "\n${BOLD}${GREEN}  установка завершена успешно!${NC}"
    show_links "$P_USER"
}

cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE}    удаляем компоненты Telemt...${NC}"
    # Проверяем, существует ли сервис, прежде чем его стопать
    if systemctl list-unit-files | grep -q "telemt.service"; then
        run_step "остановка службы" "systemctl stop telemt 2>/dev/null || true"
        run_step "отключение автозагрузки" "systemctl disable telemt 2>/dev/null || true"
    fi
    
    run_step "удаление бинарных файлов" "rm -f $BIN_PATH"
    run_step "удаление файлов конфигураций" "rm -rf $CONF_DIR"
    run_step "удаление системных файлов" "rm -rf /opt/telemt"
    run_step "удаление системного юнита" "rm -f $SERVICE_FILE"
    
    # Удаляем пользователя только если он есть
    if id "telemt" &>/dev/null; then
        run_step "удаление пользователей" "userdel telemt 2>/dev/null || true"
    fi
    
    run_step "перезагрузка демонов" "systemctl daemon-reload"
    echo -e "   ${GREEN}${BOLD}Telemt успешно удалён${NC}" # Ровно 3 пробела
}

# --- IPIP TUNNEL LOGIC ---

cleanup_tunnel() {
    echo -e "\n${BOLD}${SKY_BLUE}    удаляем компоненты туннеля...${NC}"
    if systemctl list-unit-files | grep -q "ipip-tunnel.service"; then
        run_step "остановка службы туннеля" "systemctl stop ipip-tunnel 2>/dev/null || true"
        run_step "отключение автозагрузки" "systemctl disable ipip-tunnel 2>/dev/null || true"
    fi
    
    # Удаляем интерфейс только если он существует
    if [ -d "/sys/class/net/$TUN_NAME" ]; then
        run_step "удаление интерфейса $TUN_NAME" "ip link delete $TUN_NAME 2>/dev/null || true"
    fi
    
    # Очистка маршрутов без паники
    run_step "очистка правил маршрутизации" "ip rule del from 10.200.200.1 table 200 2>/dev/null || true; ip route flush table 200 2>/dev/null || true"
    
    run_step "удаление файлов" "rm -f $TUN_RUN_SCRIPT $TUN_SERVICE"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
    echo -e "   ${GREEN}${BOLD}туннель успешно удалён${NC}" # Ровно 3 пробела
}

setup_tunnel() {
    local mode=$1
    printf "\n${BOLD}${YELLOW}настройка туннеля${NC}\n"

    # Валидация тега
    while true; do
        echo -ne "  задайте тег для подключения: "
        read t_note
        if [[ "$t_note" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            echo -e "  ${RED}ошибка: используйте только латиницу и цифры${NC}"
        fi
    done

    echo -ne "  ID (0-20): "
    read tun_id
    tun_id=${tun_id:-0}

    # Имя интерфейса теперь тоже привязано к тегу для наглядности в ip
    local T_NAME="ipip-$t_note"
    local T_SERVICE="ipip-$t_note.service"
    local T_SCRIPT="/usr/local/bin/ipip-run-$t_note.sh"

    if [[ "$mode" == "russia" ]]; then
        local MY_TUN_IP="10.200.$tun_id.1"
        local r_msg="публичный IP выходного сервера: "
    else
        local MY_TUN_IP="10.200.$tun_id.2"
        local r_msg="публичный IP входного сервера: "
    fi

    local LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+')
    echo -e "  ваш IP: ${SKY_BLUE}$LOCAL_IP${NC}"
    
    echo -ne "  $r_msg"
    read REMOTE_IP
    [[ -z "$REMOTE_IP" ]] && return

    cat <<EOF > $T_SCRIPT
#!/bin/bash
# REMOTE_IP: $REMOTE_IP
# TAG: $t_note
# TUN_ID: $tun_id
ip link delete $T_NAME 2>/dev/null
ip tunnel add $T_NAME mode ipip remote $REMOTE_IP local $LOCAL_IP ttl 255
ip addr add $MY_TUN_IP/30 dev $T_NAME
ip link set $T_NAME up
TABLE_ID=$((200 + tun_id))
ip rule del from $MY_TUN_IP table \$TABLE_ID 2>/dev/null
ip rule add from $MY_TUN_IP table \$TABLE_ID
ip route add default dev $T_NAME table \$TABLE_ID
EOF
    chmod +x $T_SCRIPT

    cat <<EOF > /etc/systemd/system/$T_SERVICE
[Unit]
Description=IPIP Tunnel [$t_note]
After=network.target

[Service]
Type=oneshot
ExecStart=$T_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload && systemctl enable --now "$T_SERVICE" &>/dev/null
    echo -e "  ${GREEN}готово${NC}"
}

# --- SUBMENUS ---

submenu_service() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         УПРАВЛЕНИЕ   СЕРВИСОМ          ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}перезапустить Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_telemt; wait_user ;;
            2) [ -f "$SERVICE_FILE" ] && systemctl restart telemt && echo -e "${GREEN}  Telemt перезапущен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            3) [ -f "$SERVICE_FILE" ] && systemctl stop telemt && echo -e "${YELLOW}  Telemt остановлен${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_users() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║        УПРАВЛЕНИЕ  ПОЛЬЗОВАТЕЛЯМИ      ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}список пользователей и ссылки${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}добавить пользователя${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удаление пользователей${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}настроить лимит IP${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}║          СПИСОК  ПОЛЬЗОВАТЕЛЕЙ         ║${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
                read -p "$(echo -e $ORANGE"       введите номер: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    show_links "${USERS[$((U_IDX-1))]}"; wait_user
                fi
            done ;;
            2) read -p "$(echo -e $ORANGE"       имя нового пользователя: "$NC)" UNAME
               if [[ "$UNAME" =~ ^[a-zA-Z0-9]+$ ]]; then
                    read -p "$(echo -e $ORANGE"       лимит IP (0 - без лимита): "$NC)" ULIM; ULIM=${ULIM:-0}
                    U_SEC=$(openssl rand -hex 16)
                    sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
                    echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}       добавлен${NC}"; wait_user
               fi ;;
            3) mapfile -t USERS < <(get_user_list)
               echo -e "Выберите номер для удаления:"; for i in "${!USERS[@]}"; do echo "$((i+1))) ${USERS[$i]}"; done
               read -p "Номер: " U_IDX
               if [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                   DEL_NAME="${USERS[$((U_IDX-1))]}"; sed -i "/^$DEL_NAME =/d" $CONF_FILE; systemctl restart telemt; echo "Удален"; wait_user
               fi ;;
            0) break ;;
        esac
    done
}

submenu_settings() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║           НАСТРОЙКИ   TELEMT           ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}системный лог${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}изменить порт${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}изменить SNI домен${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) journalctl -u telemt -n 50; wait_user ;;
            2) read -p "Новый порт: " N_PORT; sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && systemctl restart telemt; wait_user ;;
            3) read -p "Новый SNI: " N_SNI; sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_tunnel() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         IP-IP ТУННЕЛИ ДЛЯ XRAY         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        
        local found=0
        for script in /usr/local/bin/ipip-run-*.sh; do
            if [ -f "$script" ]; then
                local tag=$(grep "TAG:" "$script" | awk '{print $3}')
                local r_ip=$(grep "REMOTE_IP:" "$script" | awk '{print $3}')
                local iface="ipip-$tag"
                
                # Проверяем, поднят ли конкретно этот интерфейс
                if [ -d "/sys/class/net/$iface" ]; then
                    local p_stat="${GREEN}up${NC}"
                else
                    local p_stat="${RED}down${NC}"
                fi
                
                printf "  [ %-10s | %-15s | %b ]\n" "$tag" "$r_ip" "$p_stat"
                found=1
            fi
        done
        
        [[ $found -eq 0 ]] && printf "          ${GRAY}(активных туннелей нет)${NC}\n"
        echo ""

        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить на входной сервер${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}установить на выходной сервер${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удалить туннель${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}проверить скорость${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
        
        echo ""
        read -p "$(echo -e $ORANGE"  выберите действие: "$NC)" tchoice
        case $tchoice in
            1) setup_tunnel "russia"; wait_user ;;
            2) setup_tunnel "europe"; wait_user ;;
            3) 
                echo -ne "  введите тег для удаления: "
                read del_note
                local del_iface="ipip-$del_note"
                if [ -f "/etc/systemd/system/ipip-$del_note.service" ]; then
                    systemctl disable --now "ipip-$del_note.service" &>/dev/null
                    rm -f "/etc/systemd/system/ipip-$del_note.service" "/usr/local/bin/ipip-run-$del_note.sh"
                    ip link delete "$del_iface" 2>/dev/null
                    echo -e "  ${GREEN}удалено${NC}"
                else
                    echo -e "  ${RED}не найдено${NC}"
                fi
                wait_user ;;
            4) 
                echo -ne "  тег для теста: "
                read s_note
                local s_iface="ipip-$s_note"
                if [ -d "/sys/class/net/$s_iface" ]; then
                    local s_ip=$(ip addr show "$s_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
                    echo -e "  ${SKY_BLUE}тест через $s_iface...${NC}"
                    SPEED_BPS=$(curl -o /dev/null -s --max-time 30 -w "%{speed_download}" --interface "$s_ip" http://speedtest.tele2.net/500MB.zip)
                    SPEED_MBPS=$(awk "BEGIN {printf \"%.2f\", ($SPEED_BPS * 8) / 1048576}")
                    echo -e "  ${GREEN}результат: ~ $SPEED_MBPS Мбит/с${NC}"
                else
                    echo -e "  ${RED}интерфейс не найден${NC}"
                fi
                wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        check_updates
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}обновить менеджер${UPDATE_INFO}${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}удалить сервис Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}полная очистка${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        
        echo -ne "       ${ORANGE}выберите действие: ${NC}"
        read subchoice
        
        case "$subchoice" in
            1) 
               if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
                   chmod +x "$CLI_NAME"
                   echo -e "       ${GREEN}Обновлено!${NC}"
                   sleep 1; exec "$CLI_NAME"
               fi 
               ;;
            2) 
               echo -ne "       ${ORANGE}Удалить Telemt? (y/n): ${NC}"
               read confirm
               confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
               if [[ "$confirm" == "y" ]]; then
                   cleanup_proxy
                   wait_user
               fi 
               ;;
            3) 
               echo -ne "       ${ORANGE}Удалить ВСЁ? (y/n): ${NC}"
               read confirm
               confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
               if [[ "$confirm" == "y" ]]; then
                   cleanup_proxy
                   cleanup_tunnel
                   run_step "удаление менеджера" "rm -f $CLI_NAME"
                   echo -e "\n   ${GREEN}${BOLD}Очистка завершена. Выход...${NC}"
                   exit 0
               fi 
               ;;
            0) 
               break 
               ;;
            *) 
               continue 
               ;;
        esac
    done
}

# --- main cycle ---
while true; do
    check_updates
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║           %s (v%s)         ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi
    printf "  %s %b\n" "      $L_STATUS_LABEL" "$STATUS"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}$L_MAIN_5${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    read -p "$(echo -e $ORANGE"       выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_settings ;;
        4) submenu_tunnel ;;
        5) submenu_manager ;;
        0) exit 0 ;;
        *) sleep 0.1 ;;
    esac
done
