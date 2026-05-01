#!/bin/bash

# ==============================================================================
# СИСТЕМА УПРАВЛЕНИЯ ПРОКСИ-ИНФРАСТРУКТУРОЙ «СТАЛИН-3000»
# ВЕРСИЯ: 1.8.0 (STABLE BASE)
# ------------------------------------------------------------------------------
# Разработан для автоматизации развертывания Telemt и Zapret (TPWS).
# Архитектура: Линейный интерфейс с фиксацией состояния сервисов.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. КОНФИГУРАЦИЯ СРЕДЫ И СТИЛИСТИЧЕСКИЕ КОНСТАНТЫ
# ------------------------------------------------------------------------------
CURRENT_VERSION="1.8.0"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/refs/heads/main/beta_install.sh"

# Базовая позиция контента (2 пробела)
L_IND="  "

# Цветовая сетка ANSI (Все стили по умолчанию BOLD)
NC='\033[0m'
BOLD='\033[1m'
C_FRAME='\033[1;38;5;148m' # Салатовый (Шапка/Рамки)
C_ORANGE='\033[1;38;5;214m' # Оранжевый (Пункты меню, Промпты)
C_SKY='\033[1;38;5;81m'    # Голубой (Цифры, Маркеры этапов *)
C_GREEN='\033[1;32m'       # Зеленый (Работает, Успех, [y])
C_RED='\033[1;31m'         # Красный (Не установлен, Ошибка, [n])
C_YELLOW='\033[1;33m'      # Желтый (Остановлен)

# Файловые сущности
T_BIN="/bin/telemt"
T_CONF_DIR="/etc/telemt"
T_CONF="$T_CONF_DIR/telemt.toml"
T_SERVICE="/etc/systemd/system/telemt.service"

Z_DIR="/opt/zapret"
Z_SERVICE="/etc/systemd/system/zapret-tpws.service"
CLI_PATH="/usr/local/bin/telemt"

# [Блок защиты]: Проверка на наличие привилегий суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo -e "${BOLD}${C_RED}ОШИБКА: Запуск разрешен только с правами root.${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ВЫВОДА (ИНТЕРФЕЙС)
# ------------------------------------------------------------------------------

# [МЕТОД] draw_header: Отрисовывает центрированный заголовок в рамке
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

# [МЕТОД] print_status: Детекция текущего состояния сервисов в системе
print_status() {
    local s_t s_z c_t c_z
    
    # Логика Telemt
    if [ ! -f "$T_SERVICE" ]; then s_t="не установлен"; c_t="$C_RED"
    elif systemctl is-active --quiet telemt; then s_t="работает"; c_t="$C_GREEN"
    else s_t="остановлен"; c_t="$C_YELLOW"; fi

    # Логика Zapret
    if [ ! -f "$Z_SERVICE" ]; then s_z="не установлен"; c_z="$C_RED"
    elif systemctl is-active --quiet zapret-tpws; then s_z="работает"; c_z="$C_GREEN"
    else s_z="остановлен"; c_z="$C_YELLOW"; fi

    printf "${L_IND}${BOLD}статус Telemt: %b%s${NC}\n" "$c_t" "$s_t"
    printf "${L_IND}${BOLD}статус Zapret: %b%s${NC}\n" "$c_z" "$s_z"
}

# [МЕТОД] log_step: Унифицированный вывод процесса выполнения системной задачи
log_step() {
    printf "${L_IND}${BOLD}${C_SKY}*${NC} ${BOLD}%-35s " "$1..."
    if eval "$2" > /dev/null 2>&1; then
        printf "${BOLD}${C_GREEN}[готово]${NC}\n"; return 0
    else
        printf "${BOLD}${C_RED}[ошибка]${NC}\n"; return 1
    fi
}

# [МЕТОД] msg_final: Итоговое уведомление по завершении блока команд
msg_final() {
    printf "\n${L_IND}${BOLD}${C_GREEN}ok РЕЗУЛЬТАТ: %s${NC}\n" "$1"
}

