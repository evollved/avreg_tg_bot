#!/bin/bash

# Скрипт для создания tg.sh и настройки avreg

CONFIG_FILE="/etc/avreg/scripts/telegram_config.sh"
SCRIPT_FILE="/etc/avreg/scripts/tg.sh"
CONFIG_EDITOR="/etc/avreg/scripts/edit_telegram_config.sh"
EVENT_COLLECTOR="/etc/avreg/scripts/event-collector"
EVENT_COLLECTOR_SOURCE="/usr/share/doc/avreg/examples/event-collector.gz"
EVENT_COLLECTOR_SOURCE_ALT="/usr/share/doc/avregd/examples/event-collector.gz"
VIDEO_MAX_SIZE_MB=45
VIDEO_MAX_SIZE=$((VIDEO_MAX_SIZE_MB * 1024 * 1024))
AVREG_USER="avreg"
AVREG_GROUP="avreg"

# Функция проверки и установки ffmpeg
check_and_install_ffmpeg() {
    if ! command -v ffmpeg &> /dev/null; then
        echo ""
        echo "⚠️  ffmpeg не установлен. Он рекомендуется для правильной работы с видео."
        echo "   Без ffmpeg видео будет отправляться как документ в формате MJPG."
        echo ""
        
        read -p "Установить ffmpeg сейчас? (y/n): " install_choice
        if [[ $install_choice =~ ^[Yy]$ ]]; then
            echo "Попытка установки ffmpeg..."
            
            # Определяем дистрибутив
            if command -v apt-get &> /dev/null; then
                echo "Обнаружен Debian/Ubuntu, использую apt-get..."
                sudo apt-get update
                sudo apt-get install -y ffmpeg
            elif command -v yum &> /dev/null; then
                echo "Обнаружен CentOS/RHEL, использую yum..."
                sudo yum install -y ffmpeg ffmpeg-devel
            elif command -v dnf &> /dev/null; then
                echo "Обнаружен Fedora, использую dnf..."
                sudo dnf install -y ffmpeg
            elif command -v pacman &> /dev/null; then
                echo "Обнаружен Arch Linux, использую pacman..."
                sudo pacman -Sy ffmpeg --noconfirm
            elif command -v zypper &> /dev/null; then
                echo "Обнаружен openSUSE, использую zypper..."
                sudo zypper install -y ffmpeg
            else
                echo "❌ Не удалось определить пакетный менеджер"
                echo "Установите ffmpeg вручную:"
                echo "  Debian/Ubuntu: sudo apt-get install ffmpeg"
                echo "  CentOS/RHEL: sudo yum install ffmpeg"
                echo "  Arch: sudo pacman -S ffmpeg"
                return 1
            fi
            
            # Проверяем установку
            if command -v ffmpeg &> /dev/null; then
                echo "✅ ffmpeg успешно установлен"
                return 0
            else
                echo "❌ Не удалось установить ffmpeg"
                echo "Установите ffmpeg вручную позже"
                return 1
            fi
        else
            echo "⚠️  ffmpeg не будет установлен. Видео будет отправляться как документ."
            return 1
        fi
    else
        echo "✅ ffmpeg уже установлен"
        return 0
    fi
}

