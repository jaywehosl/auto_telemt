#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.4.0-IPIP"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"[cite: 1]

# === color grade ===
BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m'   # yellow-green
ORANGE='\033[1;38;5;214m'     # orange 
SKY_BLUE='\033[1;38;5;81m'    # blue
GREEN='\033[1;32m'            # green
RED='\033[1;31m'              # red
YELLOW='\033[1;33m'           # yellow

# === strings ===
L_MENU_HEADER="СТАЛИН-3000"[cite: 1]
L_STATUS_LABEL="cтатус Telemt:"[cite: 1]
L_STATUS_RUN="работает"[cite: 1]
L_STATUS_STOP="остановлен"[cite: 1]
L_STATUS_NONE="не установлен"[cite: 1]

L_MAIN_1="управление сервисом"[cite: 1]
L_MAIN_2="управление пользователями"[cite: 1]
L_MAIN_3="настройки Telemt"[cite: 1]
L_MAIN_4="IP-IP туннели для XRAY"[cite: 1]
L_MAIN_5="обслуживание менеджера"[cite: 1]
L_MAIN_0="выход"[cite: 1]

L_PROMPT_BACK="назад"[cite: 1]
L_MSG_WAIT_ENTER="       нажмите [Enter] для продолжения..."[cite: 1]
L_ERR_NOT_INSTALLED="       ошибка: сервис еще не установлен!"[cite: 1]

# path
BIN_PATH="/bin/telemt"[cite: 1]
CONF_DIR="/etc/telemt"[cite: 1]
CONF_FILE="$CONF_DIR/telemt.toml"[cite: 1]
SERVICE_FILE="/etc/systemd/system/telemt.service"[cite: 1]
CLI_NAME="/usr/local/bin/telemt"[cite: 1]
SHORTCUT_PATH="/usr/local/bin/stln"

# Tunnel Paths
TUN_NAME="tun0"[cite: 1]
TUN_RUN_SCRIPT="/usr/local/bin/ipip-run.sh"[cite: 1]
TUN_SERVICE="/etc/systemd/system/ipip-tunnel.service"[cite: 1]

if [ "$EUID" -ne 0 ]; then echo -e "${RED}ошибка, запустите скрипт с root правами!${NC}"; exit 1; fi[cite: 1]

# --- base functions ---

create_shortcut() {
    local current_script=$(readlink -f "$0")
    if [ "$current_script" != "$SHORTCUT_PATH" ]; then
        ln -sf "$current_script" "$SHORTCUT_PATH"
        chmod +x "$SHORTCUT_PATH"
    fi
}

wait_user() {
    printf "\n${ORANGE}${BOLD}$L_MSG_WAIT_ENTER${NC}"[cite: 1]
    read -r[cite: 1]
}

run_step() {
    local msg="$1"[cite: 1]
    local cmd="$2"[cite: 1]
    printf "  ${BOLD}${SKY_BLUE}*${NC} %-35s " "$msg..."[cite: 1]
    if eval "$cmd" > /dev/null 2>&1; then[cite: 1]
        printf "${GREEN}[готово]${NC}\n"[cite: 1]
    else
        printf "${RED}[ошибка!]${NC}\n"[cite: 1]
        return 1[cite: 1]
    fi
}

check_updates() {
    REMOTE_VER=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | cut -d'"' -f2 | head -n 1)[cite: 1]
    if [[ -n "$REMOTE_VER" && "$REMOTE_VER" != "$CURRENT_VERSION" ]]; then[cite: 1]
        UPDATE_INFO=" \033[1;33m(новая версия v$REMOTE_VER)\033[0m"[cite: 1]
    else
        UPDATE_INFO=""[cite: 1]
    fi
}

get_user_list() {
    if [ -f "$CONF_FILE" ]; then[cite: 1]
        sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | awk '{print $1}' | sort -u[cite: 1]
    fi
}

