#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.4.2-MAXIMUS"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

# === color grade ===
BOLD=$(tput bold)
NC='\033[0m' 
MAIN_COLOR='\033[38;5;148m'   # yellow-green
ORANGE='\033[1;38;5;214m'     # orange 
SKY_BLUE='\033[1;38;5;81m'    # blue
GREEN='\033[1;32m'            # green
RED='\033[1;31m'              # red
YELLOW='\033[1;33m'           # yellow

# === path config ===
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
SHORTCUT_PATH="/usr/local/bin/stln"

# Tunnel Paths
TUN_NAME="tun0"
TUN_RUN_SCRIPT="/usr/local/bin/ipip-run.sh"
TUN_SERVICE="/etc/systemd/system/ipip-tunnel.service"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}ошибка: нужны права root!${NC}"; exit 1; fi

# --- core functions ---

create_shortcut() {
    # Силовой метод прописки симлинка
    local current_script=$(readlink -f "$0")
    if [ "$current_script" != "$SHORTCUT_PATH" ]; then
        ln -sf "$current_script" "$SHORTCUT_PATH"
        chmod +x "$SHORTCUT_PATH"
        # Также обновляем основной файл менеджера
        cp "$current_script" "$CLI_NAME" 2>/dev/null
        chmod +x "$CLI_NAME" 2>/dev/null
    fi
}

wait_user() {
    printf "\n${ORANGE}${BOLD}       нажмите [Enter] для продолжения...${NC}"
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

get_user_list() {
    if [ -f "$CONF_FILE" ]; then
        sed -n '/\[access.users\]/,$p' "$CONF_FILE" | grep "=" | grep -v "\[" | awk '{print $1}' | sort -u
    fi
}

show_links() {
    local target_user="$1"
    [ -z "$target_user" ] && return
    echo -e "\n${BOLD}${SKY_BLUE}       ключи для $target_user:${NC}"
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "YOUR_IP")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${RED}       ошибка: ключи не найдены. проверьте статус сервиса!${NC}"
    else
        for link in $LINKS; do
            echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
        done
    fi
}

# --- menus ---

submenu_tunnel() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║          IP-IP ТУННЕЛИ ДЛЯ XRAY        ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        
        if [ -d "/sys/class/net/$TUN_NAME" ]; then
            T_STAT="${GREEN}активен${NC}"
            MY_TUN_IP=$(ip addr show $TUN_NAME 2>/dev/null | grep -oP 'inet \K[\d.]+')
            [[ "$MY_TUN_IP" == "10.200.200.1" ]] && TARGET="10.200.200.2" || TARGET="10.200.200.1"
            P_VAL=$(ping -c 1 -W 1 $TARGET 2>/dev/null | grep -oP 'time=\K[\d.]+')
            [ -z "$P_VAL" ] && L_STAT="${RED}обрыв${NC}" || L_STAT="${GREEN}есть (${P_VAL}ms)${NC}"
        else
            T_STAT="${RED}не установлен${NC}"; L_STAT="${RED}нет${NC}"
        fi

        printf "      статус IP-IP: %b\n" "$T_STAT"
        printf "      линк: %b\n\n" "$L_STAT"
        
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить (ВХОД / РФ)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}установить (ВЫХОД / ЕВРО)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}удалить туннель${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}проверить скорость (500MB тест)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
        
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" tchoice
        case $tchoice in
            1) 
                LOCAL_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
                read -p "      IP удаленного сервера: " REMOTE_IP
                cat <<EOF > $TUN_RUN_SCRIPT
#!/bin/bash
ip tunnel add $TUN_NAME mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 255
ip addr add 10.200.200.1/30 dev $TUN_NAME
ip link set $TUN_NAME mtu 1400 up
ip route add default via 10.200.200.2 dev $TUN_NAME table 200
ip rule add from 10.200.200.1 table 200
EOF
                chmod +x $TUN_RUN_SCRIPT
                cat <<EOF > $TUN_SERVICE
[Unit]
Description=IPIP Tunnel
After=network.target
[Service]
Type=oneshot
ExecStart=$TUN_RUN_SCRIPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
                run_step "запуск туннеля" "systemctl daemon-reload && systemctl enable ipip-tunnel && systemctl restart ipip-tunnel"
                wait_user ;;
            2) 
                LOCAL_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
                MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
                read -p "      IP удаленного сервера: " REMOTE_IP
                cat <<EOF > $TUN_RUN_SCRIPT
