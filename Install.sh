#!/bin/bash

# Скрипт для создания tg.sh и настройки avreg

# Функция запроса данных для tg.sh
request_data() {
    echo "Введите токен вашего бота в Telegram:"
    read BOT_TOKEN
    echo "Введите ID чата или канала в Telegram:"
    read CHAT_ID
    echo "Введите номер камеры:"
    read camera_num
    echo "Введите ваш логин в Avreg:"
    read login
    echo "Введите URL сервера avreg (нажмите Enter для использования localhost):"
    read AVREG_URL
    AVREG_URL=\${AVREG_URL:-localhost}

    # Создание файла tg.sh с полученными данными
    cat <<EOF > /etc/avreg/scripts/tg.sh
#!/bin/bash

# Токен бота и ID чата
BOT_TOKEN='$BOT_TOKEN'
CHAT_ID='$CHAT_ID'
# Номер камеры, логин и URL сервера avreg
camera_num=$camera_num
login="$login"
AVREG_URL='$AVREG_URL'

# Кодирование логина и пустого пароля в формате Base64
auth_value=\$(echo -n "\${login}:" | base64)

# URL для запроса изображения
url="http://\${AVREG_URL}:874/avreg-cgi/jpg/image.cgi?camera=\${camera_num}&ab=\${auth_value}"
IMAGE_FILE="cam\${camera_num}.jpg"

# Функция для получения изображения
get_image() {
    wget -S "\$url" -O \$IMAGE_FILE
}

# Функция для отправки уведомления в Telegram
send_telegram() {
    get_image
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendMessage" \
    -d chat_id=\$CHAT_ID \
    -d text="Движение обнаружено." >> /tmp/telegram_log.txt 2>&1
    curl -s -X POST "https://api.telegram.org/bot\$BOT_TOKEN/sendPhoto" \
    -F chat_id=\$CHAT_ID \
    -F photo=@\$IMAGE_FILE >> /tmp/telegram_log.txt 2>&1
    rm \$IMAGE_FILE
}

EOF

    # Настройка прав доступа для tg.sh
    sudo chown root:root /etc/avreg/scripts/tg.sh
    sudo chmod 0755 /etc/avreg/scripts/tg.sh
}

# Функция настройки конфигурационного файла avreg
setup_avreg() {
    # Копирование и распаковка event-collector
    cd /etc/avreg/scripts
    sudo cp /usr/share/doc/avregd/examples/event-collector.gz /etc/avreg/scripts
    sudo gunzip event-collector.gz

    # Настройка прав доступа
    sudo chown root:root /etc/avreg/scripts/event-collector
    sudo chmod 0755 /etc/avreg/scripts/event-collector

    # Добавление вызова tg.sh в event-collector
    sed -i '/log debug "cam\[\$cam_nr\]: #\$session_nr motion session \$status at \$dt_event (diff: \$diff\/\$threshold;.......)/a exec "/etc/avreg/scripts/tg.sh"' /etc/avreg/scripts/event-collector
}

# Вызов функций
request_data
setup_avreg

# Перезапуск сервера avreg
sudo service avregd restart
