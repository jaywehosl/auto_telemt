#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-ИНФРАСТРУКТУРОЙ «СТАЛИН-3000»
# ВЕРСИЯ: 1.8.5 (STABLE ARCHITECTURE)
# ------------------------------------------------------------------------------
# Сценарий автоматизации Telemt и Zapret (TPWS). 
# Соблюден стандарт отступов EVS и цветовая дифференциация по категориям.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. КОНСТАНТЫ И ПАРАМЕТРЫ ЦВЕТОВ
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.8.5"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

L_IND="  " # Стандарт отступа (2 пробела)

# Цветовые схемы ANSI (Принудительно BOLD)
NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m'   # Салатовый (Шапка)
C_MENU='\033[1;38;5;214m'    # Оранжевый (Пункты, Промпты)
C_SKY='\033[1;38;5;81m'      # Голубой (Индексы, Процессы)
C_GREEN='\033[1;32m'         # Зеленый (Работает, Да)
C_RED='\033[1;31m'           # Красный (Ошибка, Нет)
C_YELLOW='\033[1;33m'        # Желтый (Остановлен)

# Системные пути
T_BIN="/bin/telemt"
T_CONF_DIR="/etc/telemt"
T_CONF="$T_CONF_DIR/telemt.toml"
T_SERVICE="/etc/systemd/system/telemt.service"
CLI_PATH="/usr/local/bin/telemt"

Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"

# Валидация привилегий
if [ "$EUID" -ne 0 ]; then
    echo -e "${BOLD}${C_RED}!! ОШИБКА: Запуск только под root (sudo).${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. МЕТОДЫ ВЫВОДА (ИНТЕРФЕЙСНЫЙ ДВИЖОК)
# ------------------------------------------------------------------------------

# [ОТРИСОВКА]: Динамическая шапка
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

# [ОТРИСОВКА]: Блок статусов
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

# [ОТРИСОВКА]: Формат этапа выполнения (лога)
log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

# [ОТРИСОВКА]: Поле ввода (оранжевое)
# $1 - вопрос, $2 - имя переменной, $3 - цвет ответа (опц)
prompt_user() {
    local query=$(echo -e "$1" | sed "s/y\//${C_GREEN}y${NC}\//g" | sed "s/\/n/\/${C_RED}n${NC}/g")
    printf "${L_IND}${BOLD}${C_MENU}>> %b: ${NC}" "$query"
    read -r "$2"
}

# ------------------------------------------------------------------------------
# 3. БЭКЕНД: ИНСТАЛЛЯЦИОННЫЕ СКРИПТЫ
# ------------------------------------------------------------------------------

do_install_telemt() {
    printf "\n"
    prompt_user "порт прокси (по умолчанию 443)" p_port; p_port=${p_port:-443}
    prompt_user "домен SNI (google.com)" p_sni; p_sni=${p_sni:-google.com}
    prompt_user "имя администратора" p_user; p_user=${p_user:-admin}
    printf "\n"

    log_step "инструментарий системы" "apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq"
    local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    
    log_step "загрузка бинарных данных" "curl -L '$URL' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
    log_step "создание конфига" "mkdir -p $T_CONF_DIR && cat <<EOF > $T_CONF
[general]
use_middle_proxy = false
[general.modes]
tls = true
[server]
port = $p_port
[server.api]
enabled = true
listen = \"127.0.0.1:9091\"
[censorship]
tls_domain = \"$p_sni\"
[access.users]
$p_user = \"\$(openssl rand -hex 16)\"
EOF"
    log_step "регистрация юнита" "cat <<EOF > $T_SERVICE
[Unit]
Description=Telemt Proxy
After=network-online.target
[Service]
Type=simple
ExecStart=$T_BIN $T_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF"
    log_step "старт и активация" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    
    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "IP_NOT_FOUND")
    local LNK=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$p_user\") | .links.tls[]" 2>/dev/null)
    printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа пользователя ${C_MENU}$p_user${C_SKY}:${NC}\n"
    for l in $LNK; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP}${NC}"; done
}

do_install_zapret() {
    printf "\n"
    log_step "библиотеки компиляции" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
    log_step "клонирование исходников" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
    log_step "сборка через make" "make -C $Z_DIR"
    log_step "создание юнита systemd" "cat <<EOF > $Z_SERVICE
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
    log_step "активация zapret" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
    printf "\n${L_IND}${BOLD}${C_GREEN}Установка Zapret (SOCKS:1080) завершена.${NC}\n"
}

# ------------------------------------------------------------------------------
# 4. ЛОГИКА НАВИГАЦИИ (ФРОНТЕНД)
# ------------------------------------------------------------------------------

# [SUB] Раздел TELEMT
menu_service() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}перезапустить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить сервис${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) do_install_telemt; printf "\n"; prompt_user "нажмите [Enter] для возврата" wait; break ;;
            2) printf "\n"; log_step "перезапуск" "systemctl restart telemt"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop telemt"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# [SUB] Раздел ПОЛЬЗОВАТЕЛЕЙ