show_links() {
    local target_user="$1"[cite: 1]
    [ -z "$target_user" ] && return[cite: 1]
    echo -e "\n${BOLD}${SKY_BLUE}       ключи подключения для пользователя $target_user:${NC}"[cite: 1]
    sleep 1.5[cite: 1]
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")[cite: 1]
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")[cite: 1]
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)[cite: 1]
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then[cite: 1]
        echo -e "${YELLOW}ключи подключения не найдены, проверьте статус сервиса${NC}"[cite: 1]
    else
        for link in $LINKS; do[cite: 1]
            if [[ $link == *"server=0.0.0.0"* ]]; then [ -n "$IP4" ] && echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"[cite: 1]
            elif [[ $link == *"server=::"* ]]; then [ -n "$IP6" ] && echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"[cite: 1]
            else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi[cite: 1]
        done
    fi
}

# --- Telemt installation ---

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка и установка Telemt${NC}"[cite: 1]
    read -p "$(echo -e $SKY_BLUE"  укажите порт для Telemt ${MAIN_COLOR}(по умолчанию 443): "$NC)" P_PORT; P_PORT=${P_PORT:-443}[cite: 1]
    read -p "$(echo -e $SKY_BLUE"  укажите SNI для TLS ${MAIN_COLOR}(например, google.com): "$NC)" P_SNI; P_SNI=${P_SNI:-google.com}[cite: 1]
    
    while true; do
        read -p "$(echo -e $SKY_BLUE"  введите имя пользователя: "$NC)" P_USER; P_USER=${P_USER:-admin}[cite: 1]
        if [[ "$P_USER" =~ ^[a-zA-Z0-9]+$ ]]; then break[cite: 1]
        else echo -e "      ${RED}ошибка: только латиница и цифры!${NC}"; fi[cite: 1]
    done

    read -p "$(echo -e $SKY_BLUE"  лимит IP ${MAIN_COLOR}(0 - без лимита): "$NC)" P_LIM; P_LIM=${P_LIM:-0}[cite: 1]
    
    run_step "установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y curl jq tar openssl net-tools bc -qq"[cite: 1]
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)[cite: 1]
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"[cite: 1]
    run_step "загрузка бинарных файлов" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"[cite: 1]
    
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
    chown -R telemt:telemt $CONF_DIR"[cite: 1]
    run_step "создание конфига" "$CMD_CONF"[cite: 1]
    
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
EOF"[cite: 1]
    run_step "настройка службы" "$CMD_SRV"[cite: 1]
    run_step "запуск Telemt" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"[cite: 1]
    echo -e "\n${BOLD}${GREEN}  установка завершена успешно!${NC}"[cite: 1]
    show_links "$P_USER"[cite: 1]
}

cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE}    удаляем компоненты Telemt...${NC}"[cite: 1]
    run_step "остановка службы" "systemctl stop telemt 2>/dev/null"[cite: 1]
    run_step "отключение автозагрузки" "systemctl disable telemt 2>/dev/null"[cite: 1]
    run_step "удаление бинарных файлов" "rm -f $BIN_PATH"[cite: 1]
    run_step "удаление файлов конфигураций" "rm -rf $CONF_DIR"[cite: 1]
    run_step "удаление системных файлов" "rm -rf /opt/telemt"[cite: 1]
    run_step "удаление системного юнита" "rm -f $SERVICE_FILE"[cite: 1]
    run_step "удаление пользователей" "userdel telemt 2>/dev/null || true"[cite: 1]
    run_step "перезагрузка демонов" "systemctl daemon-reload"[cite: 1]
    echo -e "${GREEN}${BOLD}    Telemt успешно удалён${NC}"[cite: 1]
}

# --- IPIP TUNNEL LOGIC ---