# ------------------------------------------------------------------------------
# 3. БЭКЕНД: УСТАНОВКА И УДАЛЕНИЕ (ЯДРО СИСТЕМЫ)
# ------------------------------------------------------------------------------

# [ЯДРО] install_telemt: Скачивание бинарников и конфигурация юнитов
do_install_telemt() {
    printf "\n"
    # Сбор данных с использованием промпта
    printf "${L_IND}${BOLD}${C_ORANGE}>> укажите порт (443): ${NC}"; read P_PORT; P_PORT=${P_PORT:-443}
    printf "${L_IND}${BOLD}${C_ORANGE}>> укажите SNI (google.com): ${NC}"; read P_SNI; P_SNI=${P_SNI:-google.com}
    printf "${L_IND}${BOLD}${C_ORANGE}>> имя пользователя: ${NC}"; read P_USER; P_USER=${P_USER:-admin}
    printf "\n"

    log_step "инсталляция системных пакетов" "apt-get update -qq && apt-get install -y curl jq tar openssl -qq"
    
    # Архитектурный расчет
    local ARCH=$(uname -m); local LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    local URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    
    log_step "получение бинарных данных" "curl -L '$URL' | tar -xz && mv telemt $T_BIN && chmod +x $T_BIN"
    
    log_step "генерация конфигурации" "mkdir -p $T_CONF_DIR && cat <<EOF > $T_CONF
[general]
use_middle_proxy = false
[general.modes]
tls = true
[server]
port = $P_PORT
[server.api]
enabled = true
listen = \"127.0.0.1:9091\"
[censorship]
tls_domain = \"$P_SNI\"
[access.users]
$P_USER = \"\$(openssl rand -hex 16)\"
EOF"

    log_step "регистрация юнита telemt" "cat <<EOF > $T_SERVICE
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

    log_step "активация службы" "systemctl daemon-reload && systemctl enable telemt && systemctl restart telemt"
    
    # Финальный вывод ссылок (из 1.3.9)
    printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа:${NC}\n"
    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
    local LNK=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$P_USER\") | .links.tls[]" 2>/dev/null)
    for l in $LNK; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP}${NC}"; done
    msg_final "Telemt готов к работе"
}

# [ЯДРО] install_zapret: Клонирование и компиляция tpws демона
do_install_zapret() {
    printf "\n"
    log_step "зависимости компиляции" "apt-get update -qq && apt-get install -y build-essential libnetfilter-queue-dev libmnl-dev libcap-dev zlib1g-dev git -qq"
    log_step "подготовка репозитория" "rm -rf $Z_DIR && git clone --depth=1 https://github.com/bol-van/zapret.git $Z_DIR"
    log_step "сборка исходного кода (make)" "make -C $Z_DIR"
    
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

    log_step "запуск демона zapret" "systemctl daemon-reload && systemctl enable zapret-tpws && systemctl restart zapret-tpws"
    msg_final "Zapret установлен и настроен на порт 1080"
}

# ------------------------------------------------------------------------------
# 4. ЛОГИКА МЕНЮ И ПОДМЕНЮ (FRONT-END)
# ------------------------------------------------------------------------------

# [ФУНКЦИЯ] Опрос обновления менеджера
get_upd_marker() {
    local rem=$(curl -sSL -f --connect-timeout 2 "${REPO_URL}" | grep "^CURRENT_VERSION=" | head -n 1 | cut -d'"' -f2)
    [[ -n "$rem" && "$rem" != "$CURRENT_VERSION" ]] && U_MARKER="${BOLD}${C_SKY} (*)${NC}" || U_MARKER=""
    R_VER="$rem"
}

# [РАЗДЕЛ]: Обслуживание сервиса Telemt
sub_service() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ TELEMT"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}установить Telemt${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}перезапустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${C_ORANGE}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
        printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> действие: ${NC}"; read sc
        case $sc in
            1) do_install_telemt; printf "\n"; echo -ne "${L_IND}${BOLD}${C_SKY}>> нажмите [Enter]: ${NC}"; read ;;
            2) printf "\n"; log_step "перезагрузка" "systemctl restart telemt"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop telemt"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# [РАЗДЕЛ]: Менеджер пользователей Telemt