# Функция проверки доступа бота
check_bot_access() {
    local BOT_TOKEN="$1"
    local CHAT_ID="$2"
    
    echo "Проверка доступа бота..."
    
    # Проверка токена бота
    local bot_info=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
    if echo "$bot_info" | grep -q '"ok":true'; then
        local bot_name=$(echo "$bot_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo "✅ Бот @${bot_name} доступен"
    else
        echo "❌ Ошибка: Неверный токен бота или бот не существует"
        echo "Ответ от Telegram: $bot_info"
        return 1
    fi
    
    # Проверка доступа к чату
    if [ -n "$CHAT_ID" ] && [ "$CHAT_ID" != "ВАШ_CHAT_ID_ЗДЕСЬ" ]; then
        local chat_info=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getChat?chat_id=${CHAT_ID}")
        if echo "$chat_info" | grep -q '"ok":true'; then
            local chat_title=$(echo "$chat_info" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
            local chat_type=$(echo "$chat_info" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
            echo "✅ Доступ к чату получен: ${chat_title} (${chat_type})"
            return 0
        else
            echo "⚠️  Не удалось получить информацию о чате. Убедитесь что:"
            echo "   1. Бот добавлен в чат/канал"
            echo "   2. Для каналов: бот должен быть администратором"
            echo "   3. ID чата указан верно"
            echo "   4. Для личных сообщений: сначала напишите боту /start"
            echo "Ответ от Telegram: $chat_info"
            
            # Предлагаем отправить тестовое сообщение
            read -p "Отправить тестовое сообщение в чат? (y/n): " send_test
            if [[ $send_test =~ ^[Yy]$ ]]; then
                local test_result=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                    -d "chat_id=${CHAT_ID}" \
                    -d "text=✅ Тестовое сообщение от бота. Если вы видите это, все настроено правильно!")
                
                if echo "$test_result" | grep -q '"ok":true'; then
                    echo "✅ Тестовое сообщение отправлено успешно!"
                    return 0
                else
                    echo "❌ Ошибка отправки тестового сообщения: $test_result"
                    return 1
                fi
            fi
            return 1
        fi
    else
        echo "⚠️  CHAT_ID не указан"
        return 1
    fi
}

# Функция получения ID чата через бота
get_chat_id_via_bot() {
    local BOT_TOKEN="$1"
    
    echo ""
    echo "Для получения ID чата:"
    echo "1. Добавьте бота в нужный чат/канал"
    echo "2. Для каналов: сделайте бота администратором"
    echo "3. Отправьте любое сообщение в чат"
    echo "4. ИЛИ для каналов: перешлите сообщение из канала боту"
    echo ""
    echo "Затем выполните:"
    echo "curl -s https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
    echo ""
    echo "В выводе найдите 'chat':{'id':XXXXX}"
    echo ""
    
    read -p "Введите ID чата вручную или оставьте пустым для пропуска: " manual_chat_id
    echo "$manual_chat_id"
}

# Функция запроса данных для конфигурации
request_config() {
    echo "=== Настройка Telegram уведомлений для Avreg ==="
    echo ""
    
    # Запрос токена бота
    while true; do
        echo "Введите токен вашего бота в Telegram:"
        echo "(например: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
        read BOT_TOKEN
        
        if [ -z "$BOT_TOKEN" ]; then
            echo "Токен не может быть пустым"
            continue
        fi
        
        # Базовая проверка формата токена
        if [[ ! "$BOT_TOKEN" =~ ^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$ ]]; then
            echo "⚠️  Формат токена выглядит нестандартно. Продолжить? (y/n): "
            read confirm
            if [[ ! $confirm =~ ^[Yy]$ ]]; then
                continue
            fi
        fi
        
        break
    done
    
    echo ""
    echo "=== Настройка камер ==="
    echo ""
    
    # Запрос количества камер
    while true; do
        echo "Введите количество камер для настройки (1-20):"
        read CAMERA_COUNT
        if [[ "$CAMERA_COUNT" =~ ^[0-9]+$ ]] && [ "$CAMERA_COUNT" -ge 1 ] && [ "$CAMERA_COUNT" -le 20 ]; then
            break
        else
            echo "❌ Неверное количество. Введите число от 1 до 20"
        fi
    done
    
    # Массивы для хранения настроек камер
    declare -a CAMERA_NUMS
    declare -a CAMERA_CHAT_IDS
    declare -a CAMERA_MEDIA_TYPES
    declare -a CAMERA_VIDEO_DURATIONS
    declare -a CAMERA_VIDEO_FPS
    
    # Настройка для каждой камеры
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        echo ""
        echo "=== Камера $i ==="
        
        # Номер камеры в базе
        while true; do
            echo "Введите номер камеры $i в базе Avreg (обычно 1, 2, 3...):"
            read CAMERA_NUM
            if [[ "$CAMERA_NUM" =~ ^[0-9]+$ ]] && [ "$CAMERA_NUM" -ge 1 ]; then
                CAMERA_NUMS[$i]=$CAMERA_NUM
                break
            else
                echo "❌ Неверный номер камеры"
            fi
        done
        
        # Настройка чата для камеры
        echo ""
        echo "Настройка чата для камеры $CAMERA_NUM:"
        CHAT_ID=""
        while true; do
            echo "Выберите способ указания чата для камеры $CAMERA_NUM:"
            echo "1) Ввести ID чата вручную"
            echo "2) Получить ID через бота"
            echo "3) Использовать общий чат (будет настроен позже)"
            echo "4) Пропустить и настроить позже"
            read -p "Ваш выбор (1-4): " chat_choice
            
            case $chat_choice in
                1)
                    echo ""
                    echo "Введите ID чата или канала для камеры $CAMERA_NUM:"
                    echo "(ID чата обычно отрицательный для групп/каналов, например: -1001234567890)"
                    echo "(ID пользователя положительный, например: 123456789)"
                    read CHAT_ID
                    
                    if check_bot_access "$BOT_TOKEN" "$CHAT_ID"; then
                        CAMERA_CHAT_IDS[$i]=$CHAT_ID
                        break
                    else
                        echo "Попробовать другой способ?"
                        continue
                    fi
                    ;;
                2)
                    CHAT_ID=$(get_chat_id_via_bot "$BOT_TOKEN")
                    if [ -n "$CHAT_ID" ]; then
                        if check_bot_access "$BOT_TOKEN" "$CHAT_ID"; then
                            CAMERA_CHAT_IDS[$i]=$CHAT_ID
                            break
                        fi
                    fi
                    ;;
                3)
                    echo "Используется общий чат (будет настроен позже)"
                    CAMERA_CHAT_IDS[$i]="ОБЩИЙ_ЧАТ"
                    break
                    ;;
                4)
                    echo "Пропускаем настройку чата для камеры $CAMERA_NUM"
                    CAMERA_CHAT_IDS[$i]="ВАШ_CHAT_ID_ЗДЕСЬ"
                    break
                    ;;
                *)
                    echo "Неверный выбор"
                    ;;
            esac
        done
        
        # Настройка типа медиа для камеры
        echo ""
        echo "Выберите тип отправляемых медиа для камеры $CAMERA_NUM:"
        echo "1) Только фото"
        echo "2) Только видео"
        echo "3) Фото и видео"
        read -p "Введите номер варианта (1-3): " media_choice
        
        case $media_choice in
            1) MEDIA_TYPE="photo" ;;
            2) MEDIA_TYPE="video" ;;
            3) MEDIA_TYPE="both" ;;
            *) MEDIA_TYPE="photo" ;;
        esac
        CAMERA_MEDIA_TYPES[$i]=$MEDIA_TYPE
        
        # Длительность видео для камеры
        echo ""
        echo "Введите длительность видео для захвата с камеры $CAMERA_NUM (в секундах, минимум 5):"
        read VIDEO_DURATION
        VIDEO_DURATION=${VIDEO_DURATION:-10}
        if [ $VIDEO_DURATION -lt 5 ]; then
            VIDEO_DURATION=5
        fi
        CAMERA_VIDEO_DURATIONS[$i]=$VIDEO_DURATION
        
        # FPS для видео
        echo ""
        echo "Введите FPS для видео (качество, 1-30, по умолчанию 5):"
        read VIDEO_FPS
        VIDEO_FPS=${VIDEO_FPS:-5}
        if [ $VIDEO_FPS -lt 1 ]; then
            VIDEO_FPS=1
        elif [ $VIDEO_FPS -gt 30 ]; then
            VIDEO_FPS=30
        fi
        CAMERA_VIDEO_FPS[$i]=$VIDEO_FPS
    done
    
    # Настройка общего чата (если есть камеры с "ОБЩИЙ_ЧАТ")
    GENERAL_CHAT_ID=""
    if [[ " ${CAMERA_CHAT_IDS[@]} " =~ "ОБЩИЙ_ЧАТ" ]]; then
        echo ""
        echo "=== Настройка общего чата ==="
        
        while true; do
            echo "Выберите способ указания общего чата:"
            echo "1) Ввести ID общего чата вручную"
            echo "2) Получить ID через бота"
            echo "3) Пропустить и настроить позже"
            read -p "Ваш выбор (1-3): " general_chat_choice
            
            case $general_chat_choice in
                1)
                    echo ""
                    echo "Введите ID общего чата или канала:"
                    read GENERAL_CHAT_ID
                    
                    if check_bot_access "$BOT_TOKEN" "$GENERAL_CHAT_ID"; then
                        # Заменяем "ОБЩИЙ_ЧАТ" на реальный ID
                        for ((i=1; i<=$CAMERA_COUNT; i++)); do
                            if [ "${CAMERA_CHAT_IDS[$i]}" = "ОБЩИЙ_ЧАТ" ]; then
                                CAMERA_CHAT_IDS[$i]=$GENERAL_CHAT_ID
                            fi
                        done
                        break
                    fi
                    ;;
                2)
                    GENERAL_CHAT_ID=$(get_chat_id_via_bot "$BOT_TOKEN")
                    if [ -n "$GENERAL_CHAT_ID" ]; then
                        if check_bot_access "$BOT_TOKEN" "$GENERAL_CHAT_ID"; then
                            # Заменяем "ОБЩИЙ_ЧАТ" на реальный ID
                            for ((i=1; i<=$CAMERA_COUNT; i++)); do
                                if [ "${CAMERA_CHAT_IDS[$i]}" = "ОБЩИЙ_ЧАТ" ]; then
                                    CAMERA_CHAT_IDS[$i]=$GENERAL_CHAT_ID
                                fi
                            done
                            break
                        fi
                    fi
                    ;;
                3)
                    echo "Пропускаем настройку общего чата"
                    # Оставляем "ОБЩИЙ_ЧАТ" как есть
                    break
                    ;;
                *)
                    echo "Неверный выбор"
                    ;;
            esac
        done
    fi
    
    # Остальные настройки
    echo ""
    echo "Введите ваш логин в Avreg:"
    read login
    login=${login:-admin}
    
    echo ""
    echo "Введите пароль для Avreg (оставьте пустым если не требуется):"
    read -s avreg_password
    echo ""
    
    echo ""
    echo "Введите URL сервера avreg (нажмите Enter для использования localhost):"
    read AVREG_URL
    AVREG_URL=${AVREG_URL:-localhost}
    
    # Проверка доступности Avreg
    echo ""
    echo "Проверка доступности Avreg на ${AVREG_URL}:874..."
    if timeout 5 curl -s "http://${AVREG_URL}:874" > /dev/null; then
        echo "✅ Avreg доступен"
    else
        echo "⚠️  Не удалось подключиться к Avreg. Проверьте URL и порт 874"
    fi
    
    # Создание конфигурационного файла
    cat <<EOF > "$CONFIG_FILE"
#!/bin/bash
# Конфигурация Telegram бота для Avreg
# Файл создан: $(date)

# Данные бота Telegram
BOT_TOKEN='$BOT_TOKEN'

# Количество камер
CAMERA_COUNT=$CAMERA_COUNT

# Массивы с настройками камер
EOF

    # Добавляем массивы камер в конфиг
    echo "declare -a CAMERA_NUMS=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_NUMS[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_NUMS[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_CHAT_IDS=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_CHAT_IDS[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_CHAT_IDS[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_MEDIA_TYPES=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_MEDIA_TYPES[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_MEDIA_TYPES[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_VIDEO_DURATIONS=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_VIDEO_DURATIONS[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_VIDEO_DURATIONS[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_VIDEO_FPS=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_VIDEO_FPS[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_VIDEO_FPS[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    cat <<EOF >> "$CONFIG_FILE"

# Функция получения настроек камеры по номеру в базе
get_camera_config() {
    local camera_num=\$1
    local camera_index=-1
    
    # Ищем индекс камеры в массиве
    for ((i=0; i<\$CAMERA_COUNT; i++)); do
        if [ "\${CAMERA_NUMS[\$i]}" = "\$camera_num" ]; then
            camera_index=\$i
            break
        fi
    done
    
    if [ \$camera_index -eq -1 ]; then
        echo "Ошибка: Камера \$camera_num не найдена в конфигурации" >&2
        return 1
    fi
    
    # Экспортируем настройки для камеры
    export CHAT_ID="\${CAMERA_CHAT_IDS[\$camera_index]}"
    export MEDIA_TYPE="\${CAMERA_MEDIA_TYPES[\$camera_index]}"
    export VIDEO_DURATION="\${CAMERA_VIDEO_DURATIONS[\$camera_index]}"
    export VIDEO_FPS="\${CAMERA_VIDEO_FPS[\$camera_index]}"
    
    return 0
}

# Данные для доступа к Avreg
login="$login"
avreg_password="$avreg_password"
AVREG_URL='$AVREG_URL'

# Общие настройки
VIDEO_MAX_SIZE=$VIDEO_MAX_SIZE  # максимальный размер видео для отправки как фото (45 MB)