#!/bin/bash
ip tunnel add $TUN_NAME mode ipip local $LOCAL_IP remote $REMOTE_IP ttl 255
ip addr add 10.200.200.2/30 dev $TUN_NAME
ip link set $TUN_NAME mtu 1400 up
iptables -t nat -A POSTROUTING -s 10.200.200.0/30 -o $MAIN_IF -j MASQUERADE
EOF
                chmod +x $TUN_RUN_SCRIPT
                cat <<EOF > $TUN_SERVICE
[Unit]
Description=IPIP Tunnel
After=network.target
[Service]
Type=oneshot
ExecStart=$TUN_RUN_SCRIPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
                run_step "запуск туннеля" "systemctl daemon-reload && systemctl enable ipip-tunnel && systemctl restart ipip-tunnel"
                wait_user ;;
            3) run_step "удаление" "systemctl stop ipip-tunnel; systemctl disable ipip-tunnel; ip link delete $TUN_NAME; rm -f $TUN_RUN_SCRIPT $TUN_SERVICE"; wait_user ;;
            4) 
                if [ ! -d "/sys/class/net/$TUN_NAME" ]; then echo -e "      ${RED}ошибка: туннель не поднят!${NC}"; wait_user; continue; fi
                echo -e "       ${SKY_BLUE}тестируем скорость...${NC}"
                SPEED=$(curl -o /dev/null -s -w "%{speed_download}" --interface $MY_TUN_IP http://cachefly.cachefly.net/500mb.test)
                MBPS=$(echo "scale=2; $SPEED * 8 / 1048576" | bc)
                echo -e "       ${GREEN}результат: ~ $MBPS Мбит/с${NC}"; wait_user ;;
            0) break ;;
        esac
    done
}

# --- main cycle ---

create_shortcut

while true; do
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║           СТАЛИН-3000 (v%s)        ║${NC}\n" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${RED}не установлен${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${GREEN}работает${NC}"
    else STATUS="${YELLOW}остановлен${NC}"; fi
    
    printf "      статус Telemt: %b\n\n" "$STATUS"
    
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}управление сервисом (Telemt)${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}пользователи и ссылки${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}IP-IP туннель${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}обновить менеджер${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}выход${NC}\n"
    
    read -p "$(echo -e $ORANGE"       выберите раздел: "$NC)" mchoice
    case $mchoice in
        1) 
            if [ -f "$SERVICE_FILE" ]; then
                echo -e "      ${SKY_BLUE}1 - перезапустить / 2 - остановить / 3 - удалить всё${NC}"
                read -p "      действие: " act
                [[ "$act" == "1" ]] && systemctl restart telemt
                [[ "$act" == "2" ]] && systemctl stop telemt
                [[ "$act" == "3" ]] && { systemctl stop telemt; rm -f $BIN_PATH $CONF_FILE $SERVICE_FILE; }
            else
                echo -e "\n${BOLD}${MAIN_COLOR}  установка Telemt${NC}"
                read -p "  порт (443): " P_PORT; P_PORT=${P_PORT:-443}
                read -p "  SNI (google.com): " P_SNI; P_SNI=${P_SNI:-google.com}
                read -p "  имя юзера: " P_USER; P_USER=${P_USER:-admin}
                run_step "установка пакетов" "apt-get update -qq && apt-get install -y curl jq tar openssl bc -qq"
                ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
                run_step "загрузка" "curl -L '$URL' | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
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
After=network.target
[Service]
ExecStart=$BIN_PATH $CONF_FILE
Restart=always
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target
EOF
                run_step "запуск" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                show_links "$P_USER"
            fi
            wait_user ;;
        2) 
            mapfile -t USERS < <(get_user_list)
            if [ ${#USERS[@]} -eq 0 ]; then echo -e "      ${RED}юзеров нет${NC}"; else
                for i in "${!USERS[@]}"; do printf "      %d) %s\n" "$((i+1))" "${USERS[$i]}"; done
                read -p "      номер: " u_idx
                [ -n "$u_idx" ] && show_links "${USERS[$((u_idx-1))]}"
            fi
            wait_user ;;
        3) submenu_tunnel ;;
        4) 
            echo -e "      ${SKY_BLUE}обновляюсь...${NC}"
            curl -sSL "$REPO_URL?v=$(date +%s)" -o "$CLI_NAME" && chmod +x "$CLI_NAME"
            exec "$CLI_NAME" ;;
        0) exit 0 ;;
    esac
done
