#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.5.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

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
L_MENU_HEADER="СТАЛИН-3000"
L_STATUS_LABEL="cтатус Telemt:"
L_XSTATUS_LABEL="cтатус Xray:  "
L_STATUS_RUN="работает"
L_STATUS_STOP="остановлен"
L_STATUS_NONE="не установлен"

L_MAIN_1="управление Telemt (сервис)"
L_MAIN_2="управление пользователями Telemt"
L_MAIN_3="управление Xray (VLESS/Reality)"
L_MAIN_4="управление защитой (Firewall)"
L_MAIN_5="настройки Telemt"
L_MAIN_6="обслуживание менеджера"
L_MAIN_0="выход"

L_PROMPT_BACK="назад"
L_MSG_WAIT_ENTER="       нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED="       ошибка: сервис еще не установлен!"
# ==========================================================

# path
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"

X_BIN="/usr/local/bin/xray"
X_CONF_DIR="/usr/local/etc/xray"
X_CONF="$X_CONF_DIR/config.json"
X_SERVICE="/etc/systemd/system/xray.service"

CLI_NAME="/usr/local/bin/tmt"
BLOCK_SCRIPT="/usr/local/bin/block_leaseweb.sh"

if [ "$EUID" -ne 0 ]; then echo -e "${RED}ошибка, запустите скрипт с root правами!${NC}"; exit 1; fi

# --- functions ---

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
    sleep 2
    IP4=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 2 https://api64.ipify.org || echo "")
    LINKS=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target_user\") | .links.tls[]" 2>/dev/null)
    
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${YELLOW}ключи подключения не найдены, проверьте статус сервиса${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then
                if [ -n "$IP4" ]; then echo -e "${BOLD}${MAIN_COLOR}${link//0.0.0.0/$IP4}${NC}"
                else echo -e "${BOLD}${MAIN_COLOR}$link${NC}"; fi
            elif [[ $link == *"server=::"* ]]; then
                if [ -n "$IP6" ]; then echo -e "${BOLD}${MAIN_COLOR}${link//::/$IP6}${NC}"
                else continue; fi
            else
                echo -e "${BOLD}${MAIN_COLOR}$link${NC}"
            fi
        done
    fi
}

cleanup_proxy() {
    echo -e "\n${BOLD}${SKY_BLUE}    удаляем компоненты Telemt и защиты...${NC}"
    if ipset list leaseweb_v4 >/dev/null 2>&1; then
        run_step "очистка правил iptables" "iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null; iptables -D OUTPUT -m set --match-set leaseweb_v4 dst -j DROP 2>/dev/null; iptables -D FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP 2>/dev/null; ip6tables -D INPUT -m set --match-set leaseweb_v6 src -j DROP 2>/dev/null; ip6tables -D OUTPUT -m set --match-set leaseweb_v6 dst -j DROP 2>/dev/null; ip6tables -D FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP 2>/dev/null; netfilter-persistent save 2>/dev/null"
        run_step "удаление ipset баз" "systemctl disable ipset-persistent 2>/dev/null; rm -f /etc/systemd/system/ipset-persistent.service; ipset destroy leaseweb_v4 2>/dev/null; ipset destroy leaseweb_v6 2>/dev/null; rm -f /etc/ipset.conf"
        run_step "очистка задач cron" "crontab -l 2>/dev/null | grep -v 'block_leaseweb.sh' | crontab -"
        run_step "удаление скриптов защиты" "rm -f $BLOCK_SCRIPT"
    fi
    run_step "остановка службы" "systemctl stop telemt"
    run_step "отключение автозагрузки" "systemctl disable telemt"
    run_step "удаление бинарных файлов" "rm -f $BIN_PATH"
    run_step "удаление конфигураций" "rm -rf $CONF_DIR"
    run_step "удаление системных файлов" "rm -rf /opt/telemt"
    run_step "удаление системного юнита" "rm -f $SERVICE_FILE"
    run_step "удаление пользователей" "userdel telemt 2>/dev/null || true"
    run_step "перезагрузка демонов" "systemctl daemon-reload"
    echo -e "${GREEN}${BOLD}    очистка завершена успешно!${NC}"
}

# --- Xray logic ---