# Пути к файлам
TEMP_DIR="/tmp/avreg_telegram"
LOG_FILE="/tmp/telegram_bot.log"

EOF

    echo ""
    echo "✅ Конфигурация сохранена в $CONFIG_FILE"
}

# Функция создания основного скрипта
create_script() {
    cat <<'EOF' > "$SCRIPT_FILE"
#!/bin/bash

# Загрузка конфигурации
if [ -f /etc/avreg/scripts/telegram_config.sh ]; then
    source /etc/avreg/scripts/telegram_config.sh
else
    echo "Ошибка: Конфигурационный файл не найден!" >&2
    exit 1
fi

# Проверка обязательных параметров
if [ -z "$BOT_TOKEN" ] || [ "$BOT_TOKEN" = "ВАШ_BOT_TOKEN_ЗДЕСЬ" ]; then
    echo "Ошибка: BOT_TOKEN не настроен!" >&2
    exit 1
fi

# Получение номера камеры из аргумента
if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    camera_num="$1"
else
    echo "Использование: $0 <номер_камеры_в_базе>" >&2
    echo "Пример: $0 1" >&2
    echo "" >&2
    echo "Доступные камеры в конфигурации:" >&2
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "  Камера ${CAMERA_NUMS[$i]}: Чат ${CAMERA_CHAT_IDS[$i]}, Тип: ${CAMERA_MEDIA_TYPES[$i]}" >&2
    done
    exit 1
fi

# Загрузка настроек для конкретной камеры
if ! get_camera_config "$camera_num"; then
    exit 1
fi

# Проверка настроек чата
if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "ВАШ_CHAT_ID_ЗДЕСЬ" ] || [ "$CHAT_ID" = "ОБЩИЙ_ЧАТ" ]; then
    echo "Ошибка: CHAT_ID для камеры $camera_num не настроен!" >&2
    echo "Настройте чат для камеры $camera_num в конфигурационном файле" >&2
    exit 1
fi

# Создание временной директории
mkdir -p "$TEMP_DIR"

# Генерация имен файлов с учетом номера камеры
timestamp=$(date +%s)
IMAGE_FILE="${TEMP_DIR}/cam${camera_num}_${timestamp}.jpg"
VIDEO_FILE="${TEMP_DIR}/cam${camera_num}_${timestamp}.mjpg"
CONVERTED_VIDEO_FILE="${TEMP_DIR}/cam${camera_num}_${timestamp}.mp4"

# Логирование
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Камера $camera_num - $1" >> "$LOG_FILE"
    echo "Камера $camera_num: $1" >&2  # Также выводим в stderr для systemd журнала
}

# Проверка доступности Telegram API
check_telegram_api() {
    local response=$(curl -s -w "%{http_code}" "https://api.telegram.org/bot${BOT_TOKEN}/getMe" -o /dev/null)
    if [ "$response" != "200" ]; then
        log_message "❌ Ошибка доступа к Telegram API (HTTP код: $response)"
        return 1
    fi
    return 0
}

# Кодирование логина и пароля для авторизации
get_auth_header() {
    if [ -n "$avreg_password" ]; then
        echo -n "${login}:${avreg_password}"
    else
        echo -n "${login}:"
    fi | base64 -w 0
}

# Функция для получения изображения с камеры
get_image() {
    local auth_value=$(get_auth_header)
    local url="http://${AVREG_URL}:874/avreg-cgi/jpg/image.cgi?camera=${camera_num}&ab=${auth_value}"
    
    log_message "Запрос изображения с камеры $camera_num"
    
    # Используем wget с таймаутом
    wget --timeout=10 --tries=2 -q "$url" -O "$IMAGE_FILE" 2>> "$LOG_FILE"
    local wget_status=$?
    
    if [ $wget_status -eq 0 ] && [ -f "$IMAGE_FILE" ] && [ -s "$IMAGE_FILE" ]; then
        local file_size=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || echo "0")
        log_message "✅ Изображение получено: $IMAGE_FILE (${file_size} байт)"
        
        # Проверяем, что это действительно изображение
        if file "$IMAGE_FILE" | grep -q "image"; then
            return 0
        else
            log_message "⚠️  Полученный файл не является изображением"
            return 1
        fi
    else
        log_message "❌ Ошибка получения изображения (код: $wget_status)"
        return 1
    fi
}

# Функция для получения видео с камеры через MJPG поток
get_video() {
    local auth_value=$(get_auth_header)
    
    log_message "Запрос MJPG потока с камеры $camera_num (длительность: ${VIDEO_DURATION}сек, FPS: ${VIDEO_FPS})"
    
    # URL для MJPG потока
    local mjpg_url="http://${AVREG_URL}:874/avreg-cgi/mjpg/video.cgi?camera=${camera_num}"
    
    # Добавляем параметр fps
    mjpg_url="${mjpg_url}&fps=${VIDEO_FPS}"
    
    # Добавляем аутентификацию
    mjpg_url="${mjpg_url}&ab=${auth_value}"
    
    log_message "URL MJPG потока: $(echo $mjpg_url | sed 's/ab=[^&]*/ab=***/')"
    
    # Удаляем старые временные файлы если есть
    rm -f "$VIDEO_FILE" "$CONVERTED_VIDEO_FILE" 2>/dev/null
    
    # Захватываем MJPG поток через curl с таймаутом
    log_message "Захват MJPG потока..."
    timeout ${VIDEO_DURATION} curl -s "$mjpg_url" > "$VIDEO_FILE" 2>> "$LOG_FILE"
    local curl_status=$?
    
    if [ ! -f "$VIDEO_FILE" ] || [ ! -s "$VIDEO_FILE" ]; then
        log_message "❌ Не удалось получить MJPG поток (статус curl: $curl_status)"
        return 1
    fi
    
    local mjpg_size=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
    log_message "✅ MJPG поток сохранен: $VIDEO_FILE (${mjpg_size} байт)"
    
    # Проверяем, является ли файл валидным MJPG
    if ! file "$VIDEO_FILE" | grep -q "JPEG" && ! file "$VIDEO_FILE" | grep -q "MJPG" && ! file "$VIDEO_FILE" | grep -q "MPEG"; then
        log_message "⚠️  Полученный файл может не быть валидным MJPG потоком"
        # Не прерываем - возможно все равно можно конвертировать
    fi
    
    # Конвертируем MJPG в MP4 если установлен ffmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        log_message "Конвертация MJPG в MP4 через ffmpeg..."
        
        # Определяем FPS для конвертации
        local fps_for_conversion=$VIDEO_FPS
        if [ $fps_for_conversion -lt 1 ]; then
            fps_for_conversion=1
        elif [ $fps_for_conversion -gt 30 ]; then
            fps_for_conversion=30
        fi
        
        # Конвертируем MJPG в MP4
        ffmpeg -y \
            -loglevel error \
            -f mjpeg \
            -r ${fps_for_conversion} \
            -i "$VIDEO_FILE" \
            -c:v libx264 \
            -preset ultrafast \
            -crf 28 \
            -pix_fmt yuv420p \
            -r ${fps_for_conversion} \
            -f mp4 \
            "$CONVERTED_VIDEO_FILE" 2>> "$LOG_FILE"
        
        local ffmpeg_status=$?
        
        if [ $ffmpeg_status -eq 0 ] && [ -f "$CONVERTED_VIDEO_FILE" ] && [ -s "$CONVERTED_VIDEO_FILE" ]; then
            local mp4_size=$(stat -c%s "$CONVERTED_VIDEO_FILE" 2>/dev/null || echo "0")
            log_message "✅ Видео сконвертировано в MP4: $CONVERTED_VIDEO_FILE (${mp4_size} байт, сжатие: $((mjpg_size - mp4_size)) байт)"
            
            # Удаляем оригинальный MJPG файл если конвертация успешна
            rm -f "$VIDEO_FILE" 2>/dev/null
            
            # Используем конвертированный файл для отправки
            VIDEO_FILE="$CONVERTED_VIDEO_FILE"
            return 0
        else
            log_message "⚠️  Ошибка конвертации через ffmpeg (код: $ffmpeg_status), используем оригинальный MJPG"
            
            # Если конвертация не удалась, проверяем размер MJPG файла
            if [ $mjpg_size -gt $VIDEO_MAX_SIZE ]; then
                log_message "⚠️  MJPG файл слишком большой ($mjpg_size байт), попытка уменьшить через ffmpeg..."
                
                # Пробуем другой способ конвертации
                ffmpeg -y \
                    -loglevel error \
                    -i "$VIDEO_FILE" \
                    -t $((VIDEO_DURATION > 60 ? 60 : VIDEO_DURATION)) \
                    -c:v libx264 \
                    -preset ultrafast \
                    -crf 32 \
                    -pix_fmt yuv420p \
                    -f mp4 \
                    "$CONVERTED_VIDEO_FILE" 2>> "$LOG_FILE"
                
                if [ $? -eq 0 ] && [ -f "$CONVERTED_VIDEO_FILE" ] && [ -s "$CONVERTED_VIDEO_FILE" ]; then
                    local reduced_size=$(stat -c%s "$CONVERTED_VIDEO_FILE" 2>/dev/null || echo "0")
                    log_message "✅ Видео уменьшено: $CONVERTED_VIDEO_FILE (${reduced_size} байт)"
                    rm -f "$VIDEO_FILE" 2>/dev/null
                    VIDEO_FILE="$CONVERTED_VIDEO_FILE"
                    return 0
                fi
            fi
            
            # Используем оригинальный MJPG файл
            return 0
        fi
    else
        log_message "⚠️  ffmpeg не установлен, используем оригинальный MJPG файл"
        
        # Проверяем размер файла
        if [ $mjpg_size -gt $VIDEO_MAX_SIZE ]; then
            log_message "⚠️  MJPG файл слишком большой ($mjpg_size байт > $VIDEO_MAX_SIZE байт)"
            log_message "   Установите ffmpeg для автоматического сжатия видео"
        fi
        
        return 0
    fi
}

