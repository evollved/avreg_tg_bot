#!/bin/bash

# Скрипт для создания tg.sh и настройки avreg
# Версия 1.5 - Добавлена настройка отправки только медиа без текста

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
    echo "=== Настройка отправки сообщений ==="
    echo ""
    
    # Настройка отправки текстовых сообщений
    echo "Отправлять текстовые уведомления вместе с медиа?"
    echo "1) Да, отправлять и текст, и медиа (по умолчанию)"
    echo "2) Нет, отправлять только медиа (фото/видео без текста)"
    echo "3) Отправлять только текст (без медиа)"
    read -p "Ваш выбор (1-3): " message_choice
    
    case $message_choice in
        1)
            SEND_TEXT="true"
            SEND_MEDIA="true"
            echo "✅ Будут отправляться и текст, и медиа"
            ;;
        2)
            SEND_TEXT="false"
            SEND_MEDIA="true"
            echo "✅ Будут отправляться только медиа (без текста)"
            ;;
        3)
            SEND_TEXT="true"
            SEND_MEDIA="false"
            echo "✅ Будут отправляться только текстовые уведомления (без медиа)"
            ;;
        *)
            SEND_TEXT="true"
            SEND_MEDIA="true"
            echo "✅ Используется режим по умолчанию: текст + медиа"
            ;;
    esac
    
    echo ""
    echo "=== Настройка расписания ==="
    echo ""
    
    # Настройка расписания
    echo "Настроить расписание работы бота?"
    echo "1) Всегда отправлять уведомления (по умолчанию)"
    echo "2) Настроить дни и время работы"
    read -p "Ваш выбор (1-2): " schedule_choice
    
    SCHEDULE_ENABLED="true"
    SCHEDULE_TYPE="always"
    SCHEDULE_DAYS=""
    SCHEDULE_HOURS=""
    SCHEDULE_MINUTES=""
    
    if [ "$schedule_choice" = "2" ]; then
        SCHEDULE_TYPE="custom"
        SCHEDULE_ENABLED="true"
        
        # Настройка дней недели
        echo ""
        echo "=== Настройка дней недели ==="
        echo "Выберите дни недели для отправки уведомлений:"
        echo "0) Воскресенье"
        echo "1) Понедельник"
        echo "2) Вторник"
        echo "3) Среда"
        echo "4) Четверг"
        echo "5) Пятница"
        echo "6) Суббота"
        echo "7) Все дни"
        echo ""
        echo "Введите номера дней через запятую (например: 1,2,3,4,5 для рабочих дней):"
        read schedule_days_input
        
        if [ -z "$schedule_days_input" ]; then
            echo "Используются все дни"
            SCHEDULE_DAYS="0,1,2,3,4,5,6"
        elif [[ "$schedule_days_input" =~ ^[0-6](,[0-6])*$ ]] || [ "$schedule_days_input" = "7" ]; then
            if [ "$schedule_days_input" = "7" ]; then
                SCHEDULE_DAYS="0,1,2,3,4,5,6"
            else
                SCHEDULE_DAYS="$schedule_days_input"
            fi
        else
            echo "⚠️  Неверный формат, используются все дни"
            SCHEDULE_DAYS="0,1,2,3,4,5,6"
        fi
        
        # Настройка часов
        echo ""
        echo "=== Настройка часов ==="
        echo "Выберите часы для отправки уведомлений:"
        echo "1) Все часы (0-23)"
        echo "2) Рабочее время (8-20)"
        echo "3) Ночное время (20-8)"
        echo "4) Указать свои часы"
        read -p "Ваш выбор (1-4): " hours_choice
        
        case $hours_choice in
            1)
                SCHEDULE_HOURS="0-23"
                ;;
            2)
                SCHEDULE_HOURS="8-20"
                ;;
            3)
                SCHEDULE_HOURS="20-8"
                ;;
            4)
                echo ""
                echo "Введите часы для отправки уведомлений:"
                echo "Формат: отдельные часы через запятую (0,1,2) или диапазон (8-17)"
                echo "Можно комбинировать: 0-5,8,12-14,18-23"
                read custom_hours
                if [ -n "$custom_hours" ]; then
                    SCHEDULE_HOURS="$custom_hours"
                else
                    SCHEDULE_HOURS="0-23"
                fi
                ;;
            *)
                SCHEDULE_HOURS="0-23"
                ;;
        esac
        
        # Настройка минут
        echo ""
        echo "=== Настройка минут ==="
        echo "Выберите минуты для отправки уведомлений:"
        echo "1) Все минуты (0-59)"
        echo "2) Каждые 5 минут (0,5,10,15,20,25,30,35,40,45,50,55)"
        echo "3) Каждые 10 минут (0,10,20,30,40,50)"
        echo "4) Каждые 15 минут (0,15,30,45)"
        echo "5) Каждые 30 минут (0,30)"
        echo "6) Указать свои минуты"
        read -p "Ваш выбор (1-6): " minutes_choice
        
        case $minutes_choice in
            1)
                SCHEDULE_MINUTES="0-59"
                ;;
            2)
                SCHEDULE_MINUTES="0,5,10,15,20,25,30,35,40,45,50,55"
                ;;
            3)
                SCHEDULE_MINUTES="0,10,20,30,40,50"
                ;;
            4)
                SCHEDULE_MINUTES="0,15,30,45"
                ;;
            5)
                SCHEDULE_MINUTES="0,30"
                ;;
            6)
                echo ""
                echo "Введите минуты для отправки уведомлений:"
                echo "Формат: отдельные минуты через запятую (0,15,30,45) или диапазон (0-30)"
                echo "Можно комбинировать: 0-15,30,45-59"
                read custom_minutes
                if [ -n "$custom_minutes" ]; then
                    SCHEDULE_MINUTES="$custom_minutes"
                else
                    SCHEDULE_MINUTES="0-59"
                fi
                ;;
            *)
                SCHEDULE_MINUTES="0-59"
                ;;
        esac
        
        # Настройка исключений
        echo ""
        echo "=== Настройка исключений ==="
        echo "Добавить исключения (выходные/праздничные дни)?"
        echo "1) Нет"
        echo "2) Добавить даты исключений"
        read -p "Ваш выбор (1-2): " exclude_choice
        
        if [ "$exclude_choice" = "2" ]; then
            echo ""
            echo "Введите даты исключений в формате ГГГГ-ММ-ДД, через запятую:"
            echo "Пример: 2024-01-01,2024-01-07,2024-05-01"
            echo "(оставьте пустым, если не нужно)"
            read exclude_dates
            if [ -n "$exclude_dates" ]; then
                SCHEDULE_EXCLUDE_DATES="$exclude_dates"
            fi
        fi
        
        echo ""
        echo "=== Сводка расписания ==="
        echo "Дни недели: $SCHEDULE_DAYS"
        echo "Часы: $SCHEDULE_HOURS"
        echo "Минуты: $SCHEDULE_MINUTES"
        if [ -n "$SCHEDULE_EXCLUDE_DATES" ]; then
            echo "Исключения: $SCHEDULE_EXCLUDE_DATES"
        fi
    else
        echo "Используется режим 'Всегда'"
        SCHEDULE_TYPE="always"
    fi
    
    echo ""
    echo "=== Настройка событий ==="
    echo ""
    
    # Настройка отправляемых событий
    echo "Какие события отправлять в Telegram?"
    echo ""
    echo "Основные события:"
    echo "1) Движение (motion) - обнаружение движения"
    echo "2) Захват видео (capture) - статус захвата видео"
    echo "3) Ошибки (errors) - критические ошибки системы"
    echo "4) Запись (recording) - статус записи видео"
    echo "5) Сохранение файлов (files) - сохранение видео/фото"
    echo "6) Качество изображения (quality) - изменения качества"
    echo "7) Сеть (network) - подключение клиентов"
    echo "8) Все события (all)"
    echo "9) Только движение (только motion)"
    echo ""
    
    declare -a EVENT_TYPES=()
    
    while true; do
        echo "Выберите типы событий (через запятую, например: 1,3,5):"
        read events_input
        
        if [ -z "$events_input" ]; then
            echo "❌ Необходимо выбрать хотя бы одно событие"
            continue
        fi
        
        # Преобразуем строку в массив
        IFS=',' read -ra events_array <<< "$events_input"
        
        # Проверяем каждое значение
        valid=true
        for event in "${events_array[@]}"; do
            if ! [[ "$event" =~ ^[1-9]$ ]]; then
                echo "❌ Неверный номер события: $event"
                valid=false
                break
            fi
        done
        
        if $valid; then
            # Преобразуем цифры в названия событий
            for event_num in "${events_array[@]}"; do
                case $event_num in
                    1) EVENT_TYPES+=("motion") ;;
                    2) EVENT_TYPES+=("capture") ;;
                    3) EVENT_TYPES+=("errors") ;;
                    4) EVENT_TYPES+=("recording") ;;
                    5) EVENT_TYPES+=("files") ;;
                    6) EVENT_TYPES+=("quality") ;;
                    7) EVENT_TYPES+=("network") ;;
                    8) EVENT_TYPES+=("all") ;;
                    9) EVENT_TYPES+=("motion_only") ;;
                esac
            done
            break
        fi
    done
    
    # Настройка уровней важности
    echo ""
    echo "Выберите минимальный уровень важности для отправки:"
    echo "1) DEBUG - отладочная информация"
    echo "2) INFO - информационные сообщения"
    echo "3) WARNING - предупреждения"
    echo "4) ERROR - ошибки"
    echo "5) CRITICAL - критические ошибки"
    read -p "Ваш выбор (1-5): " log_level
    
    case $log_level in
        1) LOG_LEVEL="DEBUG" ;;
        2) LOG_LEVEL="INFO" ;;
        3) LOG_LEVEL="WARNING" ;;
        4) LOG_LEVEL="ERROR" ;;
        5) LOG_LEVEL="CRITICAL" ;;
        *) LOG_LEVEL="INFO" ;;
    esac
    
    # Настройка исключений для ошибок
    echo ""
    echo "Отправлять критические ошибки вне расписания?"
    echo "1) Да, критические ошибки отправлять всегда"
    echo "2) Нет, соблюдать расписание даже для ошибок"
    read -p "Ваш выбор (1-2): " critical_choice
    
    if [ "$critical_choice" = "1" ]; then
        SEND_CRITICAL_ALWAYS="true"
    else
        SEND_CRITICAL_ALWAYS="false"
    fi
    
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
    declare -a CAMERA_EVENT_TYPES
    declare -a CAMERA_SCHEDULES
    declare -a CAMERA_SEND_TEXT
    declare -a CAMERA_SEND_MEDIA
    
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
        
        # Настройка отправки текста/медиа для камеры
        echo ""
        echo "Настройка отправки сообщений для камеры $CAMERA_NUM:"
        echo "1) Использовать общие настройки отправки сообщений"
        echo "2) Настроить индивидуально для этой камеры"
        read -p "Ваш выбор (1-2): " message_override_choice
        
        if [ "$message_override_choice" = "1" ]; then
            # Использовать общие настройки
            CAMERA_SEND_TEXT[$i]="GENERAL"
            CAMERA_SEND_MEDIA[$i]="GENERAL"
            echo "   Используются общие настройки: Текст=$SEND_TEXT, Медиа=$SEND_MEDIA"
        else
            # Индивидуальные настройки
            echo ""
            echo "Выберите режим отправки для камеры $CAMERA_NUM:"
            echo "1) Отправлять и текст, и медиа"
            echo "2) Отправлять только медиа (без текста)"
            echo "3) Отправлять только текст (без медиа)"
            read -p "Ваш выбор (1-3): " camera_message_choice
            
            case $camera_message_choice in
                1)
                    CAMERA_SEND_TEXT[$i]="true"
                    CAMERA_SEND_MEDIA[$i]="true"
                    echo "✅ Камера $CAMERA_NUM: будут отправляться и текст, и медиа"
                    ;;
                2)
                    CAMERA_SEND_TEXT[$i]="false"
                    CAMERA_SEND_MEDIA[$i]="true"
                    echo "✅ Камера $CAMERA_NUM: будут отправляться только медиа (без текста)"
                    ;;
                3)
                    CAMERA_SEND_TEXT[$i]="true"
                    CAMERA_SEND_MEDIA[$i]="false"
                    echo "✅ Камера $CAMERA_NUM: будут отправляться только текстовые уведомления"
                    ;;
                *)
                    CAMERA_SEND_TEXT[$i]="GENERAL"
                    CAMERA_SEND_MEDIA[$i]="GENERAL"
                    echo "⚠️ Используются общие настройки"
                    ;;
            esac
        fi
        
        # Настройка расписания для камеры
        echo ""
        echo "Настройка расписания для камеры $CAMERA_NUM:"
        echo "1) Использовать общее расписание"
        echo "2) Настроить индивидуальное расписание"
        echo "3) Всегда отправлять (игнорировать расписание)"
        read -p "Ваш выбор (1-3): " camera_schedule_choice
        
        case $camera_schedule_choice in
            1)
                CAMERA_SCHEDULES[$i]="GENERAL"
                ;;
            2)
                echo ""
                echo "=== Индивидуальное расписание для камеры $CAMERA_NUM ==="
                
                # Настройка дней недели
                echo "Выберите дни недели:"
                echo "0) Воскресенье"
                echo "1) Понедельник"
                echo "2) Вторник"
                echo "3) Среда"
                echo "4) Четверг"
                echo "5) Пятница"
                echo "6) Суббота"
                echo "7) Все дни"
                echo ""
                echo "Введите номера дней через запятую:"
                read camera_days_input
                
                if [ -z "$camera_days_input" ]; then
                    camera_days="0,1,2,3,4,5,6"
                elif [[ "$camera_days_input" =~ ^[0-6](,[0-6])*$ ]] || [ "$camera_days_input" = "7" ]; then
                    if [ "$camera_days_input" = "7" ]; then
                        camera_days="0,1,2,3,4,5,6"
                    else
                        camera_days="$camera_days_input"
                    fi
                else
                    camera_days="0,1,2,3,4,5,6"
                fi
                
                # Настройка часов
                echo ""
                echo "Введите часы (формат: 0-23 или 8-20 или 0,1,2):"
                read camera_hours
                camera_hours=${camera_hours:-"0-23"}
                
                # Настройка минут
                echo ""
                echo "Введите минуты (формат: 0-59 или 0,15,30,45):"
                read camera_minutes
                camera_minutes=${camera_minutes:-"0-59"}
                
                CAMERA_SCHEDULES[$i]="days:$camera_days;hours:$camera_hours;minutes:$camera_minutes"
                ;;
            3)
                CAMERA_SCHEDULES[$i]="ALWAYS"
                ;;
            *)
                CAMERA_SCHEDULES[$i]="GENERAL"
                ;;
        esac
        
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
        
        # Настройка событий для камеры
        echo ""
        echo "Выберите события для камеры $CAMERA_NUM:"
        echo "1) Использовать общие настройки событий"
        echo "2) Настроить индивидуально"
        read -p "Ваш выбор (1-2): " event_choice
        
        if [ "$event_choice" = "1" ]; then
            # Использовать общие настройки
            CAMERA_EVENT_TYPES[$i]="GENERAL"
        else
            # Индивидуальные настройки
            echo ""
            echo "Какие события отправлять для камеры $CAMERA_NUM?"
            echo "1) Движение (motion)"
            echo "2) Захват видео (capture)"
            echo "3) Ошибки (errors)"
            echo "4) Запись (recording)"
            echo "5) Сохранение файлов (files)"
            echo "6) Качество изображения (quality)"
            echo "7) Сеть (network)"
            echo "8) Все события (all)"
            echo "9) Только движение (motion_only)"
            echo ""
            
            echo "Выберите типы событий (через запятую, например: 1,3,5):"
            read camera_events
            
            # Преобразуем строку в названия событий
            IFS=',' read -ra camera_events_array <<< "$camera_events"
            local camera_event_string=""
            for event_num in "${camera_events_array[@]}"; do
                case $event_num in
                    1) camera_event_string+="motion," ;;
                    2) camera_event_string+="capture," ;;
                    3) camera_event_string+="errors," ;;
                    4) camera_event_string+="recording," ;;
                    5) camera_event_string+="files," ;;
                    6) camera_event_string+="quality," ;;
                    7) camera_event_string+="network," ;;
                    8) camera_event_string+="all," ;;
                    9) camera_event_string+="motion_only," ;;
                esac
            done
            CAMERA_EVENT_TYPES[$i]=$(echo $camera_event_string | sed 's/,$//')
        fi
        
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
# Версия: 1.5

