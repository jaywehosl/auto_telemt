#!/bin/bash

# ==============================================================================
# сценарий автоматизации Telemt и Zapret
# соблюден стандарт отступов evs и цветовая дифференциация по категориям
# версия: 3.0.0
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. константы и окружение
# ------------------------------------------------------------------------------
CURRENT_VERSION="3.0.0"
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

# наименования разделов для главного меню
M_MAIN_1="Менеджер Telemt"
M_MAIN_2="Менеджер Zapret"
M_MAIN_3="Менеджер скрипта"
M_MAIN_0="Выход"

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

# фоновая проверка версии для исключения лагов ui
check_updates_background() {
    (
        rem_v=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        if [[ -n "$rem_v" ]]; then echo "$rem_v" > "$V_TMP"; fi
    ) &
}

# обновление маркера версии на главном экране
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

# полная очистка telemt из системы
clear_telemt() {
    log_step "Остановка сервиса Telemt" "systemctl stop telemt"
    log_step "Деактивация автозагрузки" "systemctl disable telemt"
    log_step "Удаление файлов Telemt" "rm -rf $T_CONF_DIR $T_BIN $T_SERVICE"
    log_step "Перезагрузка юнитов systemd" "systemctl daemon-reload"
}

# полная очистка zapret из системы
clear_zapret() {
    log_step "Остановка демона Zapret" "systemctl stop zapret-tpws"
    log_step "Деактивация автозагрузки" "systemctl disable zapret-tpws"
    log_step "Удаление файлов Zapret" "rm -rf $Z_DIR $Z_SERVICE"
    log_step "Перезагрузка юнитов systemd" "systemctl daemon-reload"
}

# ------------------------------------------------------------------------------
# 3. методы визуализации (frontend)
# ------------------------------------------------------------------------------

# отрисовка шапки
draw_header() {
    local text="$1"; local w=44
    local p=$(( (w - ${#text}) / 2 )); local e=$(( (w - ${#text}) % 2 ))
    printf "${BOLD}${C_FRAME}╔"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╗${NC}\n"
    printf "${BOLD}${C_FRAME}║${NC}${BOLD}%*s%s%*s${BOLD}${C_FRAME}║${NC}\n" "$p" "" "$text" "$((p + e))" ""
    printf "${BOLD}${C_FRAME}╚"
    for ((i=0; i<w; i++)); do printf "═"; done
    printf "╝${NC}\n"
}

# блок мониторинга статусов
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

# стандартная строка процесса
log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

# унифицированный промпт
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

menu_telemt() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}Установить / переустановить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}Запустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}Остановить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}Перезапустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_MENU}Управление пользователями${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}6 - ${NC}${BOLD}${C_MENU}Просмотр логов${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}Назад${NC}"
        printf "\n"; prompt_user "Выберите действие" act
        case "$act" in
            1)  printf "\n"; prompt_user "Порт (443)" p_port; p_port=${p_port:-443}
                prompt_user "SNI домен (google.com)" p_sni; p_sni=${p_sni:-google.com}
                prompt_user "Имя администратора (admin)" p_user; p_user=${p_user:-admin}
                printf "\n"; log_step "Обновление кеша пакетов" "apt-get update -qq"
                log_step "Установка утилит" "apt-get install -y curl jq tar openssl net-tools -qq"
                local arch=$(uname -m); local libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                local url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$libc.tar.gz"
                log_step "Загрузка бинарных данных" "curl -L '$url' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
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
                log_step "Старт службы в системе" "systemctl daemon-reload && systemctl enable --now telemt"
                local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "ВАШ_IP")
                local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$p_user\") | .links.tls[]" 2>/dev/null)
                printf "\n${L_IND}${BOLD}${C_SKY}Ключи доступа для: ${C_MENU}$p_user${NC}\n"
                for l in $lnk; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                printf "\n"; prompt_user "Нажмите [Enter] для возврата" wait; continue ;;
            2) printf "\n"; log_step "Запуск Telemt" "systemctl start telemt"; sleep 1 ;;
            3) printf "\n"; log_step "Остановка Telemt" "systemctl stop telemt"; sleep 1 ;;
            4) printf "\n"; log_step "Перезапуск Telemt" "systemctl restart telemt"; sleep 1 ;;
            5) menu_telemt_users ;;
            6) printf "\n"; journalctl -u telemt -n 50 --no-pager; printf "\n"; prompt_user "Нажмите [Enter] для возврата" wait ;;
            0) check_updates_background; break ;;
        esac
    done
}