# Функция для отправки сообщения в Telegram
send_telegram_message() {
    local message="$1"
    
    if ! check_telegram_api; then
        log_message "❌ Невозможно отправить сообщение: Telegram API недоступен"
        return 1
    fi
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${message}\"}" \
        -w "%{http_code}")
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "✅ Сообщение отправлено: ${message:0:50}..."
        return 0
    else
        log_message "❌ Ошибка отправки сообщения"
        log_message "   HTTP код: $http_code"
        log_message "   Ответ: $json_response"
        
        # Анализ ошибки
        if echo "$json_response" | grep -q '"error_code":400'; then
            log_message "   Проблема: Неверный запрос (возможно неверный CHAT_ID)"
        elif echo "$json_response" | grep -q '"error_code":401'; then
            log_message "   Проблема: Неверный токен бота"
        elif echo "$json_response" | grep -q '"error_code":403'; then
            log_message "   Проблема: Бот заблокирован пользователем или не в чате"
        elif echo "$json_response" | grep -q '"error_code":404'; then
            log_message "   Проблема: Чат не найден"
        fi
        
        return 1
    fi
}

# Функция для отправки фото в Telegram
send_telegram_photo() {
    if [ ! -f "$IMAGE_FILE" ] || [ ! -s "$IMAGE_FILE" ]; then
        log_message "⚠️  Файл изображения не существует или пуст"
        return 1
    fi
    
    if ! check_telegram_api; then
        return 1
    fi
    
    log_message "Отправка фото в Telegram..."
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        -F "chat_id=${CHAT_ID}" \
        -F "photo=@${IMAGE_FILE}" \
        -F "caption=📸 Камера ${camera_num}: Движение обнаружено ($(date '+%Y-%m-%d %H:%M:%S'))" \
        -w "%{http_code}")
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "✅ Фото успешно отправлено"
        return 0
    else
        log_message "❌ Ошибка отправки фото"
        log_message "   HTTP код: $http_code"
        log_message "   Ответ: $json_response"
        return 1
    fi
}

# Функция для отправки видео в Telegram
send_telegram_video() {
    if [ ! -f "$VIDEO_FILE" ] || [ ! -s "$VIDEO_FILE" ]; then
        log_message "⚠️  Файл видео не существует или пуст"
        return 1
    fi
    
    if ! check_telegram_api; then
        return 1
    fi
    
    local file_size=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
    local file_ext="${VIDEO_FILE##*.}"
    
    log_message "Попытка отправки видео (размер: ${file_size} байт, расширение: $file_ext, тип: $(file -b --mime-type "$VIDEO_FILE" 2>/dev/null || echo 'unknown'))"
    
    local response=""
    local success=0
    
    # Определяем тип файла для отправки
    if [ "$file_ext" = "mjpg" ] || [ "$file_ext" = "mjpeg" ]; then
        # MJPG файлы отправляем как документ
        log_message "📁 Отправляем MJPG как документ"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=🎥 Камера ${camera_num}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))" \
            -w "%{http_code}")
    elif [[ "$file_size" -gt $VIDEO_MAX_SIZE ]]; then
        # Большие файлы отправляем как документ
        log_message "📁 Отправляем как документ (большой размер: ${file_size} байт)"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=🎥 Камера ${camera_num}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))" \
            -w "%{http_code}")
    elif [ "$file_ext" = "mp4" ] || file "$VIDEO_FILE" | grep -q "MP4"; then
        # MP4 файлы отправляем как видео
        log_message "🎥 Отправляем MP4 как видео"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendVideo" \
            -F "chat_id=${CHAT_ID}" \
            -F "video=@${VIDEO_FILE}" \
            -F "caption=🎥 Камера ${camera_num}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))" \
            -w "%{http_code}")
    else
        # Остальные форматы как документ
        log_message "📁 Отправляем как документ (неизвестный формат: $file_ext)"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=🎥 Камера ${camera_num}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))" \
            -w "%{http_code}")
    fi
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "✅ Видео успешно отправлено"
        return 0
    else
        log_message "❌ Ошибка отправки видео"
        log_message "   HTTP код: $http_code"
        log_message "   Ответ: $json_response"
        
        # Если не получилось отправить как видео, пробуем как документ
        if [ "$file_ext" = "mp4" ] && [ $success -eq 0 ]; then
            log_message "⚠️  Пробуем отправить MP4 как документ..."
            
            response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
                -F "chat_id=${CHAT_ID}" \
                -F "document=@${VIDEO_FILE}" \
                -F "caption=🎥 Камера ${camera_num}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))" \
                -w "%{http_code}")
            
            local http_code2=${response: -3}
            local json_response2=${response%???}
            
            if [ "$http_code2" = "200" ] && echo "$json_response2" | grep -q '"ok":true'; then
                log_message "✅ Видео отправлено как документ"
                return 0
            else
                log_message "❌ Ошибка отправки как документ"
                return 1
            fi
        fi
        
        return 1
    fi
}

# Основная функция обработки события
process_event() {
    log_message "=== Обработка события движения на камере $camera_num ==="
    
    # Проверяем доступность Telegram
    if ! check_telegram_api; then
        log_message "❌ Telegram API недоступен, пропускаем отправку"
        return 1
    fi
    
    # Отправляем текстовое уведомление
    if ! send_telegram_message "🚨 Камера ${camera_num}: Движение обнаружено в $(date '+%H:%M:%S')"; then
        log_message "⚠️  Не удалось отправить текстовое уведомление"
        # Не прерываем выполнение, пробуем отправить медиа
    fi
    
    # Обработка в зависимости от выбранного типа медиа
    case $MEDIA_TYPE in
        "photo")
            if get_image; then
                send_telegram_photo
            fi
            ;;
        
        "video")
            # Небольшая задержка перед захватом видео
            sleep 1
            if get_video; then
                send_telegram_video
            fi
            ;;
        
        "both")
            if get_image; then
                send_telegram_photo
            fi
            
            # Небольшая задержка перед захватом видео
            sleep 1
            
            if get_video; then
                send_telegram_video
            fi
            ;;
    esac
    
    # Очистка временных файлов
    cleanup_temp_files
    
    log_message "=== Обработка события завершена ==="
}

# Очистка временных файлов
cleanup_temp_files() {
    rm -f "$IMAGE_FILE" 2>/dev/null
    rm -f "$VIDEO_FILE" 2>/dev/null
    rm -f "$CONVERTED_VIDEO_FILE" 2>/dev/null
    # Удаляем старые файлы в temp директории (старше 1 часа)
    find "$TEMP_DIR" -type f -mmin +60 -delete 2>/dev/null
    # Удаляем пустую временную директорию если она существует
    rmdir "$TEMP_DIR" 2>/dev/null || true
}

# Обработка сигналов для очистки
trap cleanup_temp_files EXIT INT TERM