# Данные бота Telegram
BOT_TOKEN='$BOT_TOKEN'

# Настройки отправки сообщений
SEND_TEXT='$SEND_TEXT'  # Отправлять текстовые уведомления (true/false)
SEND_MEDIA='$SEND_MEDIA' # Отправлять медиа (фото/видео) (true/false)

# Настройки расписания
SCHEDULE_ENABLED='$SCHEDULE_ENABLED'
SCHEDULE_TYPE='$SCHEDULE_TYPE'
SCHEDULE_DAYS='$SCHEDULE_DAYS'
SCHEDULE_HOURS='$SCHEDULE_HOURS'
SCHEDULE_MINUTES='$SCHEDULE_MINUTES'
SCHEDULE_EXCLUDE_DATES='${SCHEDULE_EXCLUDE_DATES:-}'
SEND_CRITICAL_ALWAYS='$SEND_CRITICAL_ALWAYS'

# Настройки событий
EVENT_TYPES=($(printf '"%s" ' "${EVENT_TYPES[@]}"))
LOG_LEVEL='$LOG_LEVEL'

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
    echo "declare -a CAMERA_EVENT_TYPES=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_EVENT_TYPES[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_EVENT_TYPES[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_SCHEDULES=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_SCHEDULES[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_SCHEDULES[$i]}\" \\" >> "$CONFIG_FILE"
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
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_SEND_TEXT=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_SEND_TEXT[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_SEND_TEXT[$i]}\" \\" >> "$CONFIG_FILE"
        fi
    done
    
    echo "" >> "$CONFIG_FILE"
    echo "declare -a CAMERA_SEND_MEDIA=(\\" >> "$CONFIG_FILE"
    for ((i=1; i<=$CAMERA_COUNT; i++)); do
        if [ $i -eq $CAMERA_COUNT ]; then
            echo "  \"${CAMERA_SEND_MEDIA[$i]}\")" >> "$CONFIG_FILE"
        else
            echo "  \"${CAMERA_SEND_MEDIA[$i]}\" \\" >> "$CONFIG_FILE"
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
    export EVENT_TYPE="\${CAMERA_EVENT_TYPES[\$camera_index]}"
    export CAMERA_SCHEDULE="\${CAMERA_SCHEDULES[\$camera_index]}"
    export VIDEO_DURATION="\${CAMERA_VIDEO_DURATIONS[\$camera_index]}"
    export VIDEO_FPS="\${CAMERA_VIDEO_FPS[\$camera_index]}"
    export CAMERA_SEND_TEXT_SETTING="\${CAMERA_SEND_TEXT[\$camera_index]}"
    export CAMERA_SEND_MEDIA_SETTING="\${CAMERA_SEND_MEDIA[\$camera_index]}"
    
    return 0
}

# Функция получения настроек отправки сообщений для камеры
get_camera_message_settings() {
    local camera_num=\$1
    
    # По умолчанию используем глобальные настройки
    local send_text="\$SEND_TEXT"
    local send_media="\$SEND_MEDIA"
    
    if [ -n "\$camera_num" ]; then
        # Получаем настройки для конкретной камеры
        get_camera_config "\$camera_num" 2>/dev/null
        if [ -n "\$CAMERA_SEND_TEXT_SETTING" ] && [ "\$CAMERA_SEND_TEXT_SETTING" != "GENERAL" ]; then
            send_text="\$CAMERA_SEND_TEXT_SETTING"
        fi
        if [ -n "\$CAMERA_SEND_MEDIA_SETTING" ] && [ "\$CAMERA_SEND_MEDIA_SETTING" != "GENERAL" ]; then
            send_media="\$CAMERA_SEND_MEDIA_SETTING"
        fi
    fi
    
    export SHOULD_SEND_TEXT="\$send_text"
    export SHOULD_SEND_MEDIA="\$send_media"
    
    return 0
}

# Функция проверки, нужно ли отправлять событие
should_send_event() {
    local event_name=\$1
    local event_level=\$2
    local camera_num=\$3
    
    # Определяем настройки событий для камеры
    local camera_event_settings="\${EVENT_TYPES[@]}"
    if [ -n "\$camera_num" ]; then
        # Получаем настройки для конкретной камеры
        get_camera_config "\$camera_num" 2>/dev/null
        if [ -n "\$EVENT_TYPE" ] && [ "\$EVENT_TYPE" != "GENERAL" ]; then
            camera_event_settings=\$EVENT_TYPE
        fi
    fi
    
    # Проверяем уровень логирования
    local level_num=0
    case "\$LOG_LEVEL" in
        "DEBUG") level_num=1 ;;
        "INFO") level_num=2 ;;
        "WARNING") level_num=3 ;;
        "ERROR") level_num=4 ;;
        "CRITICAL") level_num=5 ;;
    esac
    
    local event_level_num=0
    case "\$event_level" in
        "debug") event_level_num=1 ;;
        "info") event_level_num=2 ;;
        "warning") event_level_num=3 ;;
        "error") event_level_num=4 ;;
        "critical") event_level_num=5 ;;
    esac
    
    if [ \$event_level_num -lt \$level_num ]; then
        return 1
    fi
    
    # Проверяем настройки событий
    if [[ " \${camera_event_settings[@]} " =~ " all " ]]; then
        # Проверяем расписание
        if check_schedule "\$camera_num" "\$event_name" "\$event_level"; then
            return 0
        else
            return 1
        fi
    fi
    
    if [[ " \${camera_event_settings[@]} " =~ " \$event_name " ]]; then
        # Проверяем расписание
        if check_schedule "\$camera_num" "\$event_name" "\$event_level"; then
            return 0
        else
            return 1
        fi
    fi
    
    # Проверяем специальные случаи
    if [[ " \${camera_event_settings[@]} " =~ " motion_only " ]] && [ "\$event_name" = "motion" ]; then
        if check_schedule "\$camera_num" "\$event_name" "\$event_level"; then
            return 0
        else
            return 1
        fi
    fi
    
    return 1
}

