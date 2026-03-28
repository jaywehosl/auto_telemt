#!/bin/bash

# ==========================================================
# params
# ==========================================================
CURRENT_VERSION="1.4.1"
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
L_STATUS_RUN="работает"
L_STATUS_STOP="остановлен"
L_STATUS_NONE="не установлен"

L_MAIN_1="управление сервисом"
L_MAIN_2="управление пользователями"
L_MAIN_3="управление защитой (Firewall)"
L_MAIN_4="настройки Telemt"
L_MAIN_5="обслуживание менеджера"
L_MAIN_0="выход"

L_PROMPT_BACK="назад"
L_MSG_WAIT_ENTER="       нажмите [Enter] для продолжения..."
L_ERR_NOT_INSTALLED="       ошибка: прокси еще не установлен!"
# ==========================================================

# path
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
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
    sleep 4
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

# --- Firewall Logic ---

install_firewall() {
    echo -e "\n${BOLD}${MAIN_COLOR}  активация 'Ядерного бана' для Leaseweb${NC}"
    # ФИКС: Полностью неинтерактивная установка
    run_step "установка ipset и whois" "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y ipset whois iptables-persistent -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    
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
    
    run_step "сбор базы IP адресов" "$BLOCK_SCRIPT"
    
    cat << 'EOF' > /etc/systemd/system/ipset-persistent.service
[Unit]
Description=Restore ipset sets before iptables
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
    
    run_step "применение правил iptables" "
    iptables -I INPUT -m set --match-set leaseweb_v4 src -j DROP;
    iptables -I OUTPUT -m set --match-set leaseweb_v4 dst -j DROP;
    iptables -I FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP;
    ip6tables -I INPUT -m set --match-set leaseweb_v6 src -j DROP;
    ip6tables -I OUTPUT -m set --match-set leaseweb_v6 dst -j DROP;
    ip6tables -I FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP;
    netfilter-persistent save"
    
    (crontab -l 2>/dev/null | grep -v "block_leaseweb.sh"; echo "0 3 * * 1 $BLOCK_SCRIPT && netfilter-persistent save") | crontab -
    echo -e "${GREEN}${BOLD}  защита успешно активирована!${NC}"
}

remove_firewall() {
    echo -e "\n${BOLD}${RED}  деактивация защиты...${NC}"
    iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null
    iptables -D OUTPUT -m set --match-set leaseweb_v4 dst -j DROP 2>/dev/null
    iptables -D FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP 2>/dev/null
    ip6tables -D INPUT -m set --match-set leaseweb_v6 src -j DROP 2>/dev/null
    ip6tables -D OUTPUT -m set --match-set leaseweb_v6 dst -j DROP 2>/dev/null
    ip6tables -D FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP 2>/dev/null
    netfilter-persistent save 2>/dev/null
    
    systemctl disable ipset-persistent 2>/dev/null
    rm -f /etc/systemd/system/ipset-persistent.service $BLOCK_SCRIPT /etc/ipset.conf
    ipset destroy leaseweb_v4 2>/dev/null
    ipset destroy leaseweb_v6 2>/dev/null
    crontab -l 2>/dev/null | grep -v "block_leaseweb.sh" | crontab -
    echo -e "${GREEN}  защита полностью удалена${NC}"
}

# --- submenu logic ---

submenu_firewall() {
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         УПРАВЛЕНИЕ   ЗАЩИТОЙ           ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        if ipset list leaseweb_v4 >/dev/null 2>&1; then 
            FW_STAT="${GREEN}АКТИВНА${NC}"
            COUNT=$(ipset list leaseweb_v4 2>/dev/null | grep -c '/')
        else 
            FW_STAT="${RED}ВЫКЛЮЧЕНА${NC}"
            COUNT="0"
        fi
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
                read -p "$(echo -e $ORANGE"       введите номер пользователя: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    show_links "${USERS[$((U_IDX-1))]}"; wait_user
                fi
            done ;;
            2) while true; do
                read -p "$(echo -e $ORANGE"       введите имя пользователя: "$NC)" UNAME
                [[ "$UNAME" =~ ^[a-zA-Z0-9]+$ ]] && break || echo -e "       ${RED}ошибка! только буквы и цифры!${NC}"
               done
                if [ -n "$UNAME" ]; then
                    read -p "$(echo -e $ORANGE"       лимит IP (0 - безл): "$NC)" ULIM; ULIM=${ULIM:-0}
                    U_SEC=$(openssl rand -hex 16)
                    sed -i "/\[access.user_max_unique_ips\]/a $UNAME = $ULIM" $CONF_FILE
                    echo "$UNAME = \"$U_SEC\"" >> $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}       добавлен${NC}"; wait_user
                fi ;;
            3) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}║         УДАЛЕНИЕ   ПОЛЬЗОВАТЕЛЯ        ║${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC}\n" "$((i+1))" "${USERS[$i]}"; done
                printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}назад${NC}\n"
                read -p "$(echo -e $ORANGE"       номер для удаления: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    DEL_NAME="${USERS[$((U_IDX-1))]}"; sed -i "/^$DEL_NAME =/d" $CONF_FILE
                    systemctl restart telemt && echo -e "${RED}       удалён${NC}"; wait_user
                fi
            done ;;
            4) while true; do
                mapfile -t USERS < <(get_user_list)
                clear; echo -e "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}║           ЛИМИТЫ  IP  АДРЕСОВ          ║${NC}"
                       echo -e "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}"
                for i in "${!USERS[@]}"; do
                    CUR_LIM=$(grep "^${USERS[$i]} =" $CONF_FILE | grep -v "\"" | awk '{print $3}')
                    printf "  ${BOLD}${MAIN_COLOR}%2d -${NC} ${BOLD}%s${NC} (лимит: ${YELLOW}%s${NC})\n" "$((i+1))" "${USERS[$i]}" "${CUR_LIM:-0}"
                done
                printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}Назад${NC}\n"
                read -p "$(echo -e $ORANGE"       номер для смены лимита: "$NC)" U_IDX
                [[ "$U_IDX" == "0" ]] && break
                if [[ "$U_IDX" =~ ^[0-9]+$ ]] && [ "$U_IDX" -gt 0 ] && [ "$U_IDX" -le "${#USERS[@]}" ]; then
                    T_USER="${USERS[$((U_IDX-1))]}"; read -p "$(echo -e $ORANGE"       новый лимит IP: "$NC)" N_LIM
                    sed -i "/^$T_USER = [0-9]/d" $CONF_FILE
                    sed -i "/\[access.user_max_unique_ips\]/a $T_USER = ${N_LIM:-0}" $CONF_FILE
                    systemctl restart telemt && echo -e "${GREEN}       обновлён${NC}"; wait_user
                fi
            done ;;
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
            2) read -p "$(echo -e $ORANGE"       новый порт: "$NC)" N_PORT
                [[ $N_PORT =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $N_PORT/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}  Ок${NC}" || echo -e "${RED} ошибка!${NC}"
                wait_user ;;
            3) read -p "$(echo -e $ORANGE"       новый SNI: "$NC)" N_SNI
                [ -n "$N_SNI" ] && sed -i "s/^tls_domain = .*/tls_domain = \"$N_SNI\"/" $CONF_FILE && systemctl restart telemt && echo -e "${GREEN}  Ок${NC}" || echo -e "${RED} ошибка!${NC}"
                wait_user ;;
            0) break ;;
        esac
    done
}

