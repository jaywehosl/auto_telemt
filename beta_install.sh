#!/bin/bash

# ==============================================================================
# сценарий автоматизации Telemt и Zapret
# соблюден стандарт отступов evs и цветовая дифференциация по категориям
# версия: 1.9.5 (linear ui + background update check)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. константы и окружение
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.9.5"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"
V_TMP="/tmp/telemt_v_check" # временный файл для фонового обмена версией

L_IND="  " # стандарт отступа (2 пробела)

# цветовые схемы ANSI (все стили жирные)
NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m'   # салатовый (шапка)
C_MENU='\033[1;38;5;214m'    # оранжевый (пункты, промпты)
C_SKY='\033[1;38;5;81m'      # голубой (индексы, процессы)
C_GREEN='\033[1;32m'         # зеленый (работает, да)
C_RED='\033[1;31m'           # красный (ошибка, нет)
C_YELLOW='\033[1;33m'        # желтый (остановлен)

# пути к системным ресурсам
T_BIN="/bin/telemt"
T_CONF_DIR="/etc/telemt"
T_CONF="$T_CONF_DIR/telemt.toml"
T_SERVICE="/etc/systemd/system/telemt.service"
CLI_PATH="/usr/local/bin/telemt"

Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

# наименования разделов
M_MAIN_1="управление сервисом Telemt"
M_MAIN_2="управление пользователями Telemt"
M_MAIN_3="настройки Telemt"
M_MAIN_4="управление Zapret (TPWS)"
M_MAIN_5="обслуживание менеджера"
M_MAIN_0="выход"

# очистка временных файлов при старте
rm -f "$V_TMP"

# валидация полномочий пользователя
if [ "$EUID" -ne 0 ]; then
    echo -e "${BOLD}${C_RED}!! ошибка: запустите скрипт с root правами${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. функционал фоновых задач
# ------------------------------------------------------------------------------

# запуск фоновой проверки версии (асинхронно, без задержки ui)
check_updates_background() {
    (
        rem_v=$(curl -sSL -f --connect-timeout 2 --max-time 3 "${REPO_URL}?v=$(date +%s)" 2>/dev/null | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        if [[ -n "$rem_v" ]]; then
            echo "$rem_v" > "$V_TMP"
        fi
    ) &
}

# обновление маркера на основе данных из временного файла
refresh_update_marker() {
    if [ -f "$V_TMP" ]; then
        REMOTE_VERSION=$(cat "$V_TMP")
        if [[ "$REMOTE_VERSION" != "$CURRENT_VERSION" ]]; then
            U_MARKER="${BOLD}${C_SKY} (*)${NC}"
            HAS_NEW_VERSION=true
        else
            U_MARKER=""
            HAS_NEW_VERSION=false
        fi
    else
        U_MARKER=""
    fi
}

# ------------------------------------------------------------------------------
# 3. методы визуализации (ui backend)
# ------------------------------------------------------------------------------

# отрисовка шапки с центрированием
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

# вывод блока статусов служб
print_status() {
    local s_t s_z c_t c_z
    
    # проверка telemt
    if [ ! -f "$T_SERVICE" ]; then s_t="не установлен"; c_t="$C_RED"
    elif systemctl is-active --quiet telemt; then s_t="работает"; c_t="$C_GREEN"
    else s_t="остановлен"; c_t="$C_YELLOW"; fi

    # проверка zapret
    if [ ! -f "$Z_SERVICE" ]; then s_z="не установлен"; c_z="$C_RED"
    elif systemctl is-active --quiet zapret-tpws; then s_z="работает"; c_z="$C_GREEN"
    else s_z="остановлен"; c_z="$C_YELLOW"; fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s${NC}\n" "$c_t" "$s_t"
    printf "${L_IND}${BOLD}статус Zapret: %b%s${NC}\n" "$c_z" "$s_z"
}

# вывод системного лога (этапы)
log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

# поле интерактивного ввода данных
prompt_user() {
    local query=$(echo -e "$1" | sed "s/y\//${C_GREEN}y${NC}\//g" | sed "s/\/n/\/${C_RED}n${NC}/g")
    printf "${L_IND}${BOLD}${C_MENU}>> %b: ${NC}" "$query"
    read -r "$2"
}

# ------------------------------------------------------------------------------
# 4. логика подразделов
# ------------------------------------------------------------------------------

# обслуживание сервиса telemt
menu_service() {
    check_updates_background # триггер фоновой проверки
    while true; do
        printf "\033[H\033[J" # сброс буфера (мягкая очистка)
        draw_header "УПРАВЛЕНИЕ TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}перезапустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1)  printf "\n"
                prompt_user "порт (443)" p_port; p_port=${p_port:-443}
                prompt_user "sni домен" p_sni; p_sni=${p_sni:-google.com}
                prompt_user "имя администратора" p_user; p_user=${p_user:-admin}
                printf "\n"
                log_step "кеш пакетов" "apt-get update -qq"
                log_step "установка утилит" "apt-get install -y curl jq tar openssl net-tools -qq"
                local arch=$(uname -m); local libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
                local url="https://github.com/telemt/telemt/releases/latest/download/telemt-$arch-linux-$libc.tar.gz"
                log_step "бинарный файл" "curl -L '$url' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
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
                log_step "регистрация" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
                local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$p_user\") | .links.tls[]" 2>/dev/null)
                printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа: ${C_MENU}$p_user${NC}\n"
                for l in $lnk; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$ip}${NC}"; done
                printf "\n"; prompt_user "нажмите [Enter] для продолжения" wait; break ;;
            2) printf "\n"; log_step "перезапуск" "systemctl restart telemt"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop telemt"; sleep 1 ;;
            0) check_updates_background; break ;;
        esac
    done
}