install_xray() {
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка и установка Xray (VLESS+Reality)${NC}"
    read -p "$(echo -e $SKY_BLUE"  укажите порт для Xray (напр. 443): "$NC)" X_PORT; X_PORT=${X_PORT:-443}
    read -p "$(echo -e $SKY_BLUE"  укажите домен маскировки (напр. google.com): "$NC)" X_DEST; X_DEST=${X_DEST:-google.com}
    
    run_step "установка зависимостей" "apt update -qq && apt install unzip curl uuid-runtime -y"
    
    # Определение архитектуры
    ARCH=$(uname -m)
    [[ "$ARCH" == "x86_64" ]] && XARCH="64" || XARCH="arm64-v8a"
    
    run_step "загрузка бинарника Xray" "curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$XARCH.zip && unzip -o /tmp/xray.zip -d /usr/local/bin/ xray && chmod +x $X_BIN"
    
    mkdir -p $X_CONF_DIR
    
    # Генерация ключей и UUID
    X_UUID=$($X_BIN uuid)
    X_KEYS=$($X_BIN x25519)
    X_PRIV=$(echo "$X_KEYS" | grep "Private key:" | awk '{print $3}')
    X_PUB=$(echo "$X_KEYS" | grep "Public key:" | awk '{print $3}')
    X_SID=$(openssl rand -hex 8)
    
    run_step "генерация конфигурации" "cat <<EOF > $X_CONF
{
    \"log\": {\"loglevel\": \"warning\"},
    \"inbounds\": [{
        \"port\": $X_PORT, \"protocol\": \"vless\",
        \"settings\": {
            \"clients\": [{\"id\": \"$X_UUID\", \"flow\": \"xtls-rprx-vision\"}],
            \"decryption\": \"none\"
        },
        \"streamSettings\": {
            \"network\": \"tcp\", \"security\": \"reality\",
            \"realitySettings\": {
                \"show\": false, \"dest\": \"$X_DEST:443\", \"xver\": 0,
                \"serverNames\": [\"$X_DEST\"],
                \"privateKey\": \"$X_PRIV\",
                \"shortIds\": [\"$X_SID\"]
            }
        }
    }],
    \"outbounds\": [{\"protocol\": \"freedom\"}]
}
EOF"

    run_step "создание службы systemd" "cat <<EOF > $X_SERVICE
[Unit]
Description=Xray Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$X_BIN run -config $X_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF"

    run_step "запуск Xray" "systemctl daemon-reload && systemctl enable xray && systemctl restart xray"
    
    echo -e "\n${GREEN}${BOLD}  Xray успешно установлен!${NC}"
    echo -e "  Public Key: ${YELLOW}$X_PUB${NC}"
    echo -e "  Short ID:   ${YELLOW}$X_SID${NC}"
    wait_user
}

show_xray_link() {
    if [ ! -f "$X_CONF" ]; then echo -e "${RED}Xray не настроен!${NC}"; return; fi
    IP=$(curl -s https://api.ipify.org)
    # Парсим данные из конфига
    PORT=$(jq -r '.inbounds[0].port' $X_CONF)
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $X_CONF)
    SNI=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' $X_CONF)
    PUB=$(echo "$($X_BIN x25519 -i "$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' $X_CONF)")" | grep "Public key:" | awk '{print $3}')
    SID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' $X_CONF)
    
    LINK="vless://$UUID@$IP:$PORT?security=reality&encryption=none&pbk=$PUB&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$SNI&sid=$SID#STALIN_XRAY"
    
    echo -e "\n${BOLD}${SKY_BLUE}       ключ подключения Xray (VLESS+Reality):${NC}"
    echo -e "${MAIN_COLOR}$LINK${NC}"
}

submenu_xray() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         УПРАВЛЕНИЕ   XRAY-CORE         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if systemctl is-active --quiet xray; then XSTAT="${GREEN}работает${NC}"; else XSTAT="${RED}не активен${NC}"; fi
        printf "  текущий статус: %b\n" "$XSTAT"
        printf "${MAIN_COLOR}------------------------------------------${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}установить Xray (Reality)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}показать ссылку подключения${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}перезапустить Xray${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}остановить Xray${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}удалить Xray полностью${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_xray ;;
            2) show_xray_link; wait_user ;;
            3) systemctl restart xray && echo "Ок"; wait_user ;;
            4) systemctl stop xray && echo "Стоп"; wait_user ;;
            5) read -p "Удалить Xray? (y/n): " confirm
               if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                   run_step "удаление Xray" "systemctl stop xray; systemctl disable xray; rm -f $X_BIN $X_SERVICE; rm -rf $X_CONF_DIR"
                   wait_user
               fi ;;
            0) break ;;
        esac
    done
}

# --- Остальные подразделы (без изменений в логике, только адаптация) ---

submenu_firewall() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         УПРАВЛЕНИЕ   ЗАЩИТОЙ           ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if ipset list leaseweb_v4 >/dev/null 2>&1; then FW_STAT="${GREEN}АКТИВНА${NC}"; COUNT=$(ipset list leaseweb_v4 2>/dev/null | grep -c '/'); else FW_STAT="${RED}ВЫКЛЮЧЕНА${NC}"; COUNT="0"; fi
        printf "  текущий статус: %b\n" "$FW_STAT"
        printf "  заблокировано подсетей: ${SKY_BLUE}%s${NC}\n" "$COUNT"
        printf "${MAIN_COLOR}------------------------------------------${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}включить 'Ядерный бан' (Leaseweb)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}выключить и удалить защиту${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) install_firewall; wait_user ;;
            2) remove_firewall; wait_user ;;
            0) break ;;
        esac
    done
}