cleanup_tunnel() {
    echo -e "\n${BOLD}${SKY_BLUE}    удаляем компоненты туннеля...${NC}"[cite: 1]
    run_step "остановка службы туннеля" "systemctl stop ipip-tunnel 2>/dev/null"[cite: 1]
    run_step "отключение автозагрузки" "systemctl disable ipip-tunnel 2>/dev/null"[cite: 1]
    run_step "удаление интерфейса $TUN_NAME" "ip link delete $TUN_NAME 2>/dev/null"[cite: 1]
    run_step "очистка правил маршрутизации" "ip rule del from 10.200.200.1 table 200 2>/dev/null; ip route flush table 200 2>/dev/null"[cite: 1]
    run_step "удаление файлов" "rm -f $TUN_RUN_SCRIPT $TUN_SERVICE"[cite: 1]
    run_step "перезагрузка демонов" "systemctl daemon-reload"[cite: 1]
    echo -e "${GREEN}${BOLD}    Туннель успешно удалён${NC}"[cite: 1]
}

setup_tunnel() {
    local mode=$1[cite: 1]
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка IPIP туннеля ($mode)${NC}"[cite: 1]
    LOCAL_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')[cite: 1]
    MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)[cite: 1]
    echo -e "  ${SKY_BLUE}Ваш локальный IP:${NC} $LOCAL_IP"[cite: 1]
    read -p "$(echo -e $ORANGE"  введите ПУБЛИЧНЫЙ IP удаленного сервера: "$NC)" REMOTE_IP[cite: 1]
    if [ -z "$REMOTE_IP" ]; then echo -e "${RED}ошибка: IP пуст!${NC}"; return; fi[cite: 1]

    if [ "$mode" == "europe" ]; then[cite: 1]
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
    chmod +x $TUN_RUN_SCRIPT[cite: 1]
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
    run_step "запуск службы туннеля" "systemctl daemon-reload && systemctl enable ipip-tunnel && systemctl restart ipip-tunnel"[cite: 1]
    echo -e "\n${BOLD}${GREEN}  Туннель поднят!${NC}"[cite: 1]
}

# --- SUBMENUS ---