sub_users() {
    while true; do
        clear; draw_header "ПОЛЬЗОВАТЕЛИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ОШИБКА: Сервис не установлен.${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
            printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> : ${NC}"; read sc; [[ "$sc" == "0" ]] && break || continue
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}список пользователей и ключи${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}добавить нового пользователя${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
        printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> действие: ${NC}"; read sc
        case $sc in
            1)  printf "\n"; mapfile -t US < <(sed -n '/\[access.users\]/,$p' "$T_CONF" | grep "=" | awk '{print $1}' | sort -u)
                for i in "${!US[@]}"; do printf "${L_IND}${BOLD}${C_SKY}%d - ${C_ORANGE}%s${NC}\n" "$((i+1))" "${US[$i]}"; done
                printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> номер пользователя (0-назад): ${NC}"; read uidx
                if [[ "$uidx" =~ ^[0-9]+$ ]] && [ "$uidx" -gt 0 ] && [ "$uidx" -le "${#US[@]}" ]; then
                    local target="${US[$((uidx-1))]}"
                    local IP=$(curl -4 -s --max-time 2 https://api.ipify.org || echo "0.0.0.0")
                    local LNK=$(curl -s http://127.0.0.1:9091/v1/users | jq -r ".data[] | select(.username == \"$target\") | .links.tls[]" 2>/dev/null)
                    printf "\n${L_IND}${BOLD}${C_SKY}ключи доступа:${NC}\n"
                    for l in $LNK; do echo -e "${L_IND}${BOLD}${C_ORANGE}${l//0.0.0.0/$IP}${NC}"; done
                    printf "\n"; echo -ne "${L_IND}${BOLD}${C_SKY}>> нажмите [Enter]: ${NC}"; read
                fi ;;
            2)  printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> имя: ${NC}"; read nname
                if [ -n "$nname" ]; then
                    echo "$nname = \"$(openssl rand -hex 16)\"" >> "$T_CONF"
                    log_step "обновление базы данных" "systemctl restart telemt"
                fi; sleep 1 ;;
            0) break ;;
        esac
    done
}

# [РАЗДЕЛ]: Конфигурация Telemt
sub_settings() {
    while true; do
        clear; draw_header "НАСТРОЙКИ TELEMT"; echo ""; print_status; echo ""
        if [ ! -f "$T_CONF" ]; then
            echo -e "${L_IND}${BOLD}${C_RED}!! ОШИБКА: Сервис не установлен.${NC}\n"
            echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
            printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> : ${NC}"; read sc; [[ "$sc" == "0" ]] && break || continue
        fi
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}просмотр логов (journalctl)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}изменить порт сервиса${NC}"
        echo -e "${L_IND}${BOLD}0 - ${C_ORANGE}назад${NC}"
        printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> действие: ${NC}"; read sc
        case $sc in
            1) printf "\n"; journalctl -u telemt -n 50 --no-pager; printf "\n"; echo -ne "${L_IND}${BOLD}${C_SKY}>> нажмите [Enter]: ${NC}"; read ;;
            2) printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> новый порт: ${NC}"; read nport
               [[ "$nport" =~ ^[0-9]+$ ]] && sed -i "s/^port = .*/port = $nport/" "$T_CONF" && log_step "перезагрузка" "systemctl restart telemt" && sleep 1 ;;
            0) break ;;
        esac
    done
}

# [РАЗДЕЛ]: Управление подсистемой Zapret
sub_zapret() {
    while true; do
        clear; draw_header "УПРАВЛЕНИЕ ZAPRET"; echo ""; print_status; echo ""
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}установить / обновить Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}запустить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${C_ORANGE}остановить службу${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}4 - ${C_ORANGE}полное удаление Zapret${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
        printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> действие: ${NC}"; read sc
        case $sc in
            1) do_install_zapret; printf "\n"; echo -ne "${L_IND}${BOLD}${C_SKY}>> нажмите [Enter]: ${NC}"; read ;;
            2) printf "\n"; log_step "запуск" "systemctl start zapret-tpws"; sleep 1 ;;
            3) printf "\n"; log_step "остановка" "systemctl stop zapret-tpws"; sleep 1 ;;
            4) printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> удалить Zapret из системы? [${C_GREEN}y${NC}/${C_RED}n${NC}]: "; read cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    log_step "деактивация юнитов" "systemctl stop zapret-tpws && systemctl disable zapret-tpws"
                    log_step "удаление файлов" "rm -rf $Z_DIR $Z_SERVICE && systemctl daemon-reload"
                    msg_final "Zapret удален" && sleep 1; fi ;;
            0) break ;;
        esac
    done
}