install_firewall() {
    echo -e "\n${BOLD}${MAIN_COLOR}  активация 'Ядерного бана' для Leaseweb${NC}"
    run_step "установка пакетов" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y ipset whois iptables-persistent -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    cat << 'EOF' > $BLOCK_SCRIPT
#!/bin/bash
ASNS=("AS16265" "AS60781" "AS28753" "AS30633" "AS38731" "AS49367" "AS51395" "AS50673" "AS59253" "AS133752" "AS134351")
ipset create leaseweb_v4 hash:net family inet hashsize 4096 maxelem 65536 2>/dev/null
ipset create leaseweb_v6 hash:net family inet6 hashsize 4096 maxelem 65536 2>/dev/null
for ASN in "${ASNS[@]}"; do
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route:' | awk '{print $2}' | while read -r ip; do ipset add leaseweb_v4 $ip -quiet; done
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route6:' | awk '{print $2}' | while read -r ip; do ipset add leaseweb_v6 $ip -quiet; done
done
ipset save > /etc/ipset.conf
EOF
    chmod +x $BLOCK_SCRIPT
    run_step "сбор базы IP" "$BLOCK_SCRIPT"
    cat << 'EOF' > /etc/systemd/system/ipset-persistent.service
[Unit]
Description=Restore ipset
Before=network.target netfilter-persistent.service
ConditionFileNotEmpty=/etc/ipset.conf
[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -file /etc/ipset.conf
ExecStop=/sbin/ipset save -file /etc/ipset.conf
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    run_step "настройка автозагрузки" "systemctl daemon-reload && systemctl enable ipset-persistent"
    run_step "применение правил" "iptables -I INPUT -m set --match-set leaseweb_v4 src -j DROP; ip6tables -I INPUT -m set --match-set leaseweb_v6 src -j DROP; netfilter-persistent save"
    (crontab -l 2>/dev/null | grep -v "block_leaseweb.sh"; echo "0 3 * * 1 $BLOCK_SCRIPT && netfilter-persistent save") | crontab -
    echo -e "${GREEN}${BOLD}  готово!${NC}"
}

remove_firewall() {
    echo -e "\n${BOLD}${RED}  деактивация защиты...${NC}"
    iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null
    ip6tables -D INPUT -m set --match-set leaseweb_v6 src -j DROP 2>/dev/null
    netfilter-persistent save 2>/dev/null
    systemctl disable ipset-persistent 2>/dev/null
    rm -f /etc/systemd/system/ipset-persistent.service $BLOCK_SCRIPT /etc/ipset.conf
    ipset destroy leaseweb_v4 2>/dev/null
    ipset destroy leaseweb_v6 2>/dev/null
    crontab -l 2>/dev/null | grep -v "block_leaseweb.sh" | crontab -
    echo -e "${GREEN}  удалено${NC}"
}

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
            2) [ -f "$SERVICE_FILE" ] && systemctl restart telemt && echo -e "${GREEN}  Ок${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
            3) [ -f "$SERVICE_FILE" ] && systemctl stop telemt && echo -e "${YELLOW}  Стоп${NC}" || echo -e "${RED}$L_ERR_NOT_INSTALLED${NC}"; wait_user ;;
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
                clear; echo -e "${BOLD}${MAIN_COLOR}=== СПИСОК ПОЛЬЗОВАТЕЛЕЙ ===${NC}"
                for i in "${!USERS[@]}"; do printf "  %2d - %s\n" "$((i+1))" "${USERS[$i]}"; done
                read -p "Номер для ссылок (0 - назад): " U_IDX
                [[ "$U_IDX" == "0" ]] && break
                show_links "${USERS[$((U_IDX-1))]}"; wait_user
               done ;;
            2) read -p "Имя: " UNAME
               [[ "$UNAME" =~ ^[a-zA-Z0-9]+$ ]] || { echo "ошибка!"; wait_user; continue; }
               read -p "Лимит: " ULIM; ULIM=${ULIM:-0}
               sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
               echo "$UNAME = \"$(openssl rand -hex 16)\"" >> $CONF_FILE
               systemctl restart telemt; wait_user ;;
            3) # Delete logic...
               mapfile -t USERS < <(get_user_list)
               for i in "${!USERS[@]}"; do printf "  %2d - %s\n" "$((i+1))" "${USERS[$i]}"; done
               read -p "Номер: " U_IDX
               if [ "$U_IDX" -gt 0 ]; then sed -i "/^${USERS[$((U_IDX-1))]} =/d" $CONF_FILE; systemctl restart telemt; fi; wait_user ;;
            4) # IP Limit logic...
               mapfile -t USERS < <(get_user_list)
               for i in "${!USERS[@]}"; do CUR=$(grep "^${USERS[$i]} =" $CONF_FILE | grep -v "\"" | awk '{print $3}'); printf "  %2d - %s (%s)\n" "$((i+1))" "${USERS[$i]}" "${CUR:-0}"; done
               read -p "Номер: " U_IDX; read -p "Лимит: " NLIM; T=${USERS[$((U_IDX-1))]}
               sed -i "/^$T = [0-9]/d" $CONF_FILE; sed -i "/\[access.user_max_unique_ips\]/a $T = ${NLIM:-0}" $CONF_FILE; systemctl restart telemt; wait_user ;;
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
            1) systemctl status telemt; wait_user ;;
            2) read -p "Порт: " NP; sed -i "s/^port = .*/port = $NP/" $CONF_FILE; systemctl restart telemt; wait_user ;;
            3) read -p "SNI: " NS; sed -i "s/^tls_domain = .*/tls_domain = \"$NS\"/" $CONF_FILE; systemctl restart telemt; wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}обновить менеджер${UPDATE_INFO}${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}удалить прокси Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}полная очистка (СТАЛИН-3000)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) echo "обновление..."; curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME" && chmod +x "$CLI_NAME" && exec "$CLI_NAME" ;;
            2) cleanup_proxy; wait_user ;;
            3) cleanup_proxy; rm -f "$CLI_NAME"; echo "удалено"; exit 0 ;;
            0) break ;;
        esac
    done
}