# Основной код
if [ "$1" = "test" ]; then
    # Тестовый режим - второй аргумент это номер камеры
    if [ -z "$2" ]; then
        echo "Использование: $0 test <номер_камеры>" >&2
        echo "Пример: $0 test 1" >&2
        exit 1
    fi
    
    camera_num="$2"
    
    # Загружаем настройки для конкретной камеры
    if ! get_camera_config "$camera_num"; then
        exit 1
    fi
    
    # Проверяем чат
    if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "ВАШ_CHAT_ID_ЗДЕСЬ" ] || [ "$CHAT_ID" = "ОБЩИЙ_ЧАТ" ]; then
        echo "❌ CHAT_ID для камеры $camera_num не настроен!" >&2
        exit 1
    fi
    
    echo "=== ТЕСТОВЫЙ РЕЖИМ ДЛЯ КАМЕРЫ $camera_num ===" >&2
    echo "Конфигурация:" >&2
    echo "  Бот: $(echo ${BOT_TOKEN:0:10})..." >&2
    echo "  Чат ID: $CHAT_ID" >&2
    echo "  Камера: $camera_num" >&2
    echo "  Тип медиа: $MEDIA_TYPE" >&2
    echo "  Длительность видео: ${VIDEO_DURATION}сек" >&2
    echo "  FPS видео: ${VIDEO_FPS}" >&2
    
    # Тестовая отправка сообщения
    send_telegram_message "🔧 Камера ${camera_num}: Тестовое сообщение от системы Avreg. Если вы видите это, все работает правильно!"
    
    if [ $? -eq 0 ]; then
        echo "✅ Тестовое сообщение отправлено успешно!" >&2
        
        # Тестовая отправка медиа в зависимости от настроек
        case $MEDIA_TYPE in
            "photo")
                echo "Отправка тестового фото..." >&2
                if get_image; then
                    send_telegram_photo
                    echo "✅ Тестовое фото отправлено!" >&2
                else
                    echo "❌ Ошибка получения тестового фото" >&2
                fi
                ;;
            "video")
                echo "Отправка тестового видео..." >&2
                if get_video; then
                    send_telegram_video
                    echo "✅ Тестовое видео отправлено!" >&2
                else
                    echo "❌ Ошибка получения тестового видео" >&2
                fi
                ;;
            "both")
                echo "Отправка тестового фото и видео..." >&2
                if get_image; then
                    send_telegram_photo
                    echo "✅ Тестовое фото отправлено!" >&2
                else
                    echo "❌ Ошибка получения тестового фото" >&2
                fi
                
                sleep 1
                
                if get_video; then
                    send_telegram_video
                    echo "✅ Тестовое видео отправлено!" >&2
                else
                    echo "❌ Ошибка получения тестового видео" >&2
                fi
                ;;
        esac
        
        echo "Проверьте чат Telegram" >&2
    else
        echo "❌ Ошибка отправки тестового сообщения" >&2
        echo "Смотрите подробности в логе: $LOG_FILE" >&2
    fi
    
    # Очистка
    cleanup_temp_files
else
    # Нормальный режим работы
    process_event
fi

EOF

    # Настройка прав доступа и владельца
    echo "Настройка прав доступа для скриптов..."
    sudo chown "$AVREG_USER:$AVREG_GROUP" "$SCRIPT_FILE"
    sudo chmod 0755 "$SCRIPT_FILE"
    
    if [ -f "$CONFIG_FILE" ]; then
        sudo chown "$AVREG_USER:$AVREG_GROUP" "$CONFIG_FILE"
        sudo chmod 0640 "$CONFIG_FILE"
    fi
    
    echo "✅ Скрипт создан: $SCRIPT_FILE"
    echo "✅ Владелец: $AVREG_USER:$AVREG_GROUP"
    echo "✅ Права: 0755 для tg.sh, 0640 для config.sh"
}

# Функция создания скрипта для редактирования конфигурации
create_config_editor() {
    cat <<'EOF' > "$CONFIG_EDITOR"
#!/bin/bash

# Скрипт для редактирования конфигурации Telegram уведомлений Avreg
# Версия 1.2

CONFIG_FILE="/etc/avreg/scripts/telegram_config.sh"
TEMP_CONFIG="/tmp/telegram_config_edit.sh"
BACKUP_DIR="/etc/avreg/scripts/backups"

# Создаем резервную копию
create_backup() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/telegram_config_$(date +%Y%m%d_%H%M%S).sh"
    cp "$CONFIG_FILE" "$backup_file"
    echo "✅ Создана резервная копия: $backup_file"
}

# Функция для редактирования токена бота
edit_bot_token() {
    echo ""
    echo "=== Редактирование токена бота ==="
    
    # Загружаем текущий токен
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущий токен: $(echo ${BOT_TOKEN:0:10}...)"
    echo ""
    echo "Введите новый токен бота:"
    echo "(например: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
    read NEW_BOT_TOKEN
    
    if [ -z "$NEW_BOT_TOKEN" ]; then
        echo "❌ Токен не может быть пустым"
        return 1
    fi
    
    # Обновляем токен в конфигурации
    sed -i "s/BOT_TOKEN='.*'/BOT_TOKEN='$NEW_BOT_TOKEN'/" "$CONFIG_FILE"
    
    echo "✅ Токен бота обновлен"
}

# Функция для редактирования чата камеры
edit_camera_chat() {
    echo ""
    echo "=== Редактирование чата камеры ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    # Показываем текущие камеры
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: Чат ${CAMERA_CHAT_IDS[$i]}"
    done
    
    echo ""
    echo "Введите номер камеры для редактирования:"
    read CAMERA_INDEX
    
    # Проверяем индекс
    re='^[0-9]+$'
    if ! [[ $CAMERA_INDEX =~ $re ]] || [ $CAMERA_INDEX -lt 1 ] || [ $CAMERA_INDEX -gt $CAMERA_COUNT ]; then
        echo "❌ Неверный номер камеры"
        return 1
    fi
    
    local array_index=$((CAMERA_INDEX - 1))
    local camera_num=${CAMERA_NUMS[$array_index]}
    local current_chat=${CAMERA_CHAT_IDS[$array_index]}
    
    echo ""
    echo "Редактирование камеры $camera_num"
    echo "Текущий Chat ID: $current_chat"
    echo ""
    echo "Введите новый Chat ID:"
    read NEW_CHAT_ID
    
    if [ -z "$NEW_CHAT_ID" ]; then
        echo "❌ Chat ID не может быть пустым"
        return 1
    fi
    
    # Обновляем массив в конфигурации
    # Создаем временный файл с обновленной конфигурацией
    awk -v idx="$array_index" -v new_chat="$NEW_CHAT_ID" '
    /^declare -a CAMERA_CHAT_IDS=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        # Конец массива
        print "declare -a CAMERA_CHAT_IDS=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        # Элемент массива с продолжением
        if (array_idx == idx) {
            array_line = array_line "  \"" new_chat "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        # Последний элемент массива без продолжения
        if (array_idx == idx) {
            print "declare -a CAMERA_CHAT_IDS=(" array_line ")"
            print "  \"" new_chat "\")"
        } else {
            print "declare -a CAMERA_CHAT_IDS=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ Chat ID камеры $camera_num обновлен на: $NEW_CHAT_ID"
}

# Функция для редактирования типа медиа камеры
edit_camera_media_type() {
    echo ""
    echo "=== Редактирование типа медиа камеры ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: Тип медиа ${CAMERA_MEDIA_TYPES[$i]}"
    done
    
    echo ""
    echo "Введите номер камеры для редактирования:"
    read CAMERA_INDEX
    
    if ! [[ $CAMERA_INDEX =~ ^[0-9]+$ ]] || [ $CAMERA_INDEX -lt 1 ] || [ $CAMERA_INDEX -gt $CAMERA_COUNT ]; then
        echo "❌ Неверный номер камеры"
        return 1
    fi
    
    local array_index=$((CAMERA_INDEX - 1))
    local camera_num=${CAMERA_NUMS[$array_index]}
    local current_type=${CAMERA_MEDIA_TYPES[$array_index]}
    
    echo ""
    echo "Редактирование камеры $camera_num"
    echo "Текущий тип медиа: $current_type"
    echo ""
    echo "Выберите новый тип медиа:"
    echo "1) Только фото"
    echo "2) Только видео"
    echo "3) Фото и видео"
    read -p "Ваш выбор (1-3): " media_choice
    
    case $media_choice in
        1) NEW_TYPE="photo" ;;
        2) NEW_TYPE="video" ;;
        3) NEW_TYPE="both" ;;
        *) echo "❌ Неверный выбор"; return 1 ;;
    esac
    
    # Обновляем массив
    awk -v idx="$array_index" -v new_type="$NEW_TYPE" '
    /^declare -a CAMERA_MEDIA_TYPES=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_MEDIA_TYPES=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_type "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_MEDIA_TYPES=(" array_line ")"
            print "  \"" new_type "\")"
        } else {
            print "declare -a CAMERA_MEDIA_TYPES=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ Тип медиа камеры $camera_num обновлен на: $NEW_TYPE"
}