# Функция проверки расписания
check_schedule() {
    local camera_num=\$1
    local event_name=\$2
    local event_level=\$3
    
    # Если расписание отключено, всегда отправляем
    if [ "\$SCHEDULE_ENABLED" = "false" ]; then
        return 0
    fi
    
    # Если тип расписания "always", всегда отправляем
    if [ "\$SCHEDULE_TYPE" = "always" ]; then
        return 0
    fi
    
    # Если событие критическое и настроена отправка критических всегда
    if [ "\$event_level" = "critical" ] && [ "\$SEND_CRITICAL_ALWAYS" = "true" ]; then
        return 0
    fi
    
    # Получаем настройки расписания для камеры
    local schedule_settings="\$SCHEDULE_DAYS;\$SCHEDULE_HOURS;\$SCHEDULE_MINUTES"
    if [ -n "\$camera_num" ]; then
        get_camera_config "\$camera_num" 2>/dev/null
        if [ -n "\$CAMERA_SCHEDULE" ]; then
            if [ "\$CAMERA_SCHEDULE" = "ALWAYS" ]; then
                return 0
            elif [ "\$CAMERA_SCHEDULE" = "GENERAL" ]; then
                # Используем общие настройки
                schedule_settings="\$SCHEDULE_DAYS;\$SCHEDULE_HOURS;\$SCHEDULE_MINUTES"
            else
                # Используем индивидуальные настройки камеры
                schedule_settings="\$CAMERA_SCHEDULE"
            fi
        fi
    fi
    
    # Текущее время
    local current_day=\$(date +%w)  # 0-6 (0=воскресенье)
    local current_hour=\$(date +%H)
    local current_minute=\$(date +%M)
    local current_date=\$(date +%Y-%m-%d)
    
    # Проверяем исключенные даты
    if [ -n "\$SCHEDULE_EXCLUDE_DATES" ]; then
        IFS=',' read -ra exclude_dates <<< "\$SCHEDULE_EXCLUDE_DATES"
        for exclude_date in "\${exclude_dates[@]}"; do
            if [ "\$current_date" = "\$exclude_date" ]; then
                return 1  # Дата в исключениях
            fi
        done
    fi
    
    # Парсим настройки расписания
    IFS=';' read -ra schedule_parts <<< "\$schedule_settings"
    
    local days_part="\${schedule_parts[0]#days:}"
    local hours_part="\${schedule_parts[1]#hours:}"
    local minutes_part="\${schedule_parts[2]#minutes:}"
    
    # Проверяем дни
    if ! check_time_part "\$current_day" "\$days_part" "day"; then
        return 1
    fi
    
    # Проверяем часы
    if ! check_time_part "\$current_hour" "\$hours_part" "hour"; then
        return 1
    fi
    
    # Проверяем минуты
    if ! check_time_part "\$current_minute" "\$minutes_part" "minute"; then
        return 1
    fi
    
    return 0
}

# Функция проверки части времени (дни, часы, минуты)
check_time_part() {
    local current_value=\$1
    local schedule_part=\$2
    local part_type=\$3
    
    # Если пусто, считаем что все значения разрешены
    if [ -z "\$schedule_part" ]; then
        return 0
    fi
    
    # Убираем пробелы
    schedule_part=\$(echo "\$schedule_part" | tr -d ' ')
    
    # Разбиваем на части по запятой
    IFS=',' read -ra parts <<< "\$schedule_part"
    
    for part in "\${parts[@]}"; do
        # Проверяем диапазон
        if [[ "\$part" =~ ^([0-9]+)-([0-9]+)\$ ]]; then
            local start=\${BASH_REMATCH[1]}
            local end=\${BASH_REMATCH[2]}
            
            # Для минут и часов: проверяем диапазон
            if [ "\$part_type" = "hour" ] || [ "\$part_type" = "minute" ]; then
                if [ \$start -le \$end ]; then
                    # Обычный диапазон
                    if [ \$current_value -ge \$start ] && [ \$current_value -le \$end ]; then
                        return 0
                    fi
                else
                    # Обратный диапазон (например, 20-8 для ночи)
                    if [ \$current_value -ge \$start ] || [ \$current_value -le \$end ]; then
                        return 0
                    fi
                fi
            else
                # Для дней: обычный диапазон
                if [ \$current_value -ge \$start ] && [ \$current_value -le \$end ]; then
                    return 0
                fi
            fi
        # Проверяем отдельное значение
        elif [[ "\$part" =~ ^[0-9]+\$ ]]; then
            if [ "\$current_value" -eq "\$part" ]; then
                return 0
            fi
        fi
    done
    
    return 1
}

# Функция получения имени события по коду
get_event_name() {
    local evt_id=\$1
    case \$evt_id in
        1) echo "system" ;;          # системные события
        2) echo "critical_error" ;;  # критические ошибки
        3) echo "capture" ;;         # захват видео/аудио
        4) echo "network" ;;         # сетевые клиенты
        5) echo "recording" ;;       # запись на диск
        13) echo "motion_start" ;;   # начало движения
        14) echo "motion_end" ;;     # конец движения
        15|16|17) echo "snapshot" ;; # снапшоты
        22) echo "quality" ;;        # качество изображения
        12|23) echo "video_saved" ;; # видео сохранено
        32) echo "audio_saved" ;;    # аудио сохранено
        *) echo "unknown" ;;
    esac
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

# Определяем режим работы
MODE="event"
CAMERA_NUM=""
EVENT_DATA=""

# Разбираем аргументы
if [ "$1" = "motion" ] && [ -n "$2" ]; then
    # Режим отправки движения
    MODE="motion"
    CAMERA_NUM="$2"
elif [ "$1" = "test" ] && [ -n "$2" ]; then
    # Тестовый режим
    MODE="test"
    CAMERA_NUM="$2"
elif [ "$1" = "event" ]; then
    # Режим обработки события из event-collector
    MODE="event"
    if [ -n "$2" ]; then
        EVENT_DATA="$2"
    fi
elif [ "$1" = "schedule" ]; then
    # Режим проверки расписания
    MODE="schedule"
    if [ -n "$2" ]; then
        CAMERA_NUM="$2"
    fi
else
    # Старый режим для совместимости
    if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
        MODE="motion"
        CAMERA_NUM="$1"
    else
        echo "Использование:" >&2
        echo "  Для движения:   $0 motion <номер_камеры>" >&2
        echo "  Для событий:    $0 event <данные_события>" >&2
        echo "  Для теста:      $0 test <номер_камеры>" >&2
        echo "  Для расписания: $0 schedule [номер_камеры]" >&2
        echo "" >&2
        echo "Доступные камеры в конфигурации:" >&2
        for ((i=0; i<CAMERA_COUNT; i++)); do
            echo "  Камера ${CAMERA_NUMS[$i]}: Чат ${CAMERA_CHAT_IDS[$i]}, Тип: ${CAMERA_MEDIA_TYPES[$i]}" >&2
        done
        exit 1
    fi
fi

# Загрузка настроек для конкретной камеры
if [ "$MODE" = "motion" ] || [ "$MODE" = "test" ] || [ "$MODE" = "schedule" ]; then
    if [ -n "$CAMERA_NUM" ]; then
        if ! get_camera_config "$CAMERA_NUM"; then
            echo "Ошибка: Камера $CAMERA_NUM не найдена в конфигурации" >&2
            exit 1
        fi
        
        # Проверка настроек чата
        if [ -z "$CHAT_ID" ] || [ "$CHAT_ID" = "ВАШ_CHAT_ID_ЗДЕСЬ" ] || [ "$CHAT_ID" = "ОБЩИЙ_ЧАТ" ]; then
            echo "Ошибка: CHAT_ID для камеры $CAMERA_NUM не настроен!" >&2
            echo "Настройте чат для камеры $CAMERA_NUM в конфигурационном файле" >&2
            exit 1
        fi
    fi
fi

# Создание временной директории
mkdir -p "$TEMP_DIR"

# Генерация имен файлов с учетом номера камеры
timestamp=$(date +%s)
IMAGE_FILE="${TEMP_DIR}/cam${CAMERA_NUM}_${timestamp}.jpg"
VIDEO_FILE="${TEMP_DIR}/cam${CAMERA_NUM}_${timestamp}.mjpg"
CONVERTED_VIDEO_FILE="${TEMP_DIR}/cam${CAMERA_NUM}_${timestamp}.mp4"

# Логирование
log_message() {
    local level="$1"
    local message="$2"
    local event_name="${3:-system}"
    
    # Проверяем, нужно ли логировать это событие
    if should_send_event "$event_name" "$level" "$CAMERA_NUM"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $event_name - Камера ${CAMERA_NUM:-N/A} - $message" >> "$LOG_FILE"
        
        # Для уровней warning и выше также отправляем в stderr
        if [ "$level" = "warning" ] || [ "$level" = "error" ] || [ "$level" = "critical" ]; then
            echo "Камера ${CAMERA_NUM:-N/A} ($event_name): $message" >&2
        fi
        
        return 0
    else
        # Только логируем, но не отправляем
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $level - $event_name - Камера ${CAMERA_NUM:-N/A} - $message (не отправлено - вне расписания)" >> "$LOG_FILE"
        return 1
    fi
}

# Проверка доступности Telegram API
check_telegram_api() {
    local response=$(curl -s -w "%{http_code}" "https://api.telegram.org/bot${BOT_TOKEN}/getMe" -o /dev/null)
    if [ "$response" != "200" ]; then
        log_message "error" "Ошибка доступа к Telegram API (HTTP код: $response)" "system"
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
    local url="http://${AVREG_URL}:874/avreg-cgi/jpg/image.cgi?camera=${CAMERA_NUM}&ab=${auth_value}"
    
    log_message "info" "Запрос изображения с камеры $CAMERA_NUM" "capture"
    
    # Используем wget с таймаутом
    wget --timeout=10 --tries=2 -q "$url" -O "$IMAGE_FILE" 2>> "$LOG_FILE"
    local wget_status=$?
    
    if [ $wget_status -eq 0 ] && [ -f "$IMAGE_FILE" ] && [ -s "$IMAGE_FILE" ]; then
        local file_size=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || echo "0")
        log_message "info" "Изображение получено: $IMAGE_FILE (${file_size} байт)" "capture"
        
        # Проверяем, что это действительно изображение
        if file "$IMAGE_FILE" | grep -q "image"; then
            return 0
        else
            log_message "warning" "Полученный файл не является изображением" "capture"
            return 1
        fi
    else
        log_message "error" "Ошибка получения изображения (код: $wget_status)" "capture"
        return 1
    fi
}