install_telemt() {
    echo -e "\n${BOLD}${MAIN_COLOR}  настройка и установка Telemt${NC}"
    read -p "Порт (443): " P_PORT; P_PORT=${P_PORT:-443}
    read -p "SNI (google.com): " P_SNI; P_SNI=${P_SNI:-google.com}
    read -p "Имя: " P_USER; P_USER=${P_USER:-admin}
    read -p "Лимит IP: " P_LIM; P_LIM=${P_LIM:-0}
    run_step "пакеты" "apt update -qq && apt install curl jq tar openssl -y"
    ARCH=$(uname -m); LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    run_step "бинарник" "curl -L https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz | tar -xz && mv telemt $BIN_PATH && chmod +x $BIN_PATH"
    useradd -d /opt/telemt -m -r -U telemt 2>/dev/null || true
    mkdir -p $CONF_DIR
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
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$P_SNI"
[access.user_max_unique_ips]
$P_USER = $P_LIM
[access.users]
$P_USER = "$(openssl rand -hex 16)"
EOF
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Telemt
After=network.target
[Service]
ExecStart=$BIN_PATH $CONF_FILE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    run_step "запуск" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
}

# --- main loop ---
if [ ! -f "$CLI_NAME" ]; then curl -sSL -f "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"; chmod +x "$CLI_NAME"; fi

while true; do
    check_updates
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║           %s (v%s)         ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    
    [ -f "$SERVICE_FILE" ] && (systemctl is-active --quiet telemt && TSTAT="${GREEN}$L_STATUS_RUN${NC}" || TSTAT="${RED}$L_STATUS_STOP${NC}") || TSTAT="${RED}$L_STATUS_NONE${NC}"
    systemctl list-unit-files | grep -qw 'xray' && (systemctl is-active --quiet xray && XSTAT="${GREEN}$L_STATUS_RUN${NC}" || XSTAT="${RED}$L_STATUS_STOP${NC}") || XSTAT="${RED}$L_STATUS_NONE${NC}"
    ipset list leaseweb_v4 >/dev/null 2>&1 && FWSTAT="${GREEN}ВКЛ${NC}" || FWSTAT="${RED}ВЫКЛ${NC}"

    printf "  %s %b\n" "      $L_STATUS_LABEL" "$TSTAT"
    printf "  %s %b\n" "      $L_XSTATUS_LABEL" "$XSTAT"
    printf "  %s %b\n" "      защита (Firewall):" "$FWSTAT"
    printf "${MAIN_COLOR}------------------------------------------${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}$L_MAIN_5${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 6 -${NC} ${BOLD}%s%b${NC}\n" "$L_MAIN_6" "$UPDATE_INFO"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    read -p "$(echo -e $ORANGE"       выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_xray ;;
        4) submenu_firewall ;;
        5) submenu_settings ;;
        6) submenu_manager ;;
        0) exit 0 ;;
    esac
done