# Функция для редактирования параметров видео
edit_video_params() {
    echo ""
    echo "=== Редактирование параметров видео ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: Длительность ${CAMERA_VIDEO_DURATIONS[$i]}сек, FPS ${CAMERA_VIDEO_FPS[$i]}"
    done
    
    echo ""
    echo "Введите номер камеры для редактирования:"
    read CAMERA_INDEX
    
    if ! [[ $CAMERA_INDEX =~ ^[0-9]+$ ]] || [ $CAMERA_INDEX -lt 1 ] || [ $CAMERA_INDEX -gt $CAMERA_COUNT ]; then
        echo "❌ Неверный номер камеры"
        return 1
    fi
    
    local array_index=$((CAMERA_INDEX - 1))
    local camera_num=${CAMERA_NUMS[$array_index]}
    
    echo ""
    echo "Редактирование параметров видео для камеры $camera_num"
    
    # Длительность видео
    echo "Текущая длительность: ${CAMERA_VIDEO_DURATIONS[$array_index]}сек"
    echo "Введите новую длительность видео (в секундах, минимум 5):"
    read NEW_DURATION
    NEW_DURATION=${NEW_DURATION:-${CAMERA_VIDEO_DURATIONS[$array_index]}}
    if [ $NEW_DURATION -lt 5 ]; then
        NEW_DURATION=5
    fi
    
    # FPS видео
    echo "Текущий FPS: ${CAMERA_VIDEO_FPS[$array_index]}"
    echo "Введите новый FPS (1-30):"
    read NEW_FPS
    NEW_FPS=${NEW_FPS:-${CAMERA_VIDEO_FPS[$array_index]}}
    if [ $NEW_FPS -lt 1 ]; then
        NEW_FPS=1
    elif [ $NEW_FPS -gt 30 ]; then
        NEW_FPS=30
    fi
    
    # Обновляем длительность
    awk -v idx="$array_index" -v new_duration="$NEW_DURATION" '
    /^declare -a CAMERA_VIDEO_DURATIONS=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_VIDEO_DURATIONS=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_duration "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_VIDEO_DURATIONS=(" array_line ")"
            print "  \"" new_duration "\")"
        } else {
            print "declare -a CAMERA_VIDEO_DURATIONS=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    # Обновляем FPS
    awk -v idx="$array_index" -v new_fps="$NEW_FPS" '
    /^declare -a CAMERA_VIDEO_FPS=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_VIDEO_FPS=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_fps "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_VIDEO_FPS=(" array_line ")"
            print "  \"" new_fps "\")"
        } else {
            print "declare -a CAMERA_VIDEO_FPS=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ Параметры видео камеры $camera_num обновлены:"
    echo "   Длительность: ${NEW_DURATION}сек"
    echo "   FPS: ${NEW_FPS}"
}

# Функция для просмотра конфигурации
view_config() {
    echo ""
    echo "=== Текущая конфигурация ==="
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Конфигурационный файл не найден"
        return 1
    fi
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Основные параметры:"
    echo "  Бот: $(echo ${BOT_TOKEN:0:10})..."
    echo "  Avreg URL: $AVREG_URL"
    echo "  Логин: $login"
    echo "  Количество камер: $CAMERA_COUNT"
    echo ""
    
    echo "Настройки камер:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "  Камера ${CAMERA_NUMS[$i]}:"
        echo "    Чат ID: ${CAMERA_CHAT_IDS[$i]}"
        echo "    Тип медиа: ${CAMERA_MEDIA_TYPES[$i]}"
        echo "    Длительность видео: ${CAMERA_VIDEO_DURATIONS[$i]}сек"
        echo "    FPS видео: ${CAMERA_VIDEO_FPS[$i]}"
        echo ""
    done
}

# Функция для проверки конфигурации
test_config() {
    echo ""
    echo "=== Тестирование конфигурации ==="
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Конфигурационный файл не найден"
        return 1
    fi
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Проверка токена бота..."
    local bot_check=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
    if echo "$bot_check" | grep -q '"ok":true'; then
        local bot_name=$(echo "$bot_check" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo "✅ Бот: @${bot_name}"
    else
        echo "❌ Ошибка проверки бота"
    fi
    
    echo ""
    echo "Для тестирования конкретной камеры выполните:"
    echo "sudo -u avreg /etc/avreg/scripts/tg.sh test <номер_камеры>"
}

# Главное меню
show_menu() {
    while true; do
        echo ""
        echo "=== Редактор конфигурации Telegram уведомлений ==="
        echo "1) Просмотреть текущую конфигурацию"
        echo "2) Редактировать токен бота"
        echo "3) Редактировать чат для камеры"
        echo "4) Редактировать тип медиа для камеры"
        echo "5) Редактировать параметры видео (длительность, FPS)"
        echo "6) Протестировать конфигурацию"
        echo "7) Создать резервную копию конфигурации"
        echo "8) Выйти"
        echo ""
        
        read -p "Выберите действие (1-8): " choice
        
        case $choice in
            1)
                view_config
                ;;
            2)
                create_backup
                edit_bot_token
                ;;
            3)
                create_backup
                edit_camera_chat
                ;;
            4)
                create_backup
                edit_camera_media_type
                ;;
            5)
                create_backup
                edit_video_params
                ;;
            6)
                test_config
                ;;
            7)
                create_backup
                ;;
            8)
                echo "Выход"
                exit 0
                ;;
            *)
                echo "❌ Неверный выбор"
                ;;
        esac
    done
}

# Проверка прав доступа
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Рекомендуется запускать скрипт с правами root (sudo)"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Проверка существования конфигурации
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Конфигурационный файл не найден: $CONFIG_FILE"
    echo "Сначала запустите основной скрипт настройки"
    exit 1
fi

# Запуск меню
show_menu

EOF

    # Настройка прав доступа
    sudo chown "$AVREG_USER:$AVREG_GROUP" "$CONFIG_EDITOR"
    sudo chmod 0755 "$CONFIG_EDITOR"
    
    echo "✅ Создан скрипт для редактирования конфигурации: $CONFIG_EDITOR"
    echo "✅ Использование: sudo -u avreg $CONFIG_EDITOR"
}