# Функция для получения видео с камеры через MJPG поток
get_video() {
    local auth_value=$(get_auth_header)
    
    log_message "info" "Запрос MJPG потока с камеры $CAMERA_NUM (длительность: ${VIDEO_DURATION}сек, FPS: ${VIDEO_FPS})" "capture"
    
    # URL для MJPG потока
    local mjpg_url="http://${AVREG_URL}:874/avreg-cgi/mjpg/video.cgi?camera=${CAMERA_NUM}"
    
    # Добавляем параметр fps
    mjpg_url="${mjpg_url}&fps=${VIDEO_FPS}"
    
    # Добавляем аутентификацию
    mjpg_url="${mjpg_url}&ab=${auth_value}"
    
    log_message "debug" "URL MJPG потока: $(echo $mjpg_url | sed 's/ab=[^&]*/ab=***/')" "capture"
    
    # Удаляем старые временные файлы если есть
    rm -f "$VIDEO_FILE" "$CONVERTED_VIDEO_FILE" 2>/dev/null
    
    # Захватываем MJPG поток через curl с таймаутом
    log_message "info" "Захват MJPG потока..." "capture"
    timeout ${VIDEO_DURATION} curl -s "$mjpg_url" > "$VIDEO_FILE" 2>> "$LOG_FILE"
    local curl_status=$?
    
    if [ ! -f "$VIDEO_FILE" ] || [ ! -s "$VIDEO_FILE" ]; then
        log_message "error" "Не удалось получить MJPG поток (статус curl: $curl_status)" "capture"
        return 1
    fi
    
    local mjpg_size=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
    log_message "info" "MJPG поток сохранен: $VIDEO_FILE (${mjpg_size} байт)" "capture"
    
    # Проверяем, является ли файлом валидным MJPG
    if ! file "$VIDEO_FILE" | grep -q "JPEG" && ! file "$VIDEO_FILE" | grep -q "MJPG" && ! file "$VIDEO_FILE" | grep -q "MPEG"; then
        log_message "warning" "Полученный файл может не быть валидным MJPG потоком" "capture"
        # Не прерываем - возможно все равно можно конвертировать
    fi
    
    # Конвертируем MJPG в MP4 если установлен ffmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        log_message "info" "Конвертация MJPG в MP4 через ffmpeg..." "capture"
        
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
            log_message "info" "Видео сконвертировано в MP4: $CONVERTED_VIDEO_FILE (${mp4_size} байт, сжатие: $((mjpg_size - mp4_size)) байт)" "capture"
            
            # Удаляем оригинальный MJPG файл если конвертация успешна
            rm -f "$VIDEO_FILE" 2>/dev/null
            
            # Используем конвертированный файл для отправки
            VIDEO_FILE="$CONVERTED_VIDEO_FILE"
            return 0
        else
            log_message "warning" "Ошибка конвертации через ffmpeg (код: $ffmpeg_status), используем оригинальный MJPG" "capture"
            
            # Если конвертация не удалась, проверяем размер MJPG файла
            if [ $mjpg_size -gt $VIDEO_MAX_SIZE ]; then
                log_message "warning" "MJPG файл слишком большой ($mjpg_size байт), попытка уменьшить через ffmpeg..." "capture"
                
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
                    log_message "info" "Видео уменьшено: $CONVERTED_VIDEO_FILE (${reduced_size} байт)" "capture"
                    rm -f "$VIDEO_FILE" 2>/dev/null
                    VIDEO_FILE="$CONVERTED_VIDEO_FILE"
                    return 0
                fi
            fi
            
            # Используем оригинальный MJPG файл
            return 0
        fi
    else
        log_message "warning" "ffmpeg не установлен, используем оригинальный MJPG файл" "capture"
        
        # Проверяем размер файла
        if [ $mjpg_size -gt $VIDEO_MAX_SIZE ]; then
            log_message "warning" "MJPG файл слишком большой ($mjpg_size байт > $VIDEO_MAX_SIZE байт)" "capture"
            log_message "info" "Установите ffmpeg для автоматического сжатия видео" "capture"
        fi
        
        return 0
    fi
}

# Функция для отправки сообщения в Telegram
send_telegram_message() {
    local message="$1"
    local event_name="${2:-system}"
    
    # Проверяем, нужно ли отправлять текст для этого события
    get_camera_message_settings "$CAMERA_NUM"
    if [ "$SHOULD_SEND_TEXT" != "true" ]; then
        log_message "debug" "Текстовое сообщение не отправляется (отключено в настройках)" "$event_name"
        return 0
    fi
    
    # Проверяем расписание
    if ! check_schedule "$CAMERA_NUM" "$event_name" "info"; then
        log_message "debug" "Сообщение не отправлено: вне расписания" "$event_name"
        return 1
    fi
    
    if ! check_telegram_api; then
        log_message "error" "Невозможно отправить сообщение: Telegram API недоступен" "$event_name"
        return 1
    fi
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\": \"${CHAT_ID}\", \"text\": \"${message}\"}" \
        -w "%{http_code}")
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "info" "Сообщение отправлено: ${message:0:50}..." "$event_name"
        return 0
    else
        log_message "error" "Ошибка отправки сообщения" "$event_name"
        log_message "debug" "HTTP код: $http_code" "$event_name"
        log_message "debug" "Ответ: $json_response" "$event_name"
        
        # Анализ ошибки
        if echo "$json_response" | grep -q '"error_code":400'; then
            log_message "warning" "Неверный запрос (возможно неверный CHAT_ID)" "$event_name"
        elif echo "$json_response" | grep -q '"error_code":401'; then
            log_message "error" "Неверный токен бота" "$event_name"
        elif echo "$json_response" | grep -q '"error_code":403'; then
            log_message "warning" "Бот заблокирован пользователем или не в чате" "$event_name"
        elif echo "$json_response" | grep -q '"error_code":404'; then
            log_message "error" "Чат не найден" "$event_name"
        fi
        
        return 1
    fi
}

# Функция для отправки фото в Telegram
send_telegram_photo() {
    local event_name="${1:-motion}"
    
    # Проверяем, нужно ли отправлять медиа для этого события
    get_camera_message_settings "$CAMERA_NUM"
    if [ "$SHOULD_SEND_MEDIA" != "true" ]; then
        log_message "debug" "Медиа не отправляется (отключено в настройках)" "$event_name"
        return 0
    fi
    
    if [ ! -f "$IMAGE_FILE" ] || [ ! -s "$IMAGE_FILE" ]; then
        log_message "warning" "Файл изображения не существует или пуст" "$event_name"
        return 1
    fi
    
    # Проверяем расписание
    if ! check_schedule "$CAMERA_NUM" "$event_name" "info"; then
        log_message "debug" "Фото не отправлено: вне расписания" "$event_name"
        return 1
    fi
    
    if ! check_telegram_api; then
        return 1
    fi
    
    log_message "info" "Отправка фото в Telegram..." "$event_name"
    
    # Определяем подпись к фото
    local caption=""
    if [ "$SHOULD_SEND_TEXT" = "true" ]; then
        caption="📸 Камера ${CAMERA_NUM}: Движение обнаружено ($(date '+%Y-%m-%d %H:%M:%S'))"
    fi
    
    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        -F "chat_id=${CHAT_ID}" \
        -F "photo=@${IMAGE_FILE}" \
        -F "caption=${caption}" \
        -w "%{http_code}")
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "info" "Фото успешно отправлено" "$event_name"
        return 0
    else
        log_message "error" "Ошибка отправки фото" "$event_name"
        log_message "debug" "HTTP код: $http_code" "$event_name"
        log_message "debug" "Ответ: $json_response" "$event_name"
        return 1
    fi
}

# Функция для отправки видео в Telegram
send_telegram_video() {
    local event_name="${1:-motion}"
    
    # Проверяем, нужно ли отправлять медиа для этого события
    get_camera_message_settings "$CAMERA_NUM"
    if [ "$SHOULD_SEND_MEDIA" != "true" ]; then
        log_message "debug" "Медиа не отправляется (отключено в настройках)" "$event_name"
        return 0
    fi
    
    if [ ! -f "$VIDEO_FILE" ] || [ ! -s "$VIDEO_FILE" ]; then
        log_message "warning" "Файл видео не существует или пуст" "$event_name"
        return 1
    fi
    
    # Проверяем расписание
    if ! check_schedule "$CAMERA_NUM" "$event_name" "info"; then
        log_message "debug" "Видео не отправлено: вне расписания" "$event_name"
        return 1
    fi
    
    if ! check_telegram_api; then
        return 1
    fi
    
    local file_size=$(stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
    local file_ext="${VIDEO_FILE##*.}"
    
    log_message "info" "Попытка отправки видео (размер: ${file_size} байт, расширение: $file_ext, тип: $(file -b --mime-type "$VIDEO_FILE" 2>/dev/null || echo 'unknown'))" "$event_name"
    
    # Определяем подпись к видео
    local caption=""
    if [ "$SHOULD_SEND_TEXT" = "true" ]; then
        caption="🎥 Камера ${CAMERA_NUM}: Видео ${VIDEO_DURATION}сек ($(date '+%Y-%m-%d %H:%M:%S'))"
    fi
    
    local response=""
    local success=0
    
    # Определяем тип файла для отправки
    if [ "$file_ext" = "mjpg" ] || [ "$file_ext" = "mjpeg" ]; then
        # MJPG файлы отправляем как документ
        log_message "info" "Отправляем MJPG как документ" "$event_name"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=${caption}" \
            -w "%{http_code}")
    elif [[ "$file_size" -gt $VIDEO_MAX_SIZE ]]; then
        # Большие файлы отправляем как документ
        log_message "info" "Отправляем как документ (большой размер: ${file_size} байт)" "$event_name"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=${caption}" \
            -w "%{http_code}")
    elif [ "$file_ext" = "mp4" ] || file "$VIDEO_FILE" | grep -q "MP4"; then
        # MP4 файлы отправляем как видео
        log_message "info" "Отправляем MP4 как видео" "$event_name"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendVideo" \
            -F "chat_id=${CHAT_ID}" \
            -F "video=@${VIDEO_FILE}" \
            -F "caption=${caption}" \
            -w "%{http_code}")
    else
        # Остальные форматы как документ
        log_message "info" "Отправляем как документ (неизвестный формат: $file_ext)" "$event_name"
        
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${VIDEO_FILE}" \
            -F "caption=${caption}" \
            -w "%{http_code}")
    fi
    
    local http_code=${response: -3}
    local json_response=${response%???}
    
    if [ "$http_code" = "200" ] && echo "$json_response" | grep -q '"ok":true'; then
        log_message "info" "Видео успешно отправлено" "$event_name"
        return 0
    else
        log_message "error" "Ошибка отправки видео" "$event_name"
        log_message "debug" "HTTP код: $http_code" "$event_name"
        log_message "debug" "Ответ: $json_response" "$event_name"
        
        # Если не получилось отправить как видео, пробуем как документ
        if [ "$file_ext" = "mp4" ] && [ $success -eq 0 ]; then
            log_message "warning" "Пробуем отправить MP4 как документ..." "$event_name"
            
            response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
                -F "chat_id=${CHAT_ID}" \
                -F "document=@${VIDEO_FILE}" \
                -F "caption=${caption}" \
                -w "%{http_code}")
            
            local http_code2=${response: -3}
            local json_response2=${response%???}
            
            if [ "$http_code2" = "200" ] && echo "$json_response2" | grep -q '"ok":true'; then
                log_message "info" "Видео отправлено как документ" "$event_name"
                return 0
            else
                log_message "error" "Ошибка отправки как документ" "$event_name"
                return 1
            fi
        fi
        
        return 1
    fi
}

# Обработка события движения
process_motion_event() {
    log_message "info" "=== Обработка события движения на камере $CAMERA_NUM ===" "motion"
    
    # Проверяем доступность Telegram
    if ! check_telegram_api; then
        log_message "error" "Telegram API недоступен, пропускаем отправку" "motion"
        return 1
    fi
    
    # Проверяем, нужно ли отправлять событие движения
    if ! should_send_event "motion" "info" "$CAMERA_NUM"; then
        log_message "debug" "Событие движения не отправляется (вне расписания или настройки фильтрации)" "motion"
        return 0
    fi
    
    # Отправляем текстовое уведомление (если включено)
    local message="🚨 Камера ${CAMERA_NUM}: Движение обнаружено в $(date '+%H:%M:%S')"
    if ! send_telegram_message "$message" "motion"; then
        log_message "warning" "Не удалось отправить текстовое уведомление" "motion"
        # Не прерываем выполнение, пробуем отправить медиа
    fi
    
    # Проверяем, нужно ли отправлять медиа для этой камеры
    get_camera_message_settings "$CAMERA_NUM"
    
    if [ "$SHOULD_SEND_MEDIA" = "true" ]; then
        # Обработка в зависимости от выбранного типа медиа
        case $MEDIA_TYPE in
            "photo")
                if get_image; then
                    send_telegram_photo "motion"
                fi
                ;;
            
            "video")
                # Небольшая задержка перед захватом видео
                sleep 1
                if get_video; then
                    send_telegram_video "motion"
                fi
                ;;
            
            "both")
                if get_image; then
                    send_telegram_photo "motion"
                fi
                
                # Небольшая задержка перед захватом видео
                sleep 1
                
                if get_video; then
                    send_telegram_video "motion"
                fi
                ;;
        esac
    else
        log_message "info" "Отправка медиа отключена для камеры $CAMERA_NUM" "motion"
    fi
    
    # Очистка временных файлов
    cleanup_temp_files
    
    log_message "info" "=== Обработка события движения завершена ===" "motion"
}