submenu_manager() {
    check_updates
    while true; do
        clear
        printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
        printf "${BOLD}${MAIN_COLOR}║         ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА         ║${NC}\n"
        printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}обновить менеджер${UPDATE_INFO}${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}удалить сервис Telemt${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}полная очистка (СТАЛИН-3000)${NC}\n"
        printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_PROMPT_BACK${NC}\n"
        read -p "$(echo -e $ORANGE"       выберите действие: "$NC)" subchoice
        case $subchoice in
            1) echo -e "${SKY_BLUE}       обновление...${NC}"; if curl -sSL -f "${REPO_URL}?v=$(date +%s)" -o "$CLI_NAME"; then
               sync; chmod +x "$CLI_NAME"; echo -e "${GREEN}Готово!${NC}"; sleep 1; exec "$CLI_NAME";
               else echo -e "${RED}ошибка${NC}"; wait_user; fi ;;
            2) read -p "$(echo -e ${RED}"       удалить сервис и конфиги? ${MAIN_COLOR}(y/n):"$NC)" confirm
               if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then cleanup_proxy && wait_user; fi ;;
            3) read -p "$(echo -e ${RED}"       удалить менеджер полностью? ${MAIN_COLOR}(y/n):"$NC)" confirm
               if [[ "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then cleanup_proxy; rm -f "$CLI_NAME"; echo -e "${RED}удалено${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# --- main cycle ---
if [ ! -f "$CLI_NAME" ]; then
    curl -sSL -f "$REPO_URL" -o "$CLI_NAME" 2>/dev/null || cp "$0" "$CLI_NAME"
    chmod +x "$CLI_NAME"
fi

while true; do
    check_updates
    clear
    printf "${BOLD}${MAIN_COLOR}╔════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${MAIN_COLOR}║           %s (v%s)         ║${NC}\n" "$L_MENU_HEADER" "$CURRENT_VERSION"
    printf "${BOLD}${MAIN_COLOR}╚════════════════════════════════════════╝${NC}\n"
    if [ ! -f "$SERVICE_FILE" ]; then STATUS="${BOLD}${RED}$L_STATUS_NONE${NC}"
    elif systemctl is-active --quiet telemt; then STATUS="${BOLD}${GREEN}$L_STATUS_RUN${NC}"
    else STATUS="${BOLD}${YELLOW}$L_STATUS_STOP${NC}"; fi
    
    if ipset list leaseweb_v4 >/dev/null 2>&1; then FW_STAT="${GREEN}ВКЛ${NC}"; else FW_STAT="${RED}ВЫКЛ${NC}"; fi
    
    printf "  %s %b\n" "      $L_STATUS_LABEL" "$STATUS"
    printf "  %s %b\n" "      защита (Firewall):" "$FW_STAT"
    printf "${MAIN_COLOR}------------------------------------------${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 1 -${NC} ${BOLD}$L_MAIN_1${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 2 -${NC} ${BOLD}$L_MAIN_2${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 3 -${NC} ${BOLD}$L_MAIN_3${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 4 -${NC} ${BOLD}$L_MAIN_4${NC}\n"
    printf "  ${BOLD}${MAIN_COLOR} 5 -${NC} ${BOLD}%s%b${NC}\n" "$L_MAIN_5" "$UPDATE_INFO"
    printf "  ${BOLD}${MAIN_COLOR} 0 -${NC} ${BOLD}$L_MAIN_0${NC}\n"
    read -p "$(echo -e $ORANGE"       выберите раздел: "$NC)" mainchoice
    case $mainchoice in
        1) submenu_service ;;
        2) submenu_users ;;
        3) submenu_firewall ;;
        4) submenu_settings ;;
        5) submenu_manager ;;
        0) exit 0 ;;
        *) sleep 0.5 ;;
    esac
done