# Функция копирования и настройки event-collector
setup_event_collector() {
    echo "=== Настройка event-collector ==="
    
    # Проверяем, существует ли event-collector
    if [ ! -f "$EVENT_COLLECTOR" ]; then
        echo "event-collector не найден в $EVENT_COLLECTOR"
        
        # Пытаемся найти исходный файл
        if [ -f "$EVENT_COLLECTOR_SOURCE" ]; then
            echo "Копирование event-collector из $EVENT_COLLECTOR_SOURCE..."
            sudo cp "$EVENT_COLLECTOR_SOURCE" "/etc/avreg/scripts/"
            sudo gunzip -f "/etc/avreg/scripts/event-collector.gz"
        elif [ -f "$EVENT_COLLECTOR_SOURCE_ALT" ]; then
            echo "Копирование event-collector из $EVENT_COLLECTOR_SOURCE_ALT..."
            sudo cp "$EVENT_COLLECTOR_SOURCE_ALT" "/etc/avreg/scripts/"
            sudo gunzip -f "/etc/avreg/scripts/event-collector.gz"
        else
            echo "❌ Исходный файл event-collector не найден в стандартных местах:"
            echo "   $EVENT_COLLECTOR_SOURCE"
            echo "   $EVENT_COLLECTOR_SOURCE_ALT"
            echo ""
            echo "Пожалуйста, укажите путь к event-collector.gz вручную:"
            read -p "Путь к event-collector.gz: " custom_path
            
            if [ -f "$custom_path" ]; then
                sudo cp "$custom_path" "/etc/avreg/scripts/"
                sudo gunzip -f "/etc/avreg/scripts/event-collector.gz"
                echo "✅ event-collector скопирован из $custom_path"
            else
                echo "❌ Файл $custom_path не существует"
                return 1
            fi
        fi
    fi
    
    if [ ! -f "$EVENT_COLLECTOR" ]; then
        echo "❌ Не удалось создать event-collector"
        return 1
    fi
    
    echo "✅ event-collector найден: $EVENT_COLLECTOR"
    
    # Изменяем event-collector для поддержки нескольких камер
    echo "Модификация event-collector для поддержки Telegram уведомлений..."
    
    # Создаем резервную копию
    sudo cp "$EVENT_COLLECTOR" "${EVENT_COLLECTOR}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Изменяем интерпретатор на bash для поддержки массивов
    sudo sed -i '1s|#!/bin/sh|#!/bin/bash|' "$EVENT_COLLECTOR"
    
    # Находим функцию on_motion_session и добавляем вызов tg.sh
    local motion_func_start=$(grep -n "^on_motion_session()" "$EVENT_COLLECTOR" | cut -d: -f1)
    
    if [ -n "$motion_func_start" ]; then
        # Находим строку с status='started'
        local status_line=$(awk -v start="$motion_func_start" 'NR >= start && /status='"'"'started'"'"'/ {print NR; exit}' "$EVENT_COLLECTOR")
        
        if [ -n "$status_line" ]; then
            # Добавляем вызов нашего скрипта после строки с status='started'
            sudo sed -i "${status_line}a\\
      # === ДОБАВЛЕНО: Вызов Telegram скрипта при обнаружении движения ===\\
      cam_nr=\\\$2  # номер камеры из аргументов функции\\
      \\
      # Проверяем, существует ли скрипт tg.sh\\
      if [ -f \\\"/etc/avreg/scripts/tg.sh\\\" ]; then\\
          # Проверяем, есть ли конфигурация для этой камеры\\
          if [ -f \\\"/etc/avreg/scripts/telegram_config.sh\\\" ]; then\\
              # Загружаем конфигурацию для проверки\\
              . /etc/avreg/scripts/telegram_config.sh 2>/dev/null || true\\
              \\
              # Проверяем, есть ли такая камера в конфигурации\\
              camera_found=0\\
              for ((i=0; i<CAMERA_COUNT; i++)); do\\
                  if [ \\\"\\\${CAMERA_NUMS[\\\$i]}\\\" = \\\"\\\$cam_nr\\\" ]; then\\
                      camera_found=1\\
                      # Проверяем, настроен ли чат для этой камеры\\
                      chat_id=\\\"\\\${CAMERA_CHAT_IDS[\\\$i]}\\\"\\
                      if [ \\\"\\\$chat_id\\\" != \\\"ВАШ_CHAT_ID_ЗДЕСЬ\\\" ] \\&\\& [ \\\"\\\$chat_id\\\" != \\\"ОБЩИЙ_ЧАТ\\\" ]; then\\
                          # Запускаем скрипт в фоновом режиме с номером камеры\\
                          /etc/avreg/scripts/tg.sh \\\"\\\$cam_nr\\\" \\&\\
                          log debug \\\"Запущен Telegram скрипт для камеры \\\$cam_nr (PID: \\\$!, Чат: \\\$chat_id)\\\"\\
                      else\\
                          log debug \\\"Telegram: для камеры \\\$cam_nr не настроен чат (Chat ID: \\\$chat_id)\\\"\\
                      fi\\
                      break\\
                  fi\\
              done\\
              \\
              if [ \\\$camera_found -eq 0 ]; then\\
                  log debug \\\"Telegram: камера \\\$cam_nr не найдена в конфигурации\\\"\\
              fi\\
          else\\
              log warn \\\"Telegram конфигурация не найдена: /etc/avreg/scripts/telegram_config.sh\\\"\\
          fi\\
      else\\
          log warn \\\"Telegram скрипт не найден: /etc/avreg/scripts/tg.sh\\\"\\
      fi\\
      # === КОНЕЦ ДОБАВЛЕНИЯ ===" "$EVENT_COLLECTOR"
            
            echo "✅ event-collector модифицирован для поддержки Telegram уведомлений"
        else
            echo "⚠️  Не удалось найти строку с status='started' в функции on_motion_session"
            echo "Добавьте код вручную в функцию on_motion_session() после строки с status='started'"
            return 1
        fi
    else
        echo "❌ Не удалось найти функцию on_motion_session() в event-collector"
        return 1
    fi
    
    # Настраиваем права доступа и владельца
    sudo chown "$AVREG_USER:$AVREG_GROUP" "$EVENT_COLLECTOR"
    sudo chmod 0755 "$EVENT_COLLECTOR"
    
    echo "✅ Права доступа установлены: $AVREG_USER:$AVREG_GROUP, 0755"
    echo "✅ Резервная копия сохранена: ${EVENT_COLLECTOR}.backup.*"
    
    return 0
}

# Функция тестирования конфигурации
test_configuration() {
    echo "=== Тестирование конфигурации ==="
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Конфигурационный файл не найден"
        return 1
    fi
    
    # Загружаем конфигурацию
    source "$CONFIG_FILE"
    
    echo "1. Проверка токена бота..."
    local bot_check=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
    if echo "$bot_check" | grep -q '"ok":true'; then
        local bot_name=$(echo "$bot_check" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
        echo "   ✅ Бот: @${bot_name}"
    else
        echo "   ❌ Ошибка: $bot_check"
        return 1
    fi
    
    echo "2. Проверка камер в конфигурации..."
    echo "   Настроено камер: $CAMERA_COUNT"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "   Камера ${CAMERA_NUMS[$i]}: Чат ${CAMERA_CHAT_IDS[$i]}, Тип: ${CAMERA_MEDIA_TYPES[$i]}"
    done
    
    echo "3. Проверка доступности Avreg..."
    if timeout 5 curl -s "http://${AVREG_URL}:874" > /dev/null; then
        echo "   ✅ Avreg доступен"
    else
        echo "   ⚠️  Avreg недоступен по адресу: ${AVREG_URL}:874"
    fi
    
    echo "4. Тестирование камер..."
    for ((i=0; i<CAMERA_COUNT; i++)); do
        camera_num=${CAMERA_NUMS[$i]}
        chat_id=${CAMERA_CHAT_IDS[$i]}
        
        if [ "$chat_id" != "ВАШ_CHAT_ID_ЗДЕСЬ" ] && [ "$chat_id" != "ОБЩИЙ_ЧАТ" ]; then
            echo ""
            echo "   Тестирование камеры $camera_num..."
            sudo -u "$AVREG_USER" "$SCRIPT_FILE" test "$camera_num"
        else
            echo ""
            echo "   ⚠️  Камера $camera_num: чат не настроен, пропускаем"
        fi
    done
    
    echo ""
    echo "=== Результаты тестирования ==="
    echo "Логи находятся в: /tmp/telegram_bot.log"
    echo "Для просмотра лога выполните: tail -f /tmp/telegram_bot.log"
}

# Функция проверки зависимостей
check_dependencies() {
    echo "Проверка зависимостей..."
    
    local missing=0
    
    # Проверка wget
    if ! command -v wget &> /dev/null; then
        echo "❌ wget не установлен"
        missing=1
    else
        echo "✅ wget установлен"
    fi
    
    # Проверка curl
    if ! command -v curl &> /dev/null; then
        echo "❌ curl не установлен"
        missing=1
    else
        echo "✅ curl установлен"
    fi
    
    # Проверка base64
    if ! command -v base64 &> /dev/null; then
        echo "❌ base64 не установлен"
        missing=1
    else
        echo "✅ base64 установлен"
    fi
    
    # Проверка gunzip (для распаковки event-collector)
    if ! command -v gunzip &> /dev/null; then
        echo "❌ gunzip не установлен"
        missing=1
    else
        echo "✅ gunzip установлен"
    fi
    
    # Проверка ffmpeg (рекомендуется)
    if ! command -v ffmpeg &> /dev/null; then
        echo "⚠️  ffmpeg не установлен (рекомендуется для работы с видео)"
    else
        echo "✅ ffmpeg установлен"
    fi
    
    # Проверка существования пользователя avreg
    if ! id "$AVREG_USER" &>/dev/null; then
        echo "⚠️  Пользователь $AVREG_USER не существует. Создайте его или укажите другого пользователя."
        read -p "Использовать пользователя по умолчанию (avreg)? (y/n): " use_default
        if [[ ! $use_default =~ ^[Yy]$ ]]; then
            read -p "Введите имя пользователя для запуска скриптов: " AVREG_USER
            if ! id "$AVREG_USER" &>/dev/null; then
                echo "❌ Пользователь $AVREG_USER не существует"
                return 1
            fi
        else
            echo "⚠️  Для корректной работы создайте пользователя avreg: sudo useradd -r -s /bin/false avreg"
        fi
    else
        echo "✅ Пользователь $AVREG_USER существует"
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo "Установите недостающие пакеты:"
        echo "Debian/Ubuntu: sudo apt-get install wget curl coreutils gzip"
        echo "CentOS/RHEL: sudo yum install wget curl coreutils gzip"
        return 1
    fi
    
    return 0
}

# Функция настройки прав доступа для всех файлов
setup_permissions() {
    echo "=== Настройка прав доступа для всех файлов ==="
    
    # Проверяем существование файлов
    if [ -f "$SCRIPT_FILE" ]; then
        sudo chown "$AVREG_USER:$AVREG_GROUP" "$SCRIPT_FILE"
        sudo chmod 0755 "$SCRIPT_FILE"
        echo "✅ Права для $SCRIPT_FILE: $AVREG_USER:$AVREG_GROUP, 0755"
    else
        echo "⚠️  $SCRIPT_FILE не существует"
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        sudo chown "$AVREG_USER:$AVREG_GROUP" "$CONFIG_FILE"
        sudo chmod 0640 "$CONFIG_FILE"
        echo "✅ Права для $CONFIG_FILE: $AVREG_USER:$AVREG_GROUP, 0640"
    else
        echo "⚠️  $CONFIG_FILE не существует"
    fi
    
    if [ -f "$CONFIG_EDITOR" ]; then
        sudo chown "$AVREG_USER:$AVREG_GROUP" "$CONFIG_EDITOR"
        sudo chmod 0755 "$CONFIG_EDITOR"
        echo "✅ Права для $CONFIG_EDITOR: $AVREG_USER:$AVREG_GROUP, 0755"
    fi
    
    if [ -f "$EVENT_COLLECTOR" ]; then
        sudo chown "$AVREG_USER:$AVREG_GROUP" "$EVENT_COLLECTOR"
        sudo chmod 0755 "$EVENT_COLLECTOR"
        echo "✅ Права для $EVENT_COLLECTOR: $AVREG_USER:$AVREG_GROUP, 0755"
    else
        echo "⚠️  $EVENT_COLLECTOR не существует"
    fi
    
    # Создаем директорию для скриптов если не существует
    sudo mkdir -p /etc/avreg/scripts
    sudo chown "$AVREG_USER:$AVREG_GROUP" /etc/avreg/scripts
    sudo chmod 0755 /etc/avreg/scripts
    echo "✅ Права для /etc/avreg/scripts: $AVREG_USER:$AVREG_GROUP, 0755"
    
    # Создаем директорию для бэкапов
    sudo mkdir -p /etc/avreg/scripts/backups
    sudo chown "$AVREG_USER:$AVREG_GROUP" /etc/avreg/scripts/backups
    sudo chmod 0755 /etc/avreg/scripts/backups
    echo "✅ Права для /etc/avreg/scripts/backups: $AVREG_USER:$AVREG_GROUP, 0755"
    
    echo "=== Проверка прав доступа ==="
    ls -la /etc/avreg/scripts/ 2>/dev/null || echo "Директория /etc/avreg/scripts/ не существует"
}

# Основное меню
show_menu() {
    while true; do
        echo ""
        echo "=== Меню управления Telegram уведомлениями Avreg ==="
        echo "1) Настроить конфигурацию (обязательно сначала)"
        echo "2) Протестировать конфигурацию"
        echo "3) Настроить event-collector (копирование и модификация)"
        echo "4) Настроить права доступа для всех файлов"
        echo "5) Показать текущую конфигурацию"
        echo "6) Проверить состояние системы"
        echo "7) Просмотреть логи"
        echo "8) Перезапустить avreg"
        echo "9) Проверить/установить ffmpeg"
        echo "10) Запустить редактор конфигурации"
        echo "11) Выход"
        echo ""
        
        read -p "Выберите действие (1-11): " choice
        
        case $choice in
            1)
                request_config
                create_script
                create_config_editor
                setup_permissions
                ;;
            2)
                test_configuration
                ;;
            3)
                setup_event_collector
                ;;
            4)
                setup_permissions
                ;;
            5)
                if [ -f "$CONFIG_FILE" ]; then
                    echo "=== Текущая конфигурация ==="
                    source "$CONFIG_FILE" 2>/dev/null
                    echo "Бот: $(echo ${BOT_TOKEN:0:10})..."
                    echo "Количество камер: $CAMERA_COUNT"
                    echo "Avreg URL: $AVREG_URL"
                    echo "Логин: $login"
                    echo "Пользователь скриптов: $AVREG_USER"
                    echo ""
                    echo "Настройки камер:"
                    for ((i=0; i<CAMERA_COUNT; i++)); do
                        echo "  Камера ${CAMERA_NUMS[$i]}:"
                        echo "    Чат: ${CAMERA_CHAT_IDS[$i]}"
                        echo "    Тип медиа: ${CAMERA_MEDIA_TYPES[$i]}"
                        echo "    Длительность видео: ${CAMERA_VIDEO_DURATIONS[$i]}сек"
                        echo "    FPS видео: ${CAMERA_VIDEO_FPS[$i]}"
                    done
                    echo ""
                    echo "Файлы:"
                    echo "  Конфиг: $CONFIG_FILE"
                    echo "  Скрипт: $SCRIPT_FILE"
                    echo "  Редактор конфига: $CONFIG_EDITOR"
                    echo "  Event-collector: $EVENT_COLLECTOR"
                else
                    echo "❌ Конфигурация не настроена. Выберите пункт 1"
                fi
                ;;
            6)
                echo "=== Состояние системы ==="
                check_dependencies
                echo ""
                if [ -f "$CONFIG_FILE" ]; then
                    source "$CONFIG_FILE" 2>/dev/null
                    echo "Конфигурация загружена: Да"
                    echo "Токен бота: $(echo ${BOT_TOKEN:0:10}...)"
                    echo "Количество камер: $CAMERA_COUNT"
                    echo "Пользователь скриптов: $AVREG_USER"
                else
                    echo "Конфигурация загружена: Нет"
                fi
                echo ""
                echo "Скрипты:"
                ls -la /etc/avreg/scripts/ 2>/dev/null || echo "Директория /etc/avreg/scripts/ не существует"
                echo ""
                echo "Проверка службы avreg:"
                if command -v systemctl &> /dev/null; then
                    systemctl status avreg --no-pager | head -10
                elif command -v service &> /dev/null; then
                    service avreg status | head -10
                else
                    echo "Не удалось проверить состояние службы"
                fi
                ;;
            7)
                echo "=== Логи ==="
                if [ -f "/tmp/telegram_bot.log" ]; then
                    echo "Последние 20 строк лога Telegram бота:"
                    tail -20 "/tmp/telegram_bot.log"
                    echo ""
                    echo "Полный лог: tail -f /tmp/telegram_bot.log"
                else
                    echo "Лог файл Telegram бота не найден"
                fi
                
                echo ""
                echo "Логи avreg:"
                if [ -f "/var/log/avreg/avreg.log" ]; then
                    echo "Последние 10 строк лога avreg:"
                    tail -10 "/var/log/avreg/avreg.log"
                else
                    echo "Лог avreg не найден"
                fi
                ;;
            8)
                echo "Перезапуск avreg..."
                if command -v systemctl &> /dev/null; then
                    sudo systemctl restart avreg
                    echo "✅ systemctl: avreg перезапущен"
                elif command -v service &> /dev/null; then
                    sudo service avreg restart
                    echo "✅ service: avreg перезапущен"
                else
                    echo "⚠️  Не удалось определить способ управления службами"
                fi
                ;;
            9)
                check_and_install_ffmpeg
                ;;
            10)
                if [ -f "$CONFIG_EDITOR" ]; then
                    sudo -u "$AVREG_USER" "$CONFIG_EDITOR"
                else
                    echo "❌ Редактор конфигурации не найден"
                    echo "Сначала выполните пункт 1 для настройки"
                fi
                ;;
            11)
                echo "Выход"
                exit 0
                ;;
            *)
                echo "❌ Неверный выбор"
                ;;
        esac
    done
}

# Создание директории если не существует
sudo mkdir -p /etc/avreg/scripts

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  Рекомендуется запускать скрипт с правами root (sudo)"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "=== Установка Telegram уведомлений для Avreg ==="
echo "Версия 1.2"
echo ""

# Проверка ffmpeg при запуске
if ! command -v ffmpeg &> /dev/null; then
    echo "⚠️  ВНИМАНИЕ: ffmpeg не установлен."
    echo "   Для правильной работы с видео рекомендуется установить ffmpeg."
    echo "   Вы можете установить его через пункт меню 9."
    echo ""
fi

# Запуск
check_dependencies
if [ $? -eq 0 ]; then
    show_menu
else
    echo "❌ Установите зависимости и запустите скрипт снова"
    exit 1
fi
