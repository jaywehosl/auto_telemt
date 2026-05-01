#!/bin/bash

# ==============================================================================
# сценарий автоматизации Telemt и Zapret
# соблюден стандарт отступов evs и цветовая дифференциация по категориям
# версия: 3.6.0 (Alpha-structure + Beta-styling)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. константы и окружение
# ------------------------------------------------------------------------------
CURRENT_VERSION="3.6.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/alpha_install.sh"
V_TMP="/tmp/telemt_v_check" 

L_IND="  " # стандарт отступа (2 пробела)

# цветовые схемы ANSI (весь текст bold по умолчанию)
NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m'   # салатовый (шапка)
C_MENU='\033[1;38;5;214m'    # оранжевый (пункты, промпты)
C_SKY='\033[1;38;5;81m'      # голубой (индексы, процессы)
C_GREEN='\033[1;32m'         # зеленый (работает, да)
C_RED='\033[1;31m'           # красный (ошибка, нет)
C_YELLOW='\033[1;33m'        # желтый (остановлен)

# системные пути
T_BIN="/bin/telemt"
T_CONF_DIR="/etc/telemt"
T_CONF="$T_CONF_DIR/telemt.toml"
T_SERVICE="/etc/systemd/system/telemt.service"
CLI_PATH="/usr/local/bin/telemt"

Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

# локализация разделов (строго по стилю beta, структура alpha)
M_MAIN_1="менеджер Telemt"
M_MAIN_2="менеджер Zapret"
M_MAIN_3="менеджер скрипта"
M_MAIN_0="выход"

# очистка временных данных проверки обновлений
rm -f "$V_TMP"

# проверка root-прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${BOLD}${C_RED}!! ошибка: запустите скрипт с root правами${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. бэкенд: служебная логика
# ------------------------------------------------------------------------------

check_updates_background() {
    (
        rem_v=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        if [[ -n "$rem_v" ]]; then echo "$rem_v" > "$V_TMP"; fi
    ) &
}

refresh_update_marker() {
    if [ -f "$V_TMP" ]; then
        REMOTE_VERSION=$(cat "$V_TMP")
        if [[ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]]; then
            U_MARKER="${BOLD}${C_SKY} (*)${NC}"; HAS_NEW_VERSION=true
        else
            U_MARKER=""; HAS_NEW_VERSION=false
        fi
    else
        U_MARKER=""; HAS_NEW_VERSION=false
    fi
}

clear_telemt() {
    [ -f "$T_SERVICE" ] && log_step "остановка сервиса" "systemctl stop telemt"
    [ -f "$T_SERVICE" ] && log_step "деактивация автозагрузки" "systemctl disable telemt"
    log_step "удаление конфигурационных файлов" "rm -rf $T_CONF_DIR $T_BIN $T_SERVICE"
    systemctl daemon-reload
}

clear_zapret() {
    [ -f "$Z_SERVICE" ] && log_step "остановка демона" "systemctl stop zapret-tpws"
    [ -f "$Z_SERVICE" ] && log_step "удаление юнита и папок" "systemctl disable zapret-tpws && rm -rf $Z_DIR $Z_SERVICE"
    systemctl daemon-reload
}

# ------------------------------------------------------------------------------
# 3. методы визуализации (frontend)
# ------------------------------------------------------------------------------

