#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.4.6"
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
}

setup_tunnel() {
    local mode=$1
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка IPIP туннеля ($mode)${NC}"
    LOCAL_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
    MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
    echo -e "  ${SKY_BLUE}Ваш локальный IP:${NC} $LOCAL_IP"
    read -p "$(echo -e $ORANGE"  введите ПУБЛИЧНЫЙ IP удаленного сервера: "$NC)" REMOTE_IP
    if [ -z "$REMOTE_IP" ]; then echo -e "${RED}ошибка: IP пуст!${NC}"; return; fi

    if [ "$mode" == "europe" ]; then
        cat <<EOF > $TUN_RUN_SCRIPT
#!/bin/bash
ip link delete $TUN_NAME 2>/dev/null
ip tunnel add $TUN_NAME mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 255
ip link set dev $TUN_NAME mtu 1400
ip addr add 10.200.200.2/30 dev $TUN_NAME
ip link set dev $TUN_NAME up
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -D POSTROUTING -s 10.200.200.0/30 -o $MAIN_IF -j MASQUERADE 2>/dev/null
iptables -t nat -A POSTROUTING -s 10.200.200.0/30 -o $MAIN_IF -j MASQUERADE
iptables -A FORWARD -i $TUN_NAME -j ACCEPT
iptables -A FORWARD -o $TUN_NAME -j ACCEPT
EOF
    else
        cat <<EOF > $TUN_RUN_SCRIPT
#!/bin/bash
ip link delete $TUN_NAME 2>/dev/null
ip tunnel add $TUN_NAME mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 255
ip link set dev $TUN_NAME mtu 1400
ip addr add 10.200.200.1/30 dev $TUN_NAME
ip link set dev $TUN_NAME up
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.$TUN_NAME.rp_filter=0
ip rule del from 10.200.200.1 table 200 2>/dev/null
ip route flush table 200 2>/dev/null
ip route add default via 10.200.200.2 dev $TUN_NAME table 200
ip rule add from 10.200.200.1 table 200
EOF
    fi
    chmod +x $TUN_RUN_SCRIPT
    cat <<EOF > $TUN_SERVICE
[Unit]
Description=IPIP Tunnel Service
After=network-online.target
[Service]
Type=oneshot
ExecStart=$TUN_RUN_SCRIPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    run_step "запуск службы туннеля" "systemctl daemon-reload && systemctl enable ipip-tunnel && systemctl restart ipip-tunnel"
    echo -e "\n${BOLD}${GREEN}  Туннель поднят!${NC}"
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
        printf "${BOLD}${MAIN_COLOR}║          IP-IP ТУННЕЛИ ДЛЯ XRAY        ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        
        if [ -d "/sys/class/net/$TUN_NAME" ]; then
            T_STATUS_STR="${BOLD}${GREEN}активен${NC}"
            MY_TUN_IP=$(ip addr show $TUN_NAME 2>/dev/null | grep -oP 'inet \K[\d.]+')
            [[ "$MY_TUN_IP" == "10.200.200.1" ]] && TARGET="10.200.200.2" || TARGET="10.200.200.1"
            PING_RES=$(ping -c 1 -W 1 $TARGET 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)
            if [ -z "$PING_RES" ]; then
                LNK_STR="${BOLD}${RED}обрыв${NC}"
                PNG_STR="${RED}---${NC}"
            else
                LNK_STR="${BOLD}${GREEN}есть${NC}"
                INT_PING=${PING_RES%.*}
                if [ "$INT_PING" -lt 50 ]; then PNG_STR="${GREEN}${PING_RES} ms${NC}"
                elif [ "$INT_PING" -lt 100 ]; then PNG_STR="${YELLOW}${PING_RES} ms${NC}"
                else PNG_STR="${RED}${PING_RES} ms${NC}"; fi
            fi
        else
            T_STATUS_STR="${BOLD}${RED}не установлен${NC}"
            LNK_STR="${RED}нет${NC}"
            PNG_STR="${RED}---${NC}"
        fi

        printf "          статус IP-IP: %b\n" "$T_STATUS_STR"
        printf "          линк: %b\n" "$LNK_STR"
        printf "          пинг: %b\n" "$PNG_STR"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить на входной сервер${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}установить на выходной сервер${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удалить туннель${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}проверить скорость (500MB тест)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" tchoice
        case $tchoice in
            1) setup_tunnel "russia"; wait_user ;;
            2) setup_tunnel "europe"; wait_user ;;
            3) 
               if [ ! -d "/sys/class/net/$TUN_NAME" ]; then
                   echo -e "       ${RED}ошибка: туннель еще не установлен!${NC}"
               else
                   read -p "$(echo -e $ORANGE"       удалить туннель? (y/n): "$NC)" confirm
                   if [[ "$confirm" == "y" ]]; then
                       cleanup_tunnel
                   else
                       echo -e "       ${SKY_BLUE}отмена удаления${NC}"
                   fi
               fi
               wait_user ;;
            4) 
               if [ ! -d "/sys/class/net/$TUN_NAME" ]; then 
                   echo -e "       ${RED}ошибка: туннель не поднят!${NC}"[cite: 2]
               else
                   echo -e "       ${SKY_BLUE}тестируем скорость через туннель...${NC}"[cite: 2]
                   echo -e "       ${ORANGE}(загрузка 500MB, подождите)${NC}"[cite: 2]
                   SPEED_BPS=$(curl -o /dev/null -s --max-time 30 -w "%{speed_download}" --interface $MY_TUN_IP http://speedtest.tele2.net/500MB.zip)[cite: 2]
                   if [[ -z "$SPEED_BPS" || "$SPEED_BPS" == "0" || "$SPEED_BPS" == "0.000" ]]; then
                       echo -e "       ${RED}ошибка: не удалось провести замер${NC}"[cite: 2]
                   else
                       SPEED_MBPS=$(awk "BEGIN {printf \"%.2f\", ($SPEED_BPS * 8) / 1048576}")[cite: 2]
                       echo -e "       ${GREEN}результат: ~ $SPEED_MBPS Мбит/с${NC}"[cite: 2]
                   fi
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
        
        case $subchoice in
            1) 
               if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
                   chmod +x "$CLI_NAME"
                   echo -e "       ${GREEN}Обновлено!${NC}"
                   sleep 1; exec "$CLI_NAME"
               fi ;;
            2) 
               echo -ne "       ${ORANGE}Удалить Telemt? (y/n): ${NC}"
               read confirm
               # Переводим в нижний регистр для надежности
               confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
               if [[ "$confirm" == "y" ]]; then
                   cleanup_proxy
                   wait_user
               fi ;;
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
               fi ;;
            0) break ;;
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