# Обработка системного события из event-collector
process_system_event() {
    local event_data="$1"
    
    # Парсим данные события
    IFS='|' read -ra event_parts <<< "$event_data"
    
    local event_id="${event_parts[0]}"
    local camera_num="${event_parts[1]}"
    local dt_event="${event_parts[2]}"
    local dt_prev="${event_parts[3]}"
    local status="${event_parts[4]}"
    local subsystem="${event_parts[5]}"
    local media_type="${event_parts[6]}"
    local description="${event_parts[7]}"
    
    # Определяем название события
    local event_name=$(get_event_name "$event_id")
    local level="info"
    
    # Определяем уровень важности
    case $event_id in
        1|2) # Системные события и критические ошибки
            if [ "$status" = "3" ] || [ "$event_id" = "2" ]; then
                level="critical"
            else
                level="info"
            fi
            ;;
        3) # Захват видео
            if [ "$status" = "3" ]; then
                level="error"
            else
                level="info"
            fi
            ;;
        5) # Запись
            level="warning"
            ;;
        13|14) # Движение
            level="info"
            ;;
        22) # Качество
            level="warning"
            ;;
        *) # Остальные
            level="info"
            ;;
    esac
    
    # Устанавливаем номер камеры для логирования
    CAMERA_NUM="$camera_num"
    
    # Получаем конфигурацию камеры
    if [ -n "$camera_num" ] && [ "$camera_num" != "0" ]; then
        if get_camera_config "$camera_num" 2>/dev/null; then
            # Проверяем, нужно ли отправлять это событие
            if ! should_send_event "$event_name" "$level" "$camera_num"; then
                log_message "debug" "Событие $event_name не отправляется (вне расписания или настройки фильтрации)" "$event_name"
                return 0
            fi
            
            # Проверяем доступность Telegram
            if ! check_telegram_api; then
                log_message "error" "Telegram API недоступен, пропускаем отправку" "$event_name"
                return 1
            fi
            
            # Формируем сообщение в зависимости от типа события
            local message=""
            local emoji=""
            
            case $event_id in
                1) # Системные события
                    case $status in
                        0) message="🟢 Система Avreg запущена"; emoji="🟢" ;;
                        1) message="🔴 Система Avreg остановлена"; emoji="🔴" ;;
                        2) message="🔄 Перезагрузка конфигурации"; emoji="🔄" ;;
                        3) message="🚨 Критическая ошибка: $description"; emoji="🚨" ;;
                    esac
                    ;;
                2) # Критические ошибки
                    message="🚨 Критическая ошибка: $description"
                    emoji="🚨"
                    ;;
                3) # Захват видео
                    case $status in
                        0) message="🎥 Камера $camera_num: Захват начат"; emoji="🎥" ;;
                        1) message="⏹️ Камера $camera_num: Захват остановлен"; emoji="⏹️" ;;
                        3) message="❌ Камера $camera_num: Ошибка захвата: $description"; emoji="❌" ;;
                    esac
                    ;;
                4) # Сетевые клиенты
                    case $status in
                        0) message="📡 Камера $camera_num: Новый клиент подключен"; emoji="📡" ;;
                        1) message="📡 Камера $camera_num: Клиент отключен"; emoji="📡" ;;
                    esac
                    ;;
                5) # Запись
                    case $status in
                        4) message="⏺️ Камера $camera_num: Запись начата"; emoji="⏺️" ;;
                        3) message="⏹️ Камера $camera_num: Запись остановлена"; emoji="⏹️" ;;
                        6) message="✅ Камера $camera_num: Запись включена"; emoji="✅" ;;
                        7) message="⭕ Камера $camera_num: Запись отключена"; emoji="⭕" ;;
                    esac
                    ;;
                13) # Начало движения
                    message="🚨 Камера $camera_num: Движение обнаружено"
                    emoji="🚨"
                    ;;
                14) # Конец движения
                    message="✅ Камера $camera_num: Движение прекратилось"
                    emoji="✅"
                    ;;
                15|16|17) # Снапшоты
                    message="📸 Камера $camera_num: Снапшот сохранен"
                    emoji="📸"
                    ;;
                22) # Качество изображения
                    message="📊 Камера $camera_num: Изменение качества: $description"
                    emoji="📊"
                    ;;
                12|23) # Видео сохранено
                    message="💾 Камера $camera_num: Видеофайл сохранен"
                    emoji="💾"
                    ;;
                32) # Аудио сохранено
                    message="🎵 Камера $camera_num: Аудиофайл сохранен"
                    emoji="🎵"
                    ;;
                *)
                    message="ℹ️ Камера $camera_num: Событие $event_id: $description"
                    emoji="ℹ️"
                    ;;
            esac
            
            # Добавляем время события
            if [ -n "$dt_event" ]; then
                message="$message (время: $dt_event)"
            fi
            
            # Отправляем сообщение (если включена отправка текста)
            get_camera_message_settings "$camera_num"
            if [ "$SHOULD_SEND_TEXT" = "true" ]; then
                send_telegram_message "$message" "$event_name"
            else
                log_message "debug" "Текстовое сообщение для события $event_name не отправлено (отключено в настройках)" "$event_name"
            fi
            
            # Логируем событие
            log_message "$level" "Событие $event_name: $description" "$event_name"
        else
            # Камера не найдена в конфигурации
            log_message "debug" "Камера $camera_num не найдена в конфигурации, событие пропущено" "$event_name"
        fi
    else
        # Системное событие без камеры
        if should_send_event "$event_name" "$level" ""; then
            # Формируем сообщение для системных событий
            local message=""
            case $event_id in
                1)
                    case $status in
                        0) message="🟢 Система Avreg запущена" ;;
                        1) message="🔴 Система Avreg остановлена" ;;
                        2) message="🔄 Перезагрузка конфигурации" ;;
                        3) message="🚨 Критическая ошибка: $description" ;;
                    esac
                    ;;
                2)
                    message="🚨 Критическая ошибка: $description"
                    ;;
            esac
            
            if [ -n "$message" ]; then
                # Используем первый чат для системных сообщений
                if [ $CAMERA_COUNT -gt 0 ]; then
                    CHAT_ID="${CAMERA_CHAT_IDS[0]}"
                    if [ "$CHAT_ID" != "ВАШ_CHAT_ID_ЗДЕСЬ" ] && [ "$CHAT_ID" != "ОБЩИЙ_ЧАТ" ]; then
                        # Для системных событий проверяем расписание и настройки отправки
                        get_camera_message_settings ""
                        if [ "$SHOULD_SEND_TEXT" = "true" ]; then
                            if check_schedule "" "$event_name" "$level"; then
                                if check_telegram_api; then
                                    send_telegram_message "$message" "$event_name"
                                fi
                            else
                                log_message "debug" "Системное событие не отправлено: вне расписания" "$event_name"
                            fi
                        else
                            log_message "debug" "Системное событие не отправлено: текст отключен" "$event_name"
                        fi
                    fi
                fi
            fi
            
            log_message "$level" "Системное событие: $description" "$event_name"
        fi
    fi
}

# Проверка расписания (режим отладки)
check_schedule_mode() {
    echo "=== Проверка расписания ==="
    echo ""
    
    local camera_num="$1"
    local current_day=$(date +%w)
    local current_hour=$(date +%H)
    local current_minute=$(date +%M)
    local current_date=$(date +%Y-%m-%d)
    
    echo "Текущее время:"
    echo "  Дата: $current_date"
    echo "  День недели: $current_day (0=воскресенье)"
    echo "  Час: $current_hour"
    echo "  Минута: $current_minute"
    echo ""
    
    if [ -n "$camera_num" ]; then
        echo "Проверка для камеры $camera_num:"
        if get_camera_config "$camera_num" 2>/dev/null; then
            echo "  Чат ID: $CHAT_ID"
            echo "  Расписание: $CAMERA_SCHEDULE"
            
            # Проверяем расписание
            if check_schedule "$camera_num" "test" "info"; then
                echo "  ✅ Время в расписании - отправка разрешена"
            else
                echo "  ❌ Время вне расписания - отправка запрещена"
            fi
        else
            echo "  ❌ Камера не найдена в конфигурации"
        fi
    else
        echo "Общие настройки расписания:"
        echo "  Тип: $SCHEDULE_TYPE"
        echo "  Дни: $SCHEDULE_DAYS"
        echo "  Часы: $SCHEDULE_HOURS"
        echo "  Минуты: $SCHEDULE_MINUTES"
        
        if [ -n "$SCHEDULE_EXCLUDE_DATES" ]; then
            echo "  Исключения: $SCHEDULE_EXCLUDE_DATES"
        fi
        
        echo ""
        echo "Проверка общего расписания:"
        if check_schedule "" "test" "info"; then
            echo "  ✅ Время в расписании - отправка разрешена"
        else
            echo "  ❌ Время вне расписания - отправка запрещена"
        fi
        
        echo ""
        echo "Проверка всех камер:"
        for ((i=0; i<CAMERA_COUNT; i++)); do
            local cam_num=${CAMERA_NUMS[$i]}
            local chat_id=${CAMERA_CHAT_IDS[$i]}
            local schedule=${CAMERA_SCHEDULES[$i]}
            
            if [ "$chat_id" != "ВАШ_CHAT_ID_ЗДЕСЬ" ] && [ "$chat_id" != "ОБЩИЙ_ЧАТ" ]; then
                echo "  Камера $cam_num:"
                echo "    Расписание: $schedule"
                
                if check_schedule "$cam_num" "test" "info"; then
                    echo "    ✅ Время в расписании"
                else
                    echo "    ❌ Время вне расписания"
                fi
            fi
        done
    fi
    
    echo ""
    echo "Настройки отправки критических ошибок:"
    echo "  Отправлять критические ошибки всегда: $SEND_CRITICAL_ALWAYS"
    
    # Тест с разными уровнями событий
    echo ""
    echo "Тест различных уровней событий:"
    for level in "info" "warning" "error" "critical"; do
        if check_schedule "$camera_num" "test" "$level"; then
            echo "  $level: ✅ Отправка разрешена"
        else
            echo "  $level: ❌ Отправка запрещена"
        fi
    done
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
case "$MODE" in
    "motion")
        process_motion_event
        ;;
    "test")
        # Тестовый режим
        echo "=== ТЕСТОВЫЙ РЕЖИМ ДЛЯ КАМЕРЫ $CAMERA_NUM ===" >&2
        echo "Конфигурация:" >&2
        echo "  Бот: $(echo ${BOT_TOKEN:0:10})..." >&2
        echo "  Чат ID: $CHAT_ID" >&2
        echo "  Камера: $CAMERA_NUM" >&2
        echo "  Тип медиа: $MEDIA_TYPE" >&2
        echo "  Длительность видео: ${VIDEO_DURATION}сек" >&2
        echo "  FPS видео: ${VIDEO_FPS}" >&2
        echo "  Расписание: $CAMERA_SCHEDULE" >&2
        
        # Получаем настройки отправки для камеры
        get_camera_message_settings "$CAMERA_NUM"
        echo "  Отправка текста: $SHOULD_SEND_TEXT" >&2
        echo "  Отправка медиа: $SHOULD_SEND_MEDIA" >&2
        
        # Проверяем расписание
        if ! check_schedule "$CAMERA_NUM" "test" "info"; then
            echo "⚠️  ВНИМАНИЕ: Текущее время вне расписания!" >&2
            echo "   Тестовое сообщение будет отправлено, но реальные события - нет." >&2
            echo "" >&2
        fi
        
        # Тестовая отправка сообщения (если включена отправка текста)
        if [ "$SHOULD_SEND_TEXT" = "true" ]; then
            send_telegram_message "🔧 Камера ${CAMERA_NUM}: Тестовое сообщение от системы Avreg. Если вы видите это, все работает правильно!" "test"
            
            if [ $? -eq 0 ]; then
                echo "✅ Тестовое сообщение отправлено успешно!" >&2
            else
                echo "❌ Ошибка отправки тестового сообщения" >&2
            fi
        else
            echo "⚠️  Отправка текстовых сообщений отключена для этой камеры" >&2
        fi
        
        # Тестовая отправка медиа (если включена отправка медиа)
        if [ "$SHOULD_SEND_MEDIA" = "true" ]; then
            case $MEDIA_TYPE in
                "photo")
                    echo "Отправка тестового фото..." >&2
                    if get_image; then
                        send_telegram_photo "test"
                        echo "✅ Тестовое фото отправлено!" >&2
                    else
                        echo "❌ Ошибка получения тестового фото" >&2
                    fi
                    ;;
                "video")
                    echo "Отправка тестового видео..." >&2
                    if get_video; then
                        send_telegram_video "test"
                        echo "✅ Тестовое видео отправлено!" >&2
                    else
                        echo "❌ Ошибка получения тестового видео" >&2
                    fi
                    ;;
                "both")
                    echo "Отправка тестового фото и видео..." >&2
                    if get_image; then
                        send_telegram_photo "test"
                        echo "✅ Тестовое фото отправлено!" >&2
                    else
                        echo "❌ Ошибка получения тестового фото" >&2
                    fi
                    
                    sleep 1
                    
                    if get_video; then
                        send_telegram_video "test"
                        echo "✅ Тестовое видео отправлено!" >&2
                    else
                        echo "❌ Ошибка получения тестового видео" >&2
                    fi
                    ;;
            esac
        else
            echo "⚠️  Отправка медиа отключена для этой камеры" >&2
        fi
        
        echo "Проверьте чат Telegram" >&2
        echo "Смотрите подробности в логе: $LOG_FILE" >&2
        
        # Очистка
        cleanup_temp_files
        ;;
    "event")
        # Обработка события из event-collector
        if [ -n "$EVENT_DATA" ]; then
            process_system_event "$EVENT_DATA"
        else
            echo "Ошибка: Не переданы данные события" >&2
            exit 1
        fi
        ;;
    "schedule")
        # Проверка расписания
        check_schedule_mode "$CAMERA_NUM"
        ;;