draw_header() {
    local text="$1"; local w=44
    local n_chars=$(echo -n "$text" | wc -m)
    local p=$(( (w - n_chars) / 2 )); local e=$(( (w - n_chars) % 2 ))
    printf "${BOLD}${C_FRAME}╔"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${C_FRAME}║${NC}${BOLD}%*s%s%*s${BOLD}${C_FRAME}║${NC}\n" "$p" "" "$text" "$((p + e))" ""
    printf "${BOLD}${C_FRAME}╚"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

print_status() {
    local s_t s_z c_t c_z
    if [ ! -f "$T_SERVICE" ]; then s_t="не установлен"; c_t="$C_RED"
    elif systemctl is-active --quiet telemt; then s_t="работает"; c_t="$C_GREEN"
    else s_t="остановлен"; c_t="$C_YELLOW"; fi
    
    if [ ! -f "$Z_SERVICE" ]; then s_z="не установлен"; c_z="$C_RED"
    elif systemctl is-active --quiet zapret-tpws; then s_z="работает"; c_z="$C_GREEN"
    else s_z="остановлен"; c_z="$C_YELLOW"; fi
    
    printf "${L_IND}${BOLD}статус Telemt: %b%s${NC}\n" "$c_t" "$s_t"
    printf "${L_IND}${BOLD}статус Zapret: %b%s${NC}\n" "$c_z" "$s_z"
}

log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

prompt_user() {
    local text="$1"
    text="${text//y\//${C_GREEN}y${C_MENU}\/}"
    text="${text//\/n/\/${C_RED}n${C_MENU}}"
    printf "${L_IND}${BOLD}${C_MENU}>> %b: ${NC}" "$text"
    read -r "$2"
}

# ------------------------------------------------------------------------------
# 4. подменю разделов
# ------------------------------------------------------------------------------

# менеджер telemt (интегрированная alpha-структура)
menu_telemt() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}установить / переустановить (IPv6 Оптимизация)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}запустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}остановить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}перезапустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_MENU}управление пользователями${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}6 - ${NC}${BOLD}${C_MENU}просмотр логов${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1)  printf "\n"; prompt_user "порт (443)" p_port; p_port=${p_port:-443}
                prompt_user "sni домен" p_sni; p_sni=${p_sni:-google.com}
                prompt_user "имя администратора" p_user; p_user=${p_user:-admin}
                printf "\n"; log_step "обновление кеша пакетов" "apt-get update -qq"
                log_step "установка утилит" "apt-get install -y curl jq tar openssl net-tools wget -qq"
                
                local arch=$(uname -m); local libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                local url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$libc.tar.gz"
                log_step "загрузка бинарных данных" "curl -L '$url' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
                
                mkdir -p $T_CONF_DIR/cache
                log_step "кэширование конфигов (IPv6)" "wget -6 -O $T_CONF_DIR/proxy-secret https://core.telegram.org/getProxySecret && wget -6 -O $T_CONF_DIR/proxy-multi.conf https://core.telegram.org/getProxyConfig && wget -6 -O $T_CONF_DIR/proxy-multi-v6.conf https://core.telegram.org/getProxyConfigV6"
                cp $T_CONF_DIR/proxy-* $T_CONF_DIR/cache/ 2>/dev/null

                cat <<EOF > $T_CONF
[general]
use_middle_proxy = false
[general.modes]
tls = true
[network]
ipv6 = true
prefer = 6
[server]
port = $p_port
[server.api]
enabled = true
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$p_sni"
[access.users]
$p_user = "$(openssl rand -hex 16)"
EOF
                cat <<EOF > $T_SERVICE
[Unit]
Description=Telemt Proxy
After=network-online.target
[Service]
Type=simple
WorkingDirectory=$T_CONF_DIR
ExecStart=$T_BIN $T_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
                log_step "старт службы в системе" "systemctl daemon-reload && systemctl enable --now telemt"
                local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$p_user\") | .links.tls[]" 2>/dev/null)
                printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа: ${C_MENU}$p_user${NC}\n"
                for l in $lnk; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                printf "\n"; prompt_user "нажмите [Enter] для возврата" wait; continue ;;
            2) printf "\n"; log_step "запуск" "systemctl start telemt"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop telemt"; sleep 1 ;;
            4) printf "\n"; log_step "перезапуск" "systemctl restart telemt"; sleep 1 ;;
            5) menu_telemt_users ;;
            6) printf "\n"; if [ ! -f "$T_SERVICE" ]; then echo -e "${L_IND}${BOLD}${C_RED}!! не установлен${NC}"; else journalctl -u telemt -n 50 --no-pager; fi; prompt_user "[Enter]" wait ;;
            0) break ;;
        esac
    done
}

