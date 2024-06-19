#!/bin/bash

# Токен вашего бота
BOT_TOKEN='TOKEN'
# ID чата или канала
CHAT_ID='CHAT_ID'
# Сообщение уведомления
MESSAGE='Движ!'
# Номер камеры
camera_num=2
# Ваш логин
login="LOGIN"
# Кодируем логин и пустой пароль в формате Base64
auth_value=$(echo -n "${login}:" | base64)
# Формируем строку запроса с использованием закодированного значения. Замените IP на IP своего сервера.
url="http://192.168.1.3:874/avreg-cgi/jpg/image.cgi?camera=${camera_num}&ab=${auth_value}"
# Имя файла изображения
IMAGE_FILE="cam${camera_num}.jpg"

# Функция получения изображения
get_image() {
    wget -S "$url" -O $IMAGE_FILE
}

# Функция отправки уведомления в Telegram
send_telegram() {
    # Получаем изображение
    get_image
    # Отправляем текстовое сообщение
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id=$CHAT_ID \
    -d text="$MESSAGE" >> /tmp/telegram_log.txt 2>&1
    # Отправляем изображение
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendPhoto" \
    -F chat_id=$CHAT_ID \
    -F photo=@"$IMAGE_FILE" >> /tmp/telegram_log.txt 2>&1
    # Удаляем изображение после отправки
    rm $IMAGE_FILE
}

# Вызов функции отправки уведомления
send_telegram