esac

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
# Версия 1.5 - Добавлена настройка отправки только медиа без текста

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

# Функция для редактирования общих настроек отправки сообщений
edit_message_settings() {
    echo ""
    echo "=== Редактирование общих настроек отправки сообщений ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие настройки:"
    echo "  Отправлять текст: $SEND_TEXT"
    echo "  Отправлять медиа: $SEND_MEDIA"
    echo ""
    
    echo "Выберите режим отправки:"
    echo "1) Отправлять и текст, и медиа"
    echo "2) Отправлять только медиа (без текста)"
    echo "3) Отправлять только текст (без медиа)"
    read -p "Ваш выбор (1-3): " message_choice
    
    case $message_choice in
        1)
            SEND_TEXT="true"
            SEND_MEDIA="true"
            echo "✅ Настройки обновлены: будут отправляться и текст, и медиа"
            ;;
        2)
            SEND_TEXT="false"
            SEND_MEDIA="true"
            echo "✅ Настройки обновлены: будут отправляться только медиа (без текста)"
            ;;
        3)
            SEND_TEXT="true"
            SEND_MEDIA="false"
            echo "✅ Настройки обновлены: будут отправляться только текстовые уведомления"
            ;;
        *)
            echo "❌ Неверный выбор"
            return 1
            ;;
    esac
    
    # Обновляем конфигурацию
    sed -i "s/^SEND_TEXT='.*'/SEND_TEXT='$SEND_TEXT'/" "$CONFIG_FILE"
    sed -i "s/^SEND_MEDIA='.*'/SEND_MEDIA='$SEND_MEDIA'/" "$CONFIG_FILE"
}

# Функция для редактирования настроек отправки для конкретной камеры
edit_camera_message_settings() {
    echo ""
    echo "=== Редактирование настроек отправки для камеры ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        local send_text_display="общие"
        local send_media_display="общие"
        
        if [ "${CAMERA_SEND_TEXT[$i]}" != "GENERAL" ]; then
            send_text_display="${CAMERA_SEND_TEXT[$i]}"
        fi
        if [ "${CAMERA_SEND_MEDIA[$i]}" != "GENERAL" ]; then
            send_media_display="${CAMERA_SEND_MEDIA[$i]}"
        fi
        
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: Текст=$send_text_display, Медиа=$send_media_display"
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
    echo "Редактирование настроек отправки для камеры $camera_num"
    echo ""
    echo "Выберите режим отправки для этой камеры:"
    echo "1) Использовать общие настройки"
    echo "2) Отправлять и текст, и медиа"
    echo "3) Отправлять только медиа (без текста)"
    echo "4) Отправлять только текст (без медиа)"
    read -p "Ваш выбор (1-4): " camera_message_choice
    
    case $camera_message_choice in
        1)
            NEW_SEND_TEXT="GENERAL"
            NEW_SEND_MEDIA="GENERAL"
            ;;
        2)
            NEW_SEND_TEXT="true"
            NEW_SEND_MEDIA="true"
            ;;
        3)
            NEW_SEND_TEXT="false"
            NEW_SEND_MEDIA="true"
            ;;
        4)
            NEW_SEND_TEXT="true"
            NEW_SEND_MEDIA="false"
            ;;
        *)
            echo "❌ Неверный выбор"
            return 1
            ;;
    esac
    
    # Обновляем массивы
    # Обновляем SEND_TEXT
    awk -v idx="$array_index" -v new_val="$NEW_SEND_TEXT" '
    /^declare -a CAMERA_SEND_TEXT=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_SEND_TEXT=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_val "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_SEND_TEXT=(" array_line ")"
            print "  \"" new_val "\")"
        } else {
            print "declare -a CAMERA_SEND_TEXT=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    # Обновляем SEND_MEDIA
    awk -v idx="$array_index" -v new_val="$NEW_SEND_MEDIA" '
    /^declare -a CAMERA_SEND_MEDIA=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_SEND_MEDIA=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_val "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_SEND_MEDIA=(" array_line ")"
            print "  \"" new_val "\")"
        } else {
            print "declare -a CAMERA_SEND_MEDIA=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ Настройки отправки для камеры $camera_num обновлены"
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
    awk -v idx="$array_index" -v new_chat="$NEW_CHAT_ID" '
    /^declare -a CAMERA_CHAT_IDS=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_CHAT_IDS=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_chat "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
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

# Функция для редактирования расписания
edit_schedule() {
    echo ""
    echo "=== Редактирование расписания ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие настройки расписания:"
    echo "  Включено: $SCHEDULE_ENABLED"
    echo "  Тип: $SCHEDULE_TYPE"
    echo "  Дни: $SCHEDULE_DAYS"
    echo "  Часы: $SCHEDULE_HOURS"
    echo "  Минуты: $SCHEDULE_MINUTES"
    
    if [ -n "$SCHEDULE_EXCLUDE_DATES" ]; then
        echo "  Исключения: $SCHEDULE_EXCLUDE_DATES"
    fi
    
    echo "  Отправлять критические ошибки всегда: $SEND_CRITICAL_ALWAYS"
    echo ""
    
    echo "Выберите действие:"
    echo "1) Включить/отключить расписание"
    echo "2) Изменить дни недели"
    echo "3) Изменить часы"
    echo "4) Изменить минуты"
    echo "5) Изменить исключения"
    echo "6) Настройка отправки критических ошибок"
    echo "7) Вернуться в меню"
    read -p "Ваш выбор (1-7): " schedule_choice
    
    case $schedule_choice in
        1)
            echo ""
            echo "Текущее состояние: $SCHEDULE_ENABLED"
            echo "Включить расписание? (true/false):"
            read new_enabled
            
            if [ "$new_enabled" = "true" ] || [ "$new_enabled" = "false" ]; then
                sed -i "s/^SCHEDULE_ENABLED='.*'/SCHEDULE_ENABLED='$new_enabled'/" "$CONFIG_FILE"
                echo "✅ Расписание обновлено: $new_enabled"
            else
                echo "❌ Неверное значение"
            fi
            ;;
        2)
            echo ""
            echo "Текущие дни: $SCHEDULE_DAYS"
            echo ""
            echo "Выберите дни недели для отправки уведомлений:"
            echo "0) Воскресенье"
            echo "1) Понедельник"
            echo "2) Вторник"
            echo "3) Среда"
            echo "4) Четверг"
            echo "5) Пятница"
            echo "6) Суббота"
            echo "7) Все дни"
            echo ""
            echo "Введите номера дней через запятую (например: 1,2,3,4,5 для рабочих дней):"
            read new_days
            
            if [ -n "$new_days" ]; then
                if [[ "$new_days" =~ ^[0-6](,[0-6])*$ ]] || [ "$new_days" = "7" ]; then
                    if [ "$new_days" = "7" ]; then
                        new_days="0,1,2,3,4,5,6"
                    fi
                    sed -i "s/^SCHEDULE_DAYS='.*'/SCHEDULE_DAYS='$new_days'/" "$CONFIG_FILE"
                    echo "✅ Дни недели обновлены: $new_days"
                else
                    echo "❌ Неверный формат дней"
                fi
            fi
            ;;
        3)
            echo ""
            echo "Текущие часы: $SCHEDULE_HOURS"
            echo ""
            echo "Введите новые часы:"
            echo "Формат: отдельные часы через запятую (0,1,2) или диапазон (8-17)"
            echo "Можно комбинировать: 0-5,8,12-14,18-23"
            read new_hours
            
            if [ -n "$new_hours" ]; then
                sed -i "s/^SCHEDULE_HOURS='.*'/SCHEDULE_HOURS='$new_hours'/" "$CONFIG_FILE"
                echo "✅ Часы обновлены: $new_hours"
            fi
            ;;
        4)
            echo ""
            echo "Текущие минуты: $SCHEDULE_MINUTES"
            echo ""
            echo "Введите новые минуты:"
            echo "Формат: отдельные минуты через запятую (0,15,30,45) или диапазон (0-30)"
            echo "Можно комбинировать: 0-15,30,45-59"
            read new_minutes
            
            if [ -n "$new_minutes" ]; then
                sed -i "s/^SCHEDULE_MINUTES='.*'/SCHEDULE_MINUTES='$new_minutes'/" "$CONFIG_FILE"
                echo "✅ Минуты обновлены: $new_minutes"
            fi
            ;;
        5)
            echo ""
            echo "Текущие исключения: ${SCHEDULE_EXCLUDE_DATES:-нет}"
            echo ""
            echo "Введите даты исключений в формате ГГГГ-ММ-ДД, через запятую:"
            echo "Пример: 2024-01-01,2024-01-07,2024-05-01"
            echo "(оставьте пустым для удаления исключений)"
            read new_exclude
            
            if [ -z "$new_exclude" ]; then
                sed -i "s/^SCHEDULE_EXCLUDE_DATES='.*'/SCHEDULE_EXCLUDE_DATES=''/" "$CONFIG_FILE"
                echo "✅ Исключения удалены"
            else
                sed -i "s/^SCHEDULE_EXCLUDE_DATES='.*'/SCHEDULE_EXCLUDE_DATES='$new_exclude'/" "$CONFIG_FILE"
                echo "✅ Исключения обновлены: $new_exclude"
            fi
            ;;
        6)
            echo ""
            echo "Текущая настройка: $SEND_CRITICAL_ALWAYS"
            echo "Отправлять критические ошибки всегда? (true/false):"
            read new_critical
            
            if [ "$new_critical" = "true" ] || [ "$new_critical" = "false" ]; then
                sed -i "s/^SEND_CRITICAL_ALWAYS='.*'/SEND_CRITICAL_ALWAYS='$new_critical'/" "$CONFIG_FILE"
                echo "✅ Настройка критических ошибок обновлена: $new_critical"
            else
                echo "❌ Неверное значение"
            fi
            ;;
        7)
            return 0
            ;;
        *)
            echo "❌ Неверный выбор"
            ;;
    esac
    
    return 0
}

