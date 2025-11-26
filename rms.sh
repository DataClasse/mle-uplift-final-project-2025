#!/usr/bin/env bash

# Определяем путь к .env файлу (текущая директория или родительская)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    # Пробуем родительскую директорию
    ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"
fi

if [ -f "$ENV_FILE" ]; then
    echo "📄 Загрузка переменных из: $ENV_FILE"
    while IFS='=' read -r key value; do
        # Игнорируем комментарии и пустые строки
        case "$key" in
            '#'*) ;;
            '') ;;
            *)
                # Удаляем кавычки из значения
                value="${value%\"}"
                value="${value#\"}"
                export "$key"="$value"
        esac
    done < "$ENV_FILE"
else
    echo "⚠️ Файл .env не найден! Искали: $SCRIPT_DIR/.env и $(dirname "$SCRIPT_DIR")/.env"
    exit 1
fi

# 3. Проверка обязательных переменных
required_vars=(DB_DESTINATION_HOST DB_DESTINATION_PORT DB_DESTINATION_NAME DB_DESTINATION_USER DB_DESTINATION_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY S3_BUCKET_NAME)
missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "⚠️ Отсутствуют обязательные переменные: ${missing_vars[*]}"
    exit 1
fi

# 4. Экспорт переменных для MLflow
export MLFLOW_S3_ENDPOINT_URL="https://storage.yandexcloud.net"

# Проверка и освобождение порта 5000
PORT=5000
if lsof -i :$PORT &>/dev/null; then
    echo "⚠️ Порт $PORT занят. Останавливаю процессы..."
    lsof -t -i :$PORT | xargs -r kill -9
    sleep 2
    if lsof -i :$PORT &>/dev/null; then
        echo "❌ Не удалось освободить порт $PORT. Завершите процессы вручную."
        exit 1
    else
        echo "✅ Порт $PORT освобождён."
    fi
else
    echo "✅ Порт $PORT свободен."
fi

# 5. Проверка подключения к PostgreSQL
echo "Проверка подключения к PostgreSQL..."
if ! nc -z -w 2 "$DB_DESTINATION_HOST" "$DB_DESTINATION_PORT"; then
    echo "❌ Не удается подключиться к $DB_DESTINATION_HOST:$DB_DESTINATION_PORT"
    exit 1
fi
echo "✅ Подключение к PostgreSQL успешно"

# 6. Запуск MLflow сервера
# Получаем host и port из .env или задаём по умолчанию
MLFLOW_SERVER_HOST=${TRACKING_SERVER_HOST:-127.0.0.1}
MLFLOW_SERVER_PORT=${TRACKING_SERVER_PORT:-5000}

# Экспорт MLFLOW_TRACKING_URI для использования в ноутбуке
export MLFLOW_TRACKING_URI="http://${MLFLOW_SERVER_HOST}:${MLFLOW_SERVER_PORT}"
echo "📊 MLFLOW_TRACKING_URI=$MLFLOW_TRACKING_URI"

echo ""
echo "🚀 Запуск MLflow сервера..."
echo "Backend URI: postgresql://$DB_DESTINATION_USER:***@$DB_DESTINATION_HOST:$DB_DESTINATION_PORT/$DB_DESTINATION_NAME"
echo "Artifact Root: s3://$S3_BUCKET_NAME"
echo "MLflow host: $MLFLOW_SERVER_HOST, port: $MLFLOW_SERVER_PORT"
echo "Tracking URI: $MLFLOW_TRACKING_URI"
echo ""

exec mlflow server \
  --backend-store-uri "postgresql://$DB_DESTINATION_USER:$DB_DESTINATION_PASSWORD@$DB_DESTINATION_HOST:$DB_DESTINATION_PORT/$DB_DESTINATION_NAME" \
  --default-artifact-root "s3://$S3_BUCKET_NAME" \
  --host $MLFLOW_SERVER_HOST \
  --port $MLFLOW_SERVER_PORT