# управление доступом пользователей
menu_users() {
    check_updates_background
    while true; do
        printf "\033[H\033[J"
        draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ошибка: сервис еще не установлен${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "выберите" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}список и ключи${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}создать пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "^[a-zA-Z0-9]" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_ORANGE}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                printf "\n"; prompt_user "номер (0 - отмена)" uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                    local target="${U_LIST[$((uidx-1))]}"
                    local ip=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                    local lnk=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    printf "\n${L_IND}${BOLD}${C_SKY}ссылки для: $target${NC}\n"
                    for l in $lnk; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$ip}${NC}"; done
                    printf "\n"; prompt_user "нажмите [Enter]" wait; fi ;;
            2)  printf "\n"; prompt_user "имя нового клиента" nname
                if [ -n "$nname" ]; then
                    echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF"
                    log_step "обновление базы" "systemctl restart telemt"; sleep 1; fi ;;
            0) check_updates_background; break ;;
        esac
    done
}

# настройки сервиса
menu_settings() {
    check_updates_background
    while true; do
        printf "\033[H\033[J"
        draw_header "НАСТРОЙКИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ошибка: сервис еще не установлен${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "выберите" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}логи системы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}изменить порт${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) printf "\n"; journalctl -u telemt -n 50 --no-pager; printf "\n"; prompt_user "нажмите [Enter]" wait ;;
            2) printf "\n"; prompt_user "укажите новый порт" nport
               [[ "$nport" =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $nport/" "$T_CONF" && log_step "сохранение" "systemctl restart telemt" && sleep 1 ;;
            0) check_updates_background; break ;;
        esac
    done
}

# подсистема zapret
menu_zapret() {
    check_updates_background
    while true; do
        printf "\033[H\033[J"
        draw_header "УПРАВЛЕНИЕ ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}удалить из системы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1)  printf "\n"
                log_step "зависимости билда" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
                log_step "исходный код" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
                log_step "компиляция" "make -C $Z_DIR"
                cat <<EOF > $Z_SERVICE
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
EOF
                log_step "старт юнита" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
                printf "\n"; prompt_user "инсталляция завершена, нажмите [Enter]" wait ;;
            2) printf "\n"; log_step "старт" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "стоп" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; prompt_user "выполнить удаление Zapret? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"
                    log_step "деактивация" "systemctl stop zapret-tpws && systemctl disable zapret-tpws"
                    log_step "очистка данных" "rm -rf $Z_DIR $Z_SERVICE && systemctl daemon-reload"
                    sleep 1; fi ;;
            0) check_updates_background; break ;;
        esac
    done
}

# обслуживание
menu_maintenance() {
    check_updates_background
    while true; do
        printf "\033[H\033[J"
        draw_header "ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА"; echo ""; print_status; echo ""
        refresh_update_marker
        if [ "$HAS_NEW_VERSION" = true ]; then
            local item_1="обновить менеджер до v$REMOTE_VERSION"
        else
            local item_1="переустановить текущую версию v$CURRENT_VERSION"
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}$item_1${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}удалить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}удалить все компоненты${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "выберите действие" act
        case "$act" in
            1) printf "\n"; log_step "загрузка" "curl -sSL -f ${REPO_URL}?v=$(date +%s) -o $CLI_PATH && chmod +x $CLI_PATH"; sleep 1; exec "$CLI_PATH" ;;
            2) printf "\n"; prompt_user "удалить Telemt? (y/n)" cf
               [[ "$cf" =~ ^[Yy]$ ]] && printf "\n" && log_step "очистка" "systemctl stop telemt && systemctl disable telemt && rm -rf $T_CONF_DIR $T_BIN $T_SERVICE && systemctl daemon-reload"; sleep 1 ;;
            3) printf "\n"; prompt_user "УНИЧТОЖИТЬ ВСЕ ПРОКСИ? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"
                    systemctl stop telemt zapret-tpws 2>/dev/null
                    systemctl disable telemt zapret-tpws 2>/dev/null
                    rm -rf "$T_CONF_DIR" "$T_BIN" "$T_SERVICE" "$Z_DIR" "$Z_SERVICE" "$CLI_PATH"
                    systemctl daemon-reload; clear
                    echo -e "${L_IND}${BOLD}${C_RED}все сервисы удалены. завершение работы.${NC}"; exit 0; fi ;;
            0) check_updates_background; break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. жизненный цикл (runtime)
# ------------------------------------------------------------------------------

# запуск фонового процесса при старте
check_updates_background

clear
while true; do
    # мониторинг статуса фоновой проверки
    refresh_update_marker
    
    printf "\033[H\033[J" # сброс экрана
    draw_header "СТАЛИН-3000 (v$CURRENT_VERSION)"
    echo ""; print_status; echo ""

    echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_1${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_2${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_3${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_4${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_ORANGE}$M_MAIN_5$U_MARKER${NC}"
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
        # любой другой ввод вызывает фоновую проверку и обновление интерфейса
        *) check_updates_background ;;
    esac
done