menu_users() {
    while true; do
        clear; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ОШИБКА: Telemt еще не установлен.${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "назад" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}список пользователей и ссылки${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}добавить нового пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1)  printf "\n"; mapfile -t U_LIST < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!U_LIST[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${NC}${BOLD}${C_ORANGE}%s${NC}\n" "$((i+1))" "${U_LIST[$i]}"; done
                printf "\n"; prompt_user "номер пользователя (0-назад)" uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#U_LIST[@]}" ]; then
                    local t_user="${U_LIST[$((uidx-1))]}"
                    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                    local LN=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$t_user\") | .links.tls[]" 2>/dev/null)
                    printf "\n${L_IND}${BOLD}${C_SKY}ключи пользователя $t_user:${NC}\n"
                    for l in $LN; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP}${NC}"; done
                    printf "\n"; prompt_user "нажмите [Enter]" wait; fi ;;
            2)  printf "\n"; prompt_user "имя нового пользователя" nname
                if [ -n "$nname" ]; then
                    echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF"
                    log_step "обновление базы данных" "systemctl restart telemt"; sleep 1; fi ;;
            0) break ;;
        esac
    done
}

# [SUB] Раздел НАСТРОЕК
menu_settings() {
    while true; do
        clear; draw_header "НАСТРОЙКИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ОШИБКА: Telemt еще не установлен.${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"; printf "\n"
            prompt_user "назад" act; break
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}журнал событий (логи)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}изменить порт службы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) printf "\n"; journalctl -u telemt -n 50 --no-pager; printf "\n"; prompt_user "нажмите [Enter]" wait ;;
            2) printf "\n"; prompt_user "введите новый порт" nport
               [[ "$nport" =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $nport/" "$T_CONF" && log_step "сохранение" "systemctl restart telemt"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# [SUB] Раздел ZAPRET
menu_zapret() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}установить / обновить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}удалить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) do_install_zapret; printf "\n"; prompt_user "нажмите [Enter] для выхода" wait; break ;;
            2) printf "\n"; log_step "запуск" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; prompt_user "полное удаление zapret из системы? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; log_step "деактивация юнитов" "systemctl stop zapret-tpws && systemctl disable zapret-tpws"
                    log_step "удаление файлов" "rm -rf $Z_DIR $Z_SERVICE"
                    log_step "сброс демонов" "systemctl daemon-reload" && sleep 1; break; fi ;;
            0) break ;;
        esac
    done
}

# [SUB] Раздел ОБСЛУЖИВАНИЯ
menu_maintenance() {
    while true; do
        clear; draw_header "ОБСЛУЖИВАНИЕ МЕНЕДЖЕРА"; echo ""; print_status; echo ""
        local up_rem=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
        local item_1; [[ -n "$up_rem" && "$up_rem" != "$CURRENT_VERSION" ]] && item_1="ОБНОВИТЬ МЕНЕДЖЕР ДО v$up_rem" || item_1="переустановить текущую версию"
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}$item_1${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}удалить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}полная очистка (Telemt+Zapret)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}назад${NC}"
        printf "\n"; prompt_user "действие" act
        case "$act" in
            1) printf "\n"; log_step "скачивание" "curl -sSL -f $REPO_URL -o $CLI_PATH && chmod +x $CLI_PATH"; sleep 1; exec "$CLI_PATH" ;;
            2) printf "\n"; prompt_user "удалить telemt? (y/n)" cf; [[ "$cf" =~ ^[Yy]$ ]] && log_step "очистка" "systemctl stop telemt; rm -rf $T_CONF_DIR $T_BIN $T_SERVICE && systemctl daemon-reload"; sleep 1 ;;
            3) printf "\n"; prompt_user "УНИЧТОЖИТЬ ВСЕ СЕРВИСЫ? (y/n)" cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; systemctl stop telemt zapret-tpws 2>/dev/null
                    rm -rf "$T_CONF_DIR" "$T_BIN" "$T_SERVICE" "$Z_DIR" "$Z_SERVICE" "$CLI_PATH"
                    systemctl daemon-reload; clear; echo -e "${L_IND}${BOLD}${C_RED}Система полностью очищена. Скрипт удален.${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. ГЛАВНЫЙ ЦИКЛ ПРИЛОЖЕНИЯ
# ------------------------------------------------------------------------------
clear
while true; do
    # Мониторинг версии репозитория для главного меню
    remote_v=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    [[ -n "$remote_v" && "$remote_v" != "$CURRENT_VERSION" ]] && marker="${BOLD}${C_SKY} (*)${NC}" || marker=""

    printf "\033[H" # Возврат курсора вверх вместо мерцающего clear
    draw_header "СТАЛИН-3000 (v$CURRENT_VERSION)"
    echo ""; print_status; echo ""

    echo -e "${L_IND}${BOLD}${C_SKY}1 - ${NC}${BOLD}${C_ORANGE}управление сервисом Telemt${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}2 - ${NC}${BOLD}${C_ORANGE}управление пользователями Telemt${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}3 - ${NC}${BOLD}${C_ORANGE}настройки Telemt${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}4 - ${NC}${BOLD}${C_ORANGE}управление Zapret (TPWS)${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}5 - ${NC}${BOLD}${C_ORANGE}обслуживание менеджера$marker${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}0 - ${NC}${BOLD}${C_ORANGE}выход${NC}"
    
    printf "\n"
    prompt_user "выберите раздел" main_sel
    
    case "$main_sel" in
        1) menu_service; clear ;;
        2) menu_users; clear ;;
        3) menu_settings; clear ;;
        4) menu_zapret; clear ;;
        5) menu_maintenance; clear ;;
        0) clear; exit 0 ;;
    esac
done