# Функция для редактирования расписания камеры
edit_camera_schedule() {
    echo ""
    echo "=== Редактирование расписания камеры ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: Расписание ${CAMERA_SCHEDULES[$i]}"
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
    local current_schedule=${CAMERA_SCHEDULES[$array_index]}
    
    echo ""
    echo "Редактирование расписания для камеры $camera_num"
    echo "Текущее расписание: $current_schedule"
    echo ""
    echo "Выберите настройки расписания:"
    echo "1) Использовать общее расписание (GENERAL)"
    echo "2) Всегда отправлять (ALWAYS)"
    echo "3) Настроить индивидуальное расписание"
    read -p "Ваш выбор (1-3): " schedule_choice
    
    case $schedule_choice in
        1)
            NEW_SCHEDULE="GENERAL"
            ;;
        2)
            NEW_SCHEDULE="ALWAYS"
            ;;
        3)
            echo ""
            echo "=== Индивидуальное расписание для камеры $camera_num ==="
            
            # Настройка дней недели
            echo "Введите дни недели (0-6 через запятую, 7=все дни):"
            read camera_days
            camera_days=${camera_days:-"0,1,2,3,4,5,6"}
            
            # Настройка часов
            echo "Введите часы (формат: 0-23 или 8-20 или 0,1,2):"
            read camera_hours
            camera_hours=${camera_hours:-"0-23"}
            
            # Настройка минут
            echo "Введите минуты (формат: 0-59 или 0,15,30,45):"
            read camera_minutes
            camera_minutes=${camera_minutes:-"0-59"}
            
            NEW_SCHEDULE="days:$camera_days;hours:$camera_hours;minutes:$camera_minutes"
            ;;
        *)
            echo "❌ Неверный выбор"
            return 1
            ;;
    esac
    
    # Обновляем массив
    awk -v idx="$array_index" -v new_schedule="$NEW_SCHEDULE" '
    /^declare -a CAMERA_SCHEDULES=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_SCHEDULES=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_schedule "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_SCHEDULES=(" array_line ")"
            print "  \"" new_schedule "\")"
        } else {
            print "declare -a CAMERA_SCHEDULES=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ Расписание камеры $camera_num обновлено на: $NEW_SCHEDULE"
}

# Функция для редактирования событий
edit_events() {
    echo ""
    echo "=== Редактирование настроек событий ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие настройки событий:"
    echo "Типы событий: ${EVENT_TYPES[@]}"
    echo "Уровень логирования: $LOG_LEVEL"
    echo ""
    
    echo "Какие события отправлять в Telegram?"
    echo ""
    echo "Основные события:"
    echo "1) Движение (motion) - обнаружение движения"
    echo "2) Захват видео (capture) - статус захвата видео"
    echo "3) Ошибки (errors) - критические ошибки системы"
    echo "4) Запись (recording) - статус записи видео"
    echo "5) Сохранение файлов (files) - сохранение видео/фото"
    echo "6) Качество изображения (quality) - изменения качества"
    echo "7) Сеть (network) - подключение клиентов"
    echo "8) Все события (all)"
    echo "9) Только движение (только motion)"
    echo ""
    
    echo "Текущие события: ${EVENT_TYPES[@]}"
    echo "Введите новые типы событий (через запятую, например: 1,3,5):"
    read events_input
    
    if [ -z "$events_input" ]; then
        echo "❌ Необходимо выбрать хотя бы одно событие"
        return 1
    fi
    
    # Преобразуем строку в массив названий
    IFS=',' read -ra events_array <<< "$events_input"
    declare -a new_event_types=()
    
    for event_num in "${events_array[@]}"; do
        case $event_num in
            1) new_event_types+=("motion") ;;
            2) new_event_types+=("capture") ;;
            3) new_event_types+=("errors") ;;
            4) new_event_types+=("recording") ;;
            5) new_event_types+=("files") ;;
            6) new_event_types+=("quality") ;;
            7) new_event_types+=("network") ;;
            8) new_event_types+=("all") ;;
            9) new_event_types+=("motion_only") ;;
            *) echo "❌ Неверный номер события: $event_num"; return 1 ;;
        esac
    done
    
    # Обновляем уровень логирования
    echo ""
    echo "Текущий уровень логирования: $LOG_LEVEL"
    echo "Выберите новый уровень важности для отправки:"
    echo "1) DEBUG - отладочная информация"
    echo "2) INFO - информационные сообщения"
    echo "3) WARNING - предупреждения"
    echo "4) ERROR - ошибки"
    echo "5) CRITICAL - критические ошибки"
    read -p "Ваш выбор (1-5): " log_level
    
    case $log_level in
        1) NEW_LOG_LEVEL="DEBUG" ;;
        2) NEW_LOG_LEVEL="INFO" ;;
        3) NEW_LOG_LEVEL="WARNING" ;;
        4) NEW_LOG_LEVEL="ERROR" ;;
        5) NEW_LOG_LEVEL="CRITICAL" ;;
        *) NEW_LOG_LEVEL="$LOG_LEVEL" ;;
    esac
    
    # Обновляем конфигурацию
    # Сначала обновляем массив событий
    local event_types_str=$(printf "'%s' " "${new_event_types[@]}")
    sed -i "s/^EVENT_TYPES=(.*)/EVENT_TYPES=($event_types_str)/" "$CONFIG_FILE"
    
    # Обновляем уровень логирования
    sed -i "s/^LOG_LEVEL='.*'/LOG_LEVEL='$NEW_LOG_LEVEL'/" "$CONFIG_FILE"
    
    echo "✅ Настройки событий обновлены"
    echo "   Типы событий: ${new_event_types[@]}"
    echo "   Уровень логирования: $NEW_LOG_LEVEL"
}

# Функция для редактирования событий камеры
edit_camera_events() {
    echo ""
    echo "=== Редактирование событий камеры ==="
    
    source "$CONFIG_FILE" 2>/dev/null
    
    echo "Текущие камеры в конфигурации:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        echo "$((i+1)). Камера ${CAMERA_NUMS[$i]}: События ${CAMERA_EVENT_TYPES[$i]}"
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
    local current_events=${CAMERA_EVENT_TYPES[$array_index]}
    
    echo ""
    echo "Редактирование событий для камеры $camera_num"
    echo "Текущие события: $current_events"
    echo ""
    echo "Выберите настройки событий:"
    echo "1) Использовать общие настройки событий (GENERAL)"
    echo "2) Настроить индивидуально"
    read -p "Ваш выбор (1-2): " event_choice
    
    case $event_choice in
        1)
            NEW_EVENTS="GENERAL"
            ;;
        2)
            echo ""
            echo "Какие события отправлять для камеры $camera_num?"
            echo "1) Движение (motion)"
            echo "2) Захват видео (capture)"
            echo "3) Ошибки (errors)"
            echo "4) Запись (recording)"
            echo "5) Сохранение файлов (files)"
            echo "6) Качество изображения (quality)"
            echo "7) Сеть (network)"
            echo "8) Все события (all)"
            echo "9) Только движение (motion_only)"
            echo ""
            
            echo "Выберите типы событий (через запятую, например: 1,3,5):"
            read camera_events
            
            # Преобразуем строку в названия событий
            IFS=',' read -ra camera_events_array <<< "$camera_events"
            local camera_event_string=""
            for event_num in "${camera_events_array[@]}"; do
                case $event_num in
                    1) camera_event_string+="motion," ;;
                    2) camera_event_string+="capture," ;;
                    3) camera_event_string+="errors," ;;
                    4) camera_event_string+="recording," ;;
                    5) camera_event_string+="files," ;;
                    6) camera_event_string+="quality," ;;
                    7) camera_event_string+="network," ;;
                    8) camera_event_string+="all," ;;
                    9) camera_event_string+="motion_only," ;;
                    *) echo "❌ Неверный номер события: $event_num"; return 1 ;;
                esac
            done
            NEW_EVENTS=$(echo $camera_event_string | sed 's/,$//')
            ;;
        *)
            echo "❌ Неверный выбор"
            return 1
            ;;
    esac
    
    # Обновляем массив
    awk -v idx="$array_index" -v new_events="$NEW_EVENTS" '
    /^declare -a CAMERA_EVENT_TYPES=\(/ {
        in_array=1
        array_line=""
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        print "declare -a CAMERA_EVENT_TYPES=(" array_line ")"
        in_array=0
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\\/ {
        if (array_idx == idx) {
            array_line = array_line "  \"" new_events "\" \\"
        } else {
            array_line = array_line $0
        }
        array_idx++
        next
    }
    in_array && /^[[:space:]]*"[^"]*"[[:space:]]*\)/ {
        if (array_idx == idx) {
            print "declare -a CAMERA_EVENT_TYPES=(" array_line ")"
            print "  \"" new_events "\")"
        } else {
            print "declare -a CAMERA_EVENT_TYPES=(" array_line ")"
            print $0
        }
        in_array=0
        next
    }
    !in_array {
        print $0
    }
    ' "$CONFIG_FILE" > "$TEMP_CONFIG" && mv "$TEMP_CONFIG" "$CONFIG_FILE"
    
    echo "✅ События камеры $camera_num обновлены на: $NEW_EVENTS"
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
    
    echo ""
    echo "Настройки отправки сообщений:"
    echo "  Отправлять текст: $SEND_TEXT"
    echo "  Отправлять медиа: $SEND_MEDIA"
    
    echo ""
    echo "Настройки расписания:"
    echo "  Включено: $SCHEDULE_ENABLED"
    echo "  Тип: $SCHEDULE_TYPE"
    echo "  Дни: $SCHEDULE_DAYS"
    echo "  Часы: $SCHEDULE_HOURS"
    echo "  Минуты: $SCHEDULE_MINUTES"
    
    if [ -n "$SCHEDULE_EXCLUDE_DATES" ]; then
        echo "  Исключения: $SCHEDULE_EXCLUDE_DATES"
    fi
    
    echo "  Отправлять критические ошибки всегда: $SEND_CRITICAL_ALWAYS"
    
    echo ""
    echo "Настройки событий:"
    echo "  Типы событий: ${EVENT_TYPES[@]}"
    echo "  Уровень логирования: $LOG_LEVEL"
    echo "  Количество камер: $CAMERA_COUNT"
    echo "  Пользователь скриптов: $AVREG_USER"
    echo ""
    
    echo "Настройки камер:"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        local send_text_display="общие"
        local send_media_display="общие"
        
        if [ "${CAMERA_SEND_TEXT[$i]}" != "GENERAL" ]; then
            send_text_display="${CAMERA_SEND_TEXT[$i]}"
        fi
        if [ "${CAMERA_SEND_MEDIA[$i]}" != "GENERAL" ]; then
            send_media_display="${CAMERA_SEND_MEDIA[$i]}"
        fi
        
        echo "  Камера ${CAMERA_NUMS[$i]}:"
        echo "    Чат ID: ${CAMERA_CHAT_IDS[$i]}"
        echo "    Тип медиа: ${CAMERA_MEDIA_TYPES[$i]}"
        echo "    События: ${CAMERA_EVENT_TYPES[$i]}"
        echo "    Расписание: ${CAMERA_SCHEDULES[$i]}"
        echo "    Длительность видео: ${CAMERA_VIDEO_DURATIONS[$i]}сек"
        echo "    FPS видео: ${CAMERA_VIDEO_FPS[$i]}"
        echo "    Отправка текста: $send_text_display"
        echo "    Отправка медиа: $send_media_display"
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
    echo "Для тестирования камеры выполните:"
    echo "sudo -u avreg /etc/avreg/scripts/tg.sh test <номер_камеры>"
    echo ""
    echo "Для проверки расписания выполните:"
    echo "sudo -u avreg /etc/avreg/scripts/tg.sh schedule [номер_камеры]"
    echo ""
    echo "Для тестирования событий выполните:"
    echo "sudo -u avreg /etc/avreg/scripts/tg.sh event \"13|1|2024-01-01 12:00:00|2024-01-01 11:59:55|1|2|1|Движение обнаружено\""
}

