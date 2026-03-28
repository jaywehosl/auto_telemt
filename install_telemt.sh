#!/bin/bash

# Пути и переменные
BIN_PATH="/bin/telemt"
CONF_DIR="/etc/telemt"
CONF_FILE="$CONF_DIR/telemt.toml"
SERVICE_FILE="/etc/systemd/system/telemt.service"
CLI_NAME="/usr/local/bin/telemt"
REPO_URL="https://raw.githubusercontent.com/jaywehosl/auto_telemt/main/install_telemt.sh"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Запустите от root (sudo)${NC}"
  exit 1
fi

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

# Функция получения ссылок (с обработкой 0.0.0.0 и ::)
show_links() {
    echo -e "\n${GREEN}=== ТЕКУЩИЕ ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ ===${NC}"
    IP4=$(curl -4 -s --max-time 3 https://api.ipify.org || echo "")
    IP6=$(curl -6 -s --max-time 3 https://api64.ipify.org || echo "")
    
    # Пытаемся взять данные из API
    RAW_DATA=$(curl -s http://127.0.0.1:9091/v1/users)
    LINKS=$(echo "$RAW_DATA" | jq -r '.data[].links.tls[]' 2>/dev/null)
    
    if [ -z "$LINKS" ] || [ "$LINKS" == "null" ]; then
        echo -e "${RED}API не отвечает или пользователей нет. Проверьте: systemctl status telemt${NC}"
    else
        for link in $LINKS; do
            if [[ $link == *"server=0.0.0.0"* ]]; then
                [ -n "$IP4" ] && echo "${link//0.0.0.0/$IP4}"
            elif [[ $link == *"server=::"* ]]; then
                [ -n "$IP6" ] && echo "${link//::/$IP6}"
            else
                echo "$link"
            fi
        done
    fi
}

# Функция скачивания бинарника прокси
download_binary() {
    echo -e "${YELLOW}Скачивание бинарника Telemt...${NC}"
    ARCH=$(uname -m)
    LIBC=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)
    URL="https://github.com/telemt/telemt/releases/latest/download/telemt-$ARCH-linux-$LIBC.tar.gz"
    curl -L "$URL" | tar -xz
    mv telemt $BIN_PATH
    chmod +x $BIN_PATH
}

# --- ОСНОВНАЯ УСТАНОВКА ---

install_telemt() {
    echo -e "${GREEN}Начинаем установку Telemt...${NC}"
    
    # 1. Сбор данных
    read -p "Введите порт для прокси (по умолчанию 443): " PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-443}
    read -p "Введите TLS домен (SNI) (по умолчанию google.com): " TLS_DOMAIN
    TLS_DOMAIN=${TLS_DOMAIN:-google.com}

    # 2. Пакеты
    apt-get update -qq && apt-get install -y curl jq tar openssl net-tools -qq
    
    # 3. Бинарник и юзер
    download_binary
    useradd -d /opt/telemt -m -r -U telemt 2>/dev/null
    mkdir -p $CONF_DIR

    # 4. Конфиг
    cat <<EOF > $CONF_FILE
[general]
use_middle_proxy = false
[general.modes]
classic = false
secure = false
tls = true
[server]
port = $PROXY_PORT
[server.api]
enabled = true
listen = "127.0.0.1:9091"
[censorship]
tls_domain = "$TLS_DOMAIN"
[access.users]
admin = "$(openssl rand -hex 16)"
EOF
    chown -R telemt:telemt $CONF_DIR

    # 5. Systemd сервис
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Telemt Proxy
After=network-online.target
Wants=network-online.target

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
EOF

    # 6. Запуск
    systemctl daemon-reload
    systemctl enable telemt
    systemctl restart telemt

    # 7. РЕГИСТРАЦИЯ КОМАНДЫ 'telemt'
    # Скачиваем сам этот скрипт в /usr/local/bin, чтобы он всегда был доступен
    curl -sSL $REPO_URL -o $CLI_NAME
    chmod +x $CLI_NAME
    
    echo -e "${GREEN}Установка завершена! Команда 'telemt' теперь доступна из любого места.${NC}"
    echo -e "${YELLOW}Запускаю панель управления...${NC}"
    sleep 2
}

# --- МЕНЮ УПРАВЛЕНИЯ ---

run_menu() {
    while true; do
        echo -e "\n${GREEN}=== МЕНЕДЖЕР TELEMT ===${NC}"
        echo "1) Статус сервиса"
        echo "2) Показать ссылки"
        echo "3) Добавить пользователя"
        echo "4) Удалить пользователя"
        echo "5) Сменить порт"
        echo "6) Сменить TLS домен (SNI)"
        echo "7) Перезапустить сервис"
        echo "8) Остановить сервис"
        echo "9) ОБНОВИТЬ СКРИПТ (из GitHub)"
        echo "10) УДАЛИТЬ ВСЁ (Uninstall)"
        echo "0) Выход"
        read -p "Выберите действие: " choice

        case $choice in
            1) systemctl status telemt ;;
            2) show_links ;;
            3)
                read -p "Имя нового пользователя: " NEW_USER
                SECRET=$(openssl rand -hex 16)
                # Добавляем строку в конец файла в секцию users
                echo "$NEW_USER = \"$SECRET\"" >> $CONF_FILE
                systemctl restart telemt
                echo -e "${GREEN}Пользователь $NEW_USER добавлен!${NC}"
                show_links
                ;;
            4)
                echo "Текущие пользователи:"
                grep -A 50 "\[access.users\]" $CONF_FILE | grep "=" | awk '{print $1}'
                read -p "Имя для удаления: " DEL_USER
                sed -i "/^$DEL_USER =/d" $CONF_FILE
                systemctl restart telemt
                echo -e "${RED}Пользователь $DEL_USER удален.${NC}"
                ;;
            5)
                read -p "Новый порт: " NEW_PORT
                sed -i "s/^port = .*/port = $NEW_PORT/" $CONF_FILE
                systemctl restart telemt
                echo -e "${GREEN}Порт изменен на $NEW_PORT${NC}"
                ;;
            6)
                read -p "Новый SNI (напр. apple.com): " NEW_SNI
                sed -i "s/^tls_domain = .*/tls_domain = \"$NEW_SNI\"/" $CONF_FILE
                systemctl restart telemt
                echo -e "${GREEN}SNI изменен на $NEW_SNI${NC}"
                ;;
            7) systemctl restart telemt && echo "Сервис перезапущен." ;;
            8) systemctl stop telemt && echo "Сервис остановлен." ;;
            9) 
                echo "Обновление скрипта..."
                curl -sSL $REPO_URL -o $CLI_NAME
                chmod +x $CLI_NAME
                echo -e "${GREEN}Скрипт обновлен! Перезапустите его командой 'telemt'${NC}"
                exit 0
                ;;
            10)
                read -p "Вы уверены, что хотите удалить ВСЁ? (y/n): " confirm
                if [ "$confirm" == "y" ]; then
                    systemctl stop telemt
                    systemctl disable telemt
                    rm -f $SERVICE_FILE $BIN_PATH $CLI_NAME
                    rm -rf $CONF_DIR /opt/telemt
                    userdel telemt 2>/dev/null
                    echo -e "${RED}Всё успешно удалено.${NC}"
                    exit 0
                fi
                ;;
            0) exit 0 ;;
            *) echo "Неверный ввод." ;;
        esac
    done
}

# --- ТОЧКА ВХОДА ---

# Если бинарник не найден — запускаем установку
if [ ! -f "$BIN_PATH" ]; then
    install_telemt
fi

# После установки (или если уже стоит) — сразу в меню
run_menu
