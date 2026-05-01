#!/bin/bash

# ==============================================================================
# сценарий автоматизации Telemt и Zapret
# соблюден стандарт отступов evs и цветовая дифференциация по категориям
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. константы
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.9.3"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # стандарт отступа (2 пробела)

# цветовые схемы ANSI
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

# названия разделов для главного меню
M_MAIN_1="управление сервисом Telemt"
M_MAIN_2="управление пользователями Telemt"
M_MAIN_3="настройки Telemt"
M_MAIN_4="управление Zapret"
M_MAIN_5="обслуживание менеджера"
M_MAIN_0="выход"

# анимационные кадры (пульсация)
SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
S_IDX=0

# валидация root-прав
if [ "$EUID" -ne 0 ]; then
    echo -e "${BOLD}${C_RED}!! ошибка: запустите скрипт с root правами${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. методы вывода
# ------------------------------------------------------------------------------

# [отрисовка]: заголовок раздела в рамке
draw_header() {
    local text="$1"
    local w=44
    local p=$(( (w - ${#text}) / 2 ))
    local e=$(( (w - ${#text}) % 2 ))
    printf "${BOLD}${C_FRAME}╔"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${C_FRAME}║${NC}${BOLD}%*s%s%*s${BOLD}${C_FRAME}║${NC}\n" "$p" "" "$text" "$((p + e))" ""
    printf "${BOLD}${C_FRAME}╚"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# [отрисовка]: блок состояния сервисов
print_status() {
    local s_t s_z c_t c_z p_t p_z
    S_IDX=$(( (S_IDX + 1) % ${#SPINNER[@]} ))
    local sym="${SPINNER[$S_IDX]}"
    
    if [ ! -f "$T_SERVICE" ]; then s_t="не установлен"; c_t="$C_RED"; p_t=""
    elif systemctl is-active --quiet telemt; then s_t="работает"; c_t="$C_GREEN"; p_t="$sym"
    else s_t="остановлен"; c_t="$C_YELLOW"; p_t=""; fi

    if [ ! -f "$Z_SERVICE" ]; then s_z="не установлен"; c_z="$C_RED"; p_z=""
    elif systemctl is-active --quiet zapret-tpws; then s_z="работает"; c_z="$C_GREEN"; p_z="$sym"
    else s_z="остановлен"; c_z="$C_YELLOW"; p_z=""; fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s %s${NC}\033[K\n" "$c_t" "$s_t" "$p_t"
    printf "${L_IND}${BOLD}статус Zapret: %b%s %s${NC}\033[K\n" "$c_z" "$s_z" "$p_z"
}

# [отрисовка]: шаг системного процесса
log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

# [отрисовка]: интерактивное поле ввода
prompt_user() {
    local query=$(echo -e "$1" | sed "s/y\//${C_GREEN}y${NC}\//g" | sed "s/\/n/\/${C_RED}n${NC}/g")
    printf "${L_IND}${BOLD}${C_MENU}>> %b: ${NC}" "$query"
    read -r "$2"
}

# ------------------------------------------------------------------------------
# 3. бекенд (логические методы)
# ------------------------------------------------------------------------------

# фоновая проверка версий с лимитом времени
get_upd_marker() {
    local rem
    rem=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}" 2>/dev/null | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    [[ -n "$rem" && "$rem" != "$CURRENT_VERSION" ]] && marker="${BOLD}${C_SKY} (*)${NC}" || marker=""
    remote_v="$rem"
}

# деинсталляция telemt
clear_telemt() {
    log_step "остановка сервиса" "systemctl stop telemt"
    log_step "отключение автозагрузки" "systemctl disable telemt"
    log_step "удаление конфигураций" "rm -rf $T_CONF_DIR $T_BIN $T_SERVICE"
    systemctl daemon-reload
}

# деинсталляция zapret
clear_zapret() {
    log_step "остановка демона tpws" "systemctl stop zapret-tpws"
    log_step "удаление юнита и файлов" "systemctl disable zapret-tpws && rm -rf $Z_DIR $Z_SERVICE"
    systemctl daemon-reload
}

# ------------------------------------------------------------------------------
# 4. разделы меню
# ------------------------------------------------------------------------------

# подменю управления сервисом telemt
menu_service() {
    while true; do
        printf "\033[H\033[J"
        draw_header "УПРАВЛЕНИЕ TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}перезапустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1)  printf "\n"
                prompt_user "порт прокси (по умолчанию 443)" p_port; p_port=${p_port:-443}
                prompt_user "домен SNI (google.com)" p_sni; p_sni=${p_sni:-google.com}
                prompt_user "имя администратора" p_user; p_user=${p_user:-admin}
                printf "\n"
                log_step "обновление кеша репозиториев" "apt-get update -qq"
                log_step "установка curl и tar" "apt-get install -y curl jq tar openssl net-tools -qq"
                local arch=$(uname -m); local libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                local url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$libc.tar.gz"
                log_step "получение бинарного релиза" "curl -L '$url' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
                mkdir -p $T_CONF_DIR
                cat <<EOF > $T_CONF
[general]
use_middle_proxy = false
[general.modes]
tls = true
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
ExecStart=$T_BIN $T_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
                log_step "старт службы в системе" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$p_user\") | .links.tls[]" 2>/dev/null)
                printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа пользователя ${C_MENU}$p_user${C_SKY}:${NC}\n"
                for l in $lnk; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$ip}${NC}"; done
                printf "\n"; prompt_user "нажмите [Enter] для возврата" wait ;;
            2) printf "\n"; log_step "перезапуск" "systemctl restart telemt"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop telemt"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# подменю управления доступом
menu_users() {
    while true; do
        printf "\033[H\033[J"
        draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ошибка: сервис Telemt еще не установлен${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "назад" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}список пользователей и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}добавить нового пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "^[a-zA-Z0-9]" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_ORANGE}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                printf "\n"; prompt_user "номер пользователя (0 - отмена)" uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                    local t_user="${U_LIST[$((uidx-1))]}"
                    local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                    local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$t_user\") | .links.tls[]" 2>/dev/null)
                    printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа пользователя $t_user:${NC}\n"
                    for l in $lnk; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$ip}${NC}"; done
                    printf "\n"; prompt_user "нажмите [Enter]" wait; fi ;;
            2)  printf "\n"; prompt_user "имя нового пользователя" nname
                if [ -n "$nname" ]; then
                    echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF"
                    log_step "применение настроек" "systemctl restart telemt"; sleep 1; fi ;;
            0) break ;;
        esac
    done
}

# подменю конфигурации telemt
menu_settings() {
    while true; do
        printf "\033[H\033[J"
        draw_header "НАСТРОЙКИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ошибка: сервис Telemt еще не установлен${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "назад" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}системный лог (journalctl)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}изменить порт службы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) printf "\n"; journalctl -u telemt -n 50 --no-pager; printf "\n"; prompt_user "нажмите [Enter] для возврата" wait ;;
            2) printf "\n"; prompt_user "новый сетевой порт" nport
               [[ "$nport" =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $nport/" "$T_CONF" && log_step "перезапуск сервиса" "systemctl restart telemt" && sleep 1 ;;
            0) break ;;
        esac
    done
}

# подменю управления zapret
menu_zapret() {
    while true; do
        printf "\033[H\033[J"
        draw_header "УПРАВЛЕНИЕ ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить / обновить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}полное удаление Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"
                log_step "зависимости компилятора" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                log_step "получение исходников bol-van" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                log_step "сборка исполняемых файлов" "make -C $Z_DIR"
                log_step "конфигурация zapret-tpws" "cat <<EOF > $Z_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=$Z_DIR/tpws/tpws --bind-addr=127.0.0.1 --port=1080 --socks --split-http-req=host --split-pos=2 --hostcase --hostspell=hoSt --split-tls=sni --disorder --tlsrec=sni
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF"
                log_step "активация и старт демона" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
                printf "\n"; prompt_user "установка завершена, нажмите [Enter]" wait ;;
            2) printf "\n"; log_step "запуск zapret-tpws" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "остановка zapret-tpws" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; prompt_user "удалить все компоненты Zapret? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; log_step "деактивация служб" "systemctl stop zapret-tpws && systemctl disable zapret-tpws"
                    log_step "удаление директорий" "rm -rf $Z_DIR $Z_SERVICE"
                    log_step "очистка демона" "systemctl daemon-reload" && sleep 1; fi ;;
            0) break ;;
        esac
    done
}

# подменю обслуживания менеджера
menu_maintenance() {
    while true; do
        printf "\033[H\033[J"
        draw_header "ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА"; echo ""; print_status; echo ""
        local item_1; [[ -n "$marker" ]] && item_1="обновить менеджер до v$remote_v" || item_1="переустановить текущую версию"
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}$item_1${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}удалить только Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}полная очистка всех сервисов${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) printf "\n"; log_step "обновление скрипта" "curl -sSL -f $REPO_URL -o $CLI_PATH && chmod +x $CLI_PATH"; sleep 1; exec "$CLI_PATH" ;;
            2) printf "\n"; prompt_user "выполнить удаление Telemt? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && printf "\n" && clear_telemt && sleep 1 ;;
            3) printf "\n"; prompt_user "УДАЛИТЬ ВСЕ ПРОКСИ И МЕНЕДЖЕР? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"
                    systemctl stop telemt zapret-tpws 2>/dev/null
                    systemctl disable telemt zapret-tpws 2>/dev/null
                    rm -rf "$T_CONF_DIR" "$T_BIN" "$T_SERVICE" "$Z_DIR" "$Z_SERVICE" "$CLI_PATH"
                    systemctl daemon-reload
                    clear; echo -e "${L_IND}${BOLD}${C_RED}все компоненты системы удалены, скрипт завершен${NC}"
                    exit 0; fi ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. главный цикл приложения
# ------------------------------------------------------------------------------
clear
while true; do
    # опрос github на наличие обновлений
    get_upd_marker
    printf "\033[H\033[J"
    draw_header "СТАЛИН-3000 (v$CURRENT_VERSION)"
    echo ""; print_status; echo ""

    echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_1${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_2${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_3${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_4${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_5$marker${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_0${NC}"
    
    printf "\n"
    prompt_user "выберите раздел" main_sel
    
    case "$main_sel" in
        1) menu_service ;;
        2) menu_users ;;
        3) menu_settings ;;
        4) menu_zapret ;;
        5) menu_maintenance ;;
        0) clear; tput cnorm; exit 0 ;;
    esac
done