# [РАЗДЕЛ]: Сервисное обслуживание и самообновление
sub_maint() {
    while true; do
        clear; draw_header "ОБСЛУЖИВАНИЕ"; echo ""; print_status; echo ""
        local text_upd; [[ -n "$U_MARKER" ]] && text_upd="ОБНОВИТЬ МЕНЕДЖЕР ДО v$R_VER" || text_upd="переустановить текущую версию v$CURRENT_VERSION"
        echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}$text_upd${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}удалить Telemt из системы${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}3 - ${C_ORANGE}полная очистка (Telemt + Zapret)${NC}"
        echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}назад${NC}"
        printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> действие: ${NC}"; read sc
        case $sc in
            1) printf "\n"; log_step "загрузка файла" "curl -sSL -f $REPO_URL -o $CLI_PATH && chmod +x $CLI_PATH"
               log_step "перезапуск..." "sleep 1"; exec "$CLI_PATH" ;;
            2) printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> удалить Telemt и данные? [${C_GREEN}y${NC}/${C_RED}n${NC}]: "; read cf
               [[ "$cf" =~ ^[Yy]$ ]] && log_step "очистка" "systemctl stop telemt; rm -rf $T_CONF_DIR $T_BIN $T_SERVICE && systemctl daemon-reload"; sleep 1 ;;
            3) printf "\n"; echo -ne "${L_IND}${BOLD}${C_ORANGE}>> ТОТАЛЬНОЕ УДАЛЕНИЕ ВСЕХ СИСТЕМ? [${C_GREEN}y${NC}/${C_RED}n${NC}]: "; read cf
               if [[ "$cf" =~ ^[Yy]$ ]]; then
                    printf "\n"; systemctl stop telemt zapret-tpws 2>/dev/null
                    rm -rf "$T_CONF_DIR" "$T_BIN" "$T_SERVICE" "$Z_DIR" "$Z_SERVICE" "$CLI_PATH"
                    systemctl daemon-reload; clear; echo -e "${L_IND}${BOLD}${C_RED}Все системы удалены. До свидания.${NC}"; exit 0; fi ;;
            0) break ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 5. ГЛАВНЫЙ ОПЕРАЦИОННЫЙ ЦИКЛ (RUNTIME)
# ------------------------------------------------------------------------------
clear
while true; do
    get_upd_marker # Мониторинг репозитория
    draw_header "$L_MENU_HEADER (v$CURRENT_VERSION)"
    echo ""; print_status; echo ""

    echo -e "${L_IND}${BOLD}${C_SKY}1 - ${C_ORANGE}$L_MAIN_1${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}2 - ${C_ORANGE}$L_MAIN_2${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}3 - ${C_ORANGE}$L_MAIN_3${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}4 - ${C_ORANGE}$L_MAIN_4${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}5 - ${C_ORANGE}$L_MAIN_5$U_MARKER${NC}"
    echo -e "${L_IND}${BOLD}${C_SKY}0 - ${C_ORANGE}$L_MAIN_0${NC}"
    
    printf "\n"
    echo -ne "${L_IND}${BOLD}${C_ORANGE}>> выберите раздел: ${NC}"
    # Обычный read обеспечивает идеальную работу клавиатуры и полей ввода.
    read -r sc
    
    case $sc in
        1) sub_service ;;
        2) sub_users ;;
        3) sub_settings ;;
        4) sub_zapret ;;
        5) sub_maint ;;
        0) clear; exit 0 ;;
    esac
done