menu_telemt_users() {
     while true; do
        printf "\033[H\033[J"
        draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! Ошибка: сервис Telemt не установлен${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}Назад${NC}"; printf "\n"
            prompt_user "Выберите" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}Список пользователей и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}Добавить нового пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}Удалить пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}Назад${NC}"
        printf "\n"; prompt_user "Действие" act
        case "$act" in
            1)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep -E "^[a-zA-Z0-9]" | grep "=" | awk '{print $1}' | sort -u)
                if [ ${#U_LIST[@]} -eq 0 ]; then
                    echo -e "${L_IND}${BOLD}${C_YELLOW}Пользователи не найдены.${NC}"
                else
                    for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_MENU}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                    printf "\n"; prompt_user "Номер пользователя для ссылок (0 - назад)" uidx
                    if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                        local target="${U_LIST[$((uidx-1))]}"
                        local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "ВАШ_IP")
                        local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                        printf "\n${L_IND}${BOLD}${C_SKY}Ссылки для $target:${NC}\n"
                        for l in $lnk; do echo -e "${L_IND}${BOLD}${C_MENU}${l//0.0.0.0/$ip}${NC}"; done
                    fi
                fi
                printf "\n"; prompt_user "Нажмите [Enter]" wait; continue ;;
            2)  printf "\n"; prompt_user "Имя нового пользователя" nname
                if [ -n "$nname" ]; then
                    echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF"
                    log_step "Обновление базы данных" "systemctl restart telemt"; sleep 1; fi ;;
            3)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep -E "^[a-zA-Z0-9]" | grep "=" | awk '{print $1}' | sort -u)
                 if [ ${#U_LIST[@]} -eq 0 ]; then
                    echo -e "${L_IND}${BOLD}${C_YELLOW}Пользователи не найдены.${NC}\n"
                 else
                    for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_MENU}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                    printf "\n"; prompt_user "Номер пользователя для удаления (0 - назад)" uidx
                    if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                        local target="${U_LIST[$((uidx-1))]}"
                        prompt_user "Удалить $target? (y/n)" confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            sed -i "/^${target} =/d" "$T_CONF"
                            log_step "Удаление пользователя $target" "systemctl restart telemt"; sleep 1
                        fi
                    fi
                 fi ;;
            0) break ;;
        esac
    done
}

menu_zapret() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}Установить / обновить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}Запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}Остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}Удалить Zapret из системы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}Назад${NC}"
        printf "\n"; prompt_user "Действие" act
        case "$act" in
            1)  printf "\n"; prompt_user "Локальный порт для Zapret (1080)" z_port; z_port=${z_port:-1080}
                printf "\n"; log_step "Установка библиотек" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                log_step "Клонирование репозитория" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                log_step "Сборка проекта" "make -C $Z_DIR"
                cat <<EOF > $Z_SERVICE
[Unit]
Description=Zapret TPWS Daemon
After=network.target
[Service]
Type=simple
User=root
ExecStart=$Z_DIR/tpws/tpws --bind-addr=127.0.0.1 --port=$z_port --socks --split-http-req=host --split-pos=2 --hostcase --hostspell=hoSt --split-tls=sni --disorder --tlsrec=sni
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
                log_step "Регистрация демона в системе" "systemctl daemon-reload && systemctl enable --now zapret-tpws"
                printf "\n"; prompt_user "Установка завершена, нажмите [Enter]" wait ;;
            2) printf "\n"; log_step "Запуск Zapret" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "Остановка Zapret" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; prompt_user "Полностью удалить Zapret? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; clear_zapret; sleep 1; fi ;;
            0) check_updates_background; break ;;
        esac
    done
}

menu_script_manager() {
    while true; do
        printf "\033[H\033[J"
        draw_header "МЕНЕДЖЕР СКРИПТА"; echo ""; print_status; echo ""
        refresh_update_marker
        if [ "$HAS_NEW_VERSION" = true ]; then item_1="Обновить менеджер до v$REMOTE_VERSION"
        else item_1="Переустановить текущую версию v$CURRENT_VERSION"; fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_MENU}$item_1${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_MENU}Удалить только Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_MENU}Удалить только Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_MENU}Удалить оба сервиса${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_MENU}Удалить ВСЁ (включая этот скрипт)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_MENU}Назад${NC}"
        printf "\n"; prompt_user "Выберите действие" act
        case "$act" in
            1) printf "\n"; log_step "Скачивание обновления" "curl -sSL -f ${REPO_URL}?v=$(date +%s) -o $CLI_PATH && chmod +x $CLI_PATH"; sleep 1; exec "$CLI_PATH" ;;
            2) printf "\n"; prompt_user "Удалить Telemt из системы? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && printf "\n" && clear_telemt && sleep 1 ;;
            3) printf "\n"; prompt_user "Удалить Zapret из системы? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && printf "\n" && clear_zapret && sleep 1 ;;
            4) printf "\n"; prompt_user "Удалить Telemt и Zapret? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && printf "\n" && clear_telemt && clear_zapret && sleep 1 ;;
            5) printf "\n"; prompt_user "ПОЛНОСТЬЮ очистить систему? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; clear_telemt; clear_zapret
                    log_step "Удаление менеджера" "rm -f $CLI_PATH"
                    clear
                    echo -e "${L_IND}${BOLD}${C_RED}Инфраструктура полностью очищена.${NC}"; exit 0; fi ;;
            0) check_updates_background; break ;;
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
    prompt_user "Выберите раздел" main_sel
    
    case "$main_sel" in
        1) menu_telemt ;;
        2) menu_zapret ;;
        3) menu_script_manager ;;
        0) clear; tput cnorm; exit 0 ;;
        *) check_updates_background ;;
    esac
done