# Главное меню
show_menu() {
    while true; do
        echo ""
        echo "=== Редактор конфигурации Telegram уведомлений ==="
        echo "1) Просмотреть текущую конфигурацию"
        echo "2) Редактировать общие настройки отправки сообщений (текст/медиа)"
        echo "3) Редактировать настройки отправки для конкретной камеры"
        echo "4) Редактировать токен бота"
        echo "5) Редактировать чат для камеры"
        echo "6) Редактировать тип медиа для камеры"
        echo "7) Редактировать настройки событий (общие)"
        echo "8) Редактировать события для камеры (индивидуальные)"
        echo "9) Редактировать настройки расписания (общие)"
        echo "10) Редактировать расписание для камеры (индивидуальные)"
        echo "11) Редактировать параметры видео (длительность, FPS)"
        echo "12) Протестировать конфигурацию"
        echo "13) Создать резервную копию конфигурации"
        echo "14) Выйти"
        echo ""
        
        read -p "Выберите действие (1-14): " choice
        
        case $choice in
            1)
                view_config
                ;;
            2)
                create_backup
                edit_message_settings
                ;;
            3)
                create_backup
                edit_camera_message_settings
                ;;
            4)
                create_backup
                edit_bot_token
                ;;
            5)
                create_backup
                edit_camera_chat
                ;;
            6)
                create_backup
                edit_camera_media_type
                ;;
            7)
                create_backup
                edit_events
                ;;
            8)
                create_backup
                edit_camera_events
                ;;
            9)
                create_backup
                edit_schedule
                ;;
            10)
                create_backup
                edit_camera_schedule
                ;;
            11)
                create_backup
                edit_video_params
                ;;
            12)
                test_config
                ;;
            13)
                create_backup
                ;;
            14)
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
    
    # Изменяем event-collector для поддержки всех событий
    echo "Модификация event-collector для поддержки всех событий Telegram..."
    
    # Создаем резервную копию
    sudo cp "$EVENT_COLLECTOR" "${EVENT_COLLECTOR}.backup.$(date +%Y%m%d%H%M%S)"
    
    # Изменяем интерпретатор на bash для поддержки массивов
    sudo sed -i '1s|#!/bin/sh|#!/bin/bash|' "$EVENT_COLLECTOR"
    
    # Находим функцию handle_event и добавляем вызов tg.sh после каждого события
    local handle_event_start=$(grep -n "^handle_event()" "$EVENT_COLLECTOR" | cut -d: -f1)
    
    if [ -n "$handle_event_start" ]; then
        # Ищем конец функции handle_event
        local handle_event_end=$(awk -v start="$handle_event_start" 'NR > start && /^[[:space:]]*}/ {print NR; exit}' "$EVENT_COLLECTOR")
        
        if [ -n "$handle_event_end" ]; then
            # Добавляем код вызова tg.sh перед return в функции handle_event
            sudo sed -i "${handle_event_end}i\\
    # Вызов Telegram скрипта для обработки события\\
    if [ -f \\\"/etc/avreg/scripts/tg.sh\\\" ]; then\\
        # Формируем строку с данными события\\
        local event_str=\\\"\\\$EVT_ID|\\\$CAM_NR|\\\$DT_EVENT|\\\$DT_PREV|\\\$SESS_NR|\\\$ALT1|\\\$ALT2|\\\$EVT_CONT\\\"\\
        /etc/avreg/scripts/tg.sh event \\\"\\\$event_str\\\" &\\
    fi" "$EVENT_COLLECTOR"
            
            echo "✅ event-collector модифицирован для обработки всех событий"
        fi
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
    
    echo "2. Проверка настроек отправки сообщений..."
    echo "   Отправлять текст: $SEND_TEXT"
    echo "   Отправлять медиа: $SEND_MEDIA"
    
    echo "3. Проверка настроек расписания..."
    echo "   Включено: $SCHEDULE_ENABLED"
    echo "   Тип: $SCHEDULE_TYPE"
    echo "   Дни: $SCHEDULE_DAYS"
    echo "   Часы: $SCHEDULE_HOURS"
    echo "   Минуты: $SCHEDULE_MINUTES"
    echo "   Отправлять критические ошибки всегда: $SEND_CRITICAL_ALWAYS"
    
    echo "4. Проверка настроек событий..."
    echo "   Типы событий: ${EVENT_TYPES[@]}"
    echo "   Уровень логирования: $LOG_LEVEL"
    
    echo "5. Проверка камер в конфигурации..."
    echo "   Настроено камер: $CAMERA_COUNT"
    for ((i=0; i<CAMERA_COUNT; i++)); do
        local send_text_display="общие"
        local send_media_display="общие"
        
        if [ "${CAMERA_SEND_TEXT[$i]}" != "GENERAL" ]; then
            send_text_display="${CAMERA_SEND_TEXT[$i]}"
        fi
        if [ "${CAMERA_SEND_MEDIA[$i]}" != "GENERAL" ]; then
            send_media_display="${CAMERA_SEND_MEDIA[$i]}"
        fi
        
        echo "   Камера ${CAMERA_NUMS[$i]}: Чат ${CAMERA_CHAT_IDS[$i]}, Тип: ${CAMERA_MEDIA_TYPES[$i]}, События: ${CAMERA_EVENT_TYPES[$i]}, Расписание: ${CAMERA_SCHEDULES[$i]}, Текст=$send_text_display, Медиа=$send_media_display"
    done
    
    echo "6. Проверка доступности Avreg..."
    if timeout 5 curl -s "http://${AVREG_URL}:874" > /dev/null; then
        echo "   ✅ Avreg доступен"
    else
        echo "   ⚠️  Avreg недоступен по адресу: ${AVREG_URL}:874"
    fi
    
    echo "7. Тестирование камер..."
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
    
    echo "8. Тестирование расписания..."
    echo ""
    echo "   Для проверки расписания выполните:"
    echo "   sudo -u avreg /etc/avreg/scripts/tg.sh schedule"
    echo "   или для конкретной камеры:"
    echo "   sudo -u avreg /etc/avreg/scripts/tg.sh schedule <номер_камеры>"
    
    echo "9. Тестирование событий..."
    echo ""
    echo "   Примеры тестовых событий:"
    echo "   - Движение обнаружено:"
    echo "     sudo -u avreg /etc/avreg/scripts/tg.sh event \"13|1|2024-01-01 12:00:00|2024-01-01 11:59:55|1|2|1|Движение обнаружено\""
    echo "   - Ошибка захвата:"
    echo "     sudo -u avreg /etc/avreg/scripts/tg.sh event \"3|1|2024-01-01 12:00:00|2024-01-01 11:59:55|3|2|1|Ошибка подключения к камере\""
    echo "   - Система запущена:"
    echo "     sudo -u avreg /etc/avreg/scripts/tg.sh event \"1|0|2024-01-01 12:00:00|2024-01-01 11:59:55|0|0|0|Система запущена\""
    
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
                    echo ""
                    echo "Настройки отправки сообщений:"
                    echo "  Отправлять текст: $SEND_TEXT"
                    echo "  Отправлять медиа: $SEND_MEDIA"
                    echo ""
                    echo "Настройки расписания:"
                    echo "  Включено: $SCHEDULE_ENABLED"
                    echo "  Тип: $SCHEDULE_TYPE"
                    echo "  Дни: $SCHEDULE_DAYS"
                    echo "  Часы: $SCHEDULE_HOURS"
                    echo "  Минуты: $SCHEDULE_MINUTES"
                    
                    if [ -n "$SCHEDULE_EXCLUDE_DATES" ]; then
                        echo "  Исключения: $SCHEDULE_EXCLUDE_DATES"
                    fi
                    
                    echo "  Отправлять критические ошибки всегда: $SEND_CRITICAL_ALWAYS"
                    
                    echo ""
                    echo "Настройки событий:"
                    echo "  Типы событий: ${EVENT_TYPES[@]}"
                    echo "  Уровень логирования: $LOG_LEVEL"
                    echo "  Количество камер: $CAMERA_COUNT"
                    echo "  Avreg URL: $AVREG_URL"
                    echo "  Логин: $login"
                    echo "  Пользователь скриптов: $AVREG_USER"
                    echo ""
                    echo "Настройки камер:"
                    for ((i=0; i<CAMERA_COUNT; i++)); do
                        local send_text_display="общие"
                        local send_media_display="общие"
                        
                        if [ "${CAMERA_SEND_TEXT[$i]}" != "GENERAL" ]; then
                            send_text_display="${CAMERA_SEND_TEXT[$i]}"
                        fi
                        if [ "${CAMERA_SEND_MEDIA[$i]}" != "GENERAL" ]; then
                            send_media_display="${CAMERA_SEND_MEDIA[$i]}"
                        fi
                        
                        echo "  Камера ${CAMERA_NUMS[$i]}:"
                        echo "    Чат: ${CAMERA_CHAT_IDS[$i]}"
                        echo "    Тип медиа: ${CAMERA_MEDIA_TYPES[$i]}"
                        echo "    События: ${CAMERA_EVENT_TYPES[$i]}"
                        echo "    Расписание: ${CAMERA_SCHEDULES[$i]}"
                        echo "    Длительность видео: ${CAMERA_VIDEO_DURATIONS[$i]}сек"
                        echo "    FPS видео: ${CAMERA_VIDEO_FPS[$i]}"
                        echo "    Отправка текста: $send_text_display"
                        echo "    Отправка медиа: $send_media_display"
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
                    echo "Типы событий: ${EVENT_TYPES[@]}"
                    echo "Уровень логирования: $LOG_LEVEL"
                    echo "Отправка текста: $SEND_TEXT"
                    echo "Отправка медиа: $SEND_MEDIA"
                    echo "Настройки расписания: $SCHEDULE_ENABLED, $SCHEDULE_TYPE"
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
                
                echo ""
                echo "Логи event-collector:"
                if [ -f "/var/log/avreg/evtcoll.log" ]; then
                    echo "Последние 10 строк лога event-collector:"
                    tail -10 "/var/log/avreg/evtcoll.log"
                elif [ -f "/var/log/avreg/evtcoll-avreg.log" ]; then
                    echo "Последние 10 строк лога event-collector:"
                    tail -10 "/var/log/avreg/evtcoll-avreg.log"
                else
                    echo "Лог event-collector не найден"
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
echo "Версия 1.5"
echo "Поддержка расписания работы бота и гибкой настройки отправки текста/медиа"
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