# подменю пользователей (стиль beta)
menu_telemt_users() {
     while true; do
        printf "\033[H\033[J"
        draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then break; fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}список пользователей и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}добавить нового пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}удалить пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "=" | awk '{print $1}' | sort -u)
                if [ ${#U_LIST[@]} -eq 0 ]; then echo -e "${L_IND}${BOLD}${C_YELLOW}пусто${NC}"; else
                    for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_MENU}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                    printf "\n"; prompt_user "номер (0-назад)" uidx
                    if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                        local target="${U_LIST[$((uidx-1))]}"
                        local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                        local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                        printf "\n${L_IND}${BOLD}${C_SKY}ссылки $target:${NC}\n"
                        for l in $lnk; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                        prompt_user "[Enter]" wait; fi
                fi ;;
            2)  prompt_user "имя" nname
                [ -n "$nname" ] && echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF" && log_step "обновление" "systemctl restart telemt" && sleep 1 ;;
            3)  mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - %s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                prompt_user "номер для удаления" uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ]; then
                    target="${U_LIST[$((uidx-1))]}"
                    sed -i "/^${target} =/d" "$T_CONF" && log_step "удаление" "systemctl restart telemt" && sleep 1; fi ;;
            0) break ;;
        esac
    done
}

# менеджер zapret (alpha-структура)
menu_zapret() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}установить / обновить (Стратегия РФ)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}сменить локальный порт${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_MENU}просмотр логов${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}6 - ${NC}${BOLD}${C_MENU}удалить Zapret из системы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"; prompt_user "локальный порт (1080)" z_port; z_port=${z_port:-1080}
                log_step "библиотеки" "apt-get update -qq && apt-get install -y build-essential git -qq"
                log_step "сборка Zapret" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR && make -C $Z_DIR"
                cat <<EOF > $Z_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=$Z_DIR/tpws/tpws --bind-addr=127.0.0.1 --port=$z_port --socks --split-pos=2 --disorder --oob --hostcase --hostspell=hoSt --split-tls=sni --tlsrec=sni
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
                log_step "регистрация" "systemctl daemon-reload && systemctl enable --now zapret-tpws"
                prompt_user "готово. [Enter]" wait ;;
            2) printf "\n"; log_step "запуск" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; prompt_user "укажите новый порт" nport
               if [[ "$nport" =~ ^[0-9]+$ ]]; then
                   sed -i "s/--port=[0-9]*/--port=$nport/" "$Z_SERVICE"
                   log_step "применение" "systemctl daemon-reload && systemctl restart zapret-tpws"; sleep 1; fi ;;
            5) printf "\n"; journalctl -u zapret-tpws -n 50 --no-pager; printf "\n"; prompt_user "[Enter]" wait ;;
            6) printf "\n"; prompt_user "полностью удалить? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && clear_zapret && sleep 1 ;;
            0) break ;;
        esac
    done
}

# менеджер скрипта (alpha-структура)
menu_script_manager() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР СКРИПТА"; echo ""; print_status; echo ""
        refresh_update_marker
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}обновить менеджер до v$REMOTE_VERSION${U_MARKER}${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}удалить только Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}удалить только Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}удалить оба сервиса${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_MENU}полное удаление всего (самоликвидация)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1) printf "\n"; log_step "скачивание" "curl -sSL $REPO_URL -o $CLI_PATH && chmod +x $CLI_PATH"; sleep 1; exec "$CLI_PATH" ;;
            2) printf "\n"; prompt_user "удалить Telemt? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && clear_telemt && sleep 1 ;;
            3) printf "\n"; prompt_user "удалить Zapret? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && clear_zapret && sleep 1 ;;
            4) printf "\n"; clear_telemt; clear_zapret; sleep 1 ;;
            5) printf "\n"; prompt_user "ПОЛНОСТЬЮ очистить систему? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    clear_telemt; clear_zapret; rm -f "$CLI_PATH"
                    clear; echo -e "${BOLD}${C_RED}инфраструктура очищена.${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. жизненный цикл (runtime)
# ------------------------------------------------------------------------------

check_updates_background
clear

while true; do
    refresh_update_marker
    printf "\033[H\033[J"
    draw_header "СТАЛИН-3000 (v$CURRENT_VERSION)"
    echo ""; print_status; echo ""

    echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}$M_MAIN_1${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}$M_MAIN_2${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}$M_MAIN_3$U_MARKER${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}$M_MAIN_0${NC}"
    
    printf "\n"
    prompt_user "выберите раздел" main_sel
    
    case "$main_sel" in
        1) menu_telemt ;;
        2) menu_zapret ;;
        3) menu_script_manager ;;
        0) clear; exit 0 ;;
        *) check_updates_background ;;
    esac
done