submenu_service() {
    while true; do
        clear[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}║         УПРАВЛЕНИЕ   СЕРВИСОМ          ║${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить Telemt${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}перезапустить Telemt${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}остановить Telemt${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"[cite: 1]
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice[cite: 1]
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
        clear[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}║        УПРАВЛЕНИЕ  ПОЛЬЗОВАТЕЛЯМИ      ║${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}список пользователей и ссылки${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}добавить пользователя${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удаление пользователей${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}настроить лимит IP${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"[cite: 1]
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice[cite: 1]
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
        clear[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}║           НАСТРОЙКИ   TELEMT           ║${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
        if [ ! -f "$CONF_FILE" ]; then echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user; break; fi[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}системный лог${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}изменить порт${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}изменить SNI домен${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"[cite: 1]
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice[cite: 1]
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
        clear[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}║          IP-IP ТУННЕЛИ ДЛЯ XRAY        ║${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
        
        if [ -d "/sys/class/net/$TUN_NAME" ]; then[cite: 1]
            T_STATUS_STR="${BOLD}${GREEN}активен${NC}"[cite: 1]
            MY_TUN_IP=$(ip addr show $TUN_NAME 2>/dev/null | grep -oP 'inet \K[\d.]+')[cite: 1]
            [[ "$MY_TUN_IP" == "10.200.200.1" ]] && TARGET="10.200.200.2" || TARGET="10.200.200.1"[cite: 1]
            
            PING_RES=$(ping -c 1 -W 1 $TARGET 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | cut -d' ' -f1)[cite: 1]
            
            if [ -z "$PING_RES" ]; then[cite: 1]
                LNK_STR="${BOLD}${RED}обрыв${NC}"[cite: 1]
                PNG_STR="${RED}---${NC}"[cite: 1]
            else
                LNK_STR="${BOLD}${GREEN}есть${NC}"[cite: 1]
                INT_PING=${PING_RES%.*}[cite: 1]
                if [ "$INT_PING" -lt 50 ]; then PNG_STR="${GREEN}${PING_RES} ms${NC}"[cite: 1]
                elif [ "$INT_PING" -lt 100 ]; then PNG_STR="${YELLOW}${PING_RES} ms${NC}"[cite: 1]
                else PNG_STR="${RED}${PING_RES} ms${NC}"; fi[cite: 1]
            fi
        else
            T_STATUS_STR="${BOLD}${RED}не установлен${NC}"[cite: 1]
            LNK_STR="${RED}нет${NC}"[cite: 1]
            PNG_STR="${RED}---${NC}"[cite: 1]
        fi

        printf "      статус IP-IP: %b\n" "$T_STATUS_STR"[cite: 1]
        printf "      линк: %b\n" "$LNK_STR"[cite: 1]
        printf "      пинг: %b\n\n" "$PNG_STR"[cite: 1]
        
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить на входной сервер${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}установить на выходной сервер${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удалить туннель${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}проверить скорость (500MB тест)${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"[cite: 1]
        
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" tchoice[cite: 1]
        case $tchoice in
            1) setup_tunnel "russia"; wait_user ;;
            2) setup_tunnel "europe"; wait_user ;;
            3) cleanup_tunnel; wait_user ;;
            4) 
               if [ ! -d "/sys/class/net/$TUN_NAME" ]; then echo -e "${RED}       ошибка: туннель не поднят!${NC}"; wait_user; continue; fi[cite: 1]
               if ! command -v bc &> /dev/null; then apt-get install -y bc -qq &>/dev/null; fi[cite: 1]
               
               echo -e "       ${SKY_BLUE}тестируем скорость через туннель...${NC}"[cite: 1]
               echo -e "       ${ORANGE}(загрузка файла 500MB, подождите)${NC}"[cite: 1]
               
               SPEED_BPS=$(curl -o /dev/null -s -w "%{speed_download}" --interface $MY_TUN_IP http://cachefly.cachefly.net/500mb.test)[cite: 1]
               
               if [[ -z "$SPEED_BPS" || "$SPEED_BPS" == "0.000" ]]; then[cite: 1]
                   echo -e "       ${RED}ошибка: не удалось провести замер${NC}"[cite: 1]
               else
                   SPEED_MBPS=$(echo "scale=2; $SPEED_BPS * 8 / 1048576" | bc)[cite: 1]
                   echo -e "       ${GREEN}результат: ~ $SPEED_MBPS Мбит/с${NC}"[cite: 1]
               fi
               wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        check_updates[cite: 1]
        clear[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}║         ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА         ║${NC}\n"[cite: 1]
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}обновить менеджер${UPDATE_INFO}${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}удалить сервис Telemt${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}полная очистка${NC}\n"[cite: 1]
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"[cite: 1]
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice[cite: 1]
        case $subchoice in
            1) if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then[cite: 1]
               chmod +x "$CLI_NAME"; echo "Обновлено!"; sleep 1; exec "$CLI_NAME"; fi ;;[cite: 1]
            2) read -p "Удалить Telemt? (y/n): " confirm; [[ "$confirm" == "y" ]] && cleanup_proxy && wait_user ;;[cite: 1]
            3) read -p "Удалить ВСЁ? (y/n): " confirm; [[ "$confirm" == "y" ]] && cleanup_proxy && cleanup_tunnel && rm -f "$CLI_NAME" && rm -f "$SHORTCUT_PATH" && exit 0 ;;[cite: 1]
            0) break ;;
        esac
    done
}

# --- main cycle ---
create_shortcut
while true; do
    check_updates[cite: 1]
    clear[cite: 1]
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"[cite: 1]
    printf "${BOLD}${MAIN_COLOR}║           %s (v%s)         ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"[cite: 1]
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"[cite: 1]
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"[cite: 1]
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"[cite: 1]
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi[cite: 1]
    printf "  %s %b\n" "      $L_STATUS_LABEL" "$STATUS"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}$L_MAIN_5${NC}\n"[cite: 1]
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"[cite: 1]
    read -p "$(echo -e $ORANGE"       выберите раздел: "$NC)" mainchoice[cite: 1]
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
