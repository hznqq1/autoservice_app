# AutoService Trio

Информационная система автосервиса, разработанная в рамках дипломного проекта.  
Проект состоит из клиентской части на Flutter, серверной части на FastAPI и базы данных PostgreSQL.

## Технологический стек

- `Flutter` (Dart) — клиентское приложение
- `FastAPI` + `SQLAlchemy` — серверное API
- `PostgreSQL` — хранение данных
- `Docker Compose` — оркестрация инфраструктуры

## Структура проекта

- `lib/` — исходный код Flutter-приложения
- `backend/` — серверное приложение FastAPI
- `scripts/` — служебные скрипты проверки
- `docker-compose.yml` — конфигурация запуска контейнеров

## Запуск проекта

Рабочая директория:

```bash
cd D:\Project\Projects\autoservice_app
```

### 1. Запуск базы данных и API

```bash
docker compose up -d --build
```

Проверка доступности API:

```bash
http://localhost:8000/health
```

### 2. Запуск клиентского приложения (Web)

```bash
flutter pub get
flutter run -d chrome
```

После запуска Flutter откройте URL, выведенный в консоли (обычно `http://localhost:53xxx`).

### 3. Остановка контейнеров

```bash
docker compose down
```

## Переменные окружения

Параметры подключения к PostgreSQL задаются в файле `.env`.

Пример:

```env
POSTGRES_USER=user_trio
POSTGRES_PASSWORD=password_trio
POSTGRES_DB=autoservice_db
```

Шаблон файла: `.env.example`.

## Smoke-тест API

Для быстрой проверки работоспособности серверной части выполните:

```bash
py scripts/smoke_test_api.py
```

Скрипт проверяет:

- доступность endpoint `health`
- создание записи автомобиля
- создание заявки на обслуживание
- корректность чтения данных через `/cars` и `/bookings`
