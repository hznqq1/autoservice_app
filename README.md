# AutoService Trio

Информационная система автосервиса (дипломный проект): клиентское приложение на Flutter, REST API на FastAPI, база PostgreSQL.

## Возможности

- **Клиент:** регистрация, вход, личный гараж, запись на услуги, история заявок, личный кабинет
- **Механик:** вход, просмотр всех заявок с email клиента и датой, смена статуса (Ожидание → В работе → Готово)
- **Изоляция данных:** у каждого клиента свой гараж и свои заявки; механик видит заявки всех клиентов

## Технологический стек

| Слой | Технологии |
|------|------------|
| Клиент | Flutter (Dart), `http`, `shared_preferences` |
| Сервер | FastAPI, SQLAlchemy, passlib (bcrypt), python-jose (JWT) |
| БД | PostgreSQL 15 |
| Инфраструктура | Docker Compose |

## Структура репозитория

```
autoservice_app/
├── lib/main.dart          # Flutter-приложение (UI + API-клиент)
├── backend/
│   ├── main.py            # REST API, маршруты
│   ├── models.py          # SQLAlchemy-модели
│   ├── schemas.py         # Pydantic-схемы
│   ├── auth.py            # JWT, хеш паролей, зависимости
│   ├── database.py        # Подключение к PostgreSQL
│   ├── Dockerfile
│   └── requirements.txt
├── web/                   # Flutter Web (index.html, html-рендерер)
├── scripts/
│   └── smoke_test_api.py  # Проверка API
├── docker-compose.yml
├── .env.example
└── README.md
```

## Быстрый старт

### 1. Подготовка

Перейдите в корневую директорию проекта и создайте локальный файл с переменными окружения:

```bash
cd autoservice_app
cp .env.example .env
```

### 2. База данных и API

```bash
docker compose up -d --build
```

Проверка: http://localhost:8000/health → `{"status":"ok",...}`

Документация API: http://localhost:8000/docs

### 3. Flutter (Web)

```bash
flutter pub get
flutter run -d chrome --web-renderer html
```

> **Web:** обязательно `--web-renderer html`, иначе при блокировке `gstatic.com` возможен белый экран.

### 4. Smoke-тест

```bash
py scripts/smoke_test_api.py
```

Ожидается: `SMOKE TEST OK`

## Учётные записи

| Роль | Email | Пароль |
|------|-------|--------|
| Механик (тест) | `mechanic@trio.ru` | `mechanic123` |
| Клиент | регистрация в приложении | свой пароль |

Механик создаётся автоматически при первом запуске API.

## API (кратко)

| Метод | Путь | Кто | Описание |
|-------|------|-----|----------|
| POST | `/register` | все | Регистрация клиента → JWT |
| POST | `/login` | все | Вход → JWT |
| GET | `/services` | все | Список услуг |
| GET/POST/PUT/DELETE | `/cars` | клиент | Гараж (только свои) |
| GET/POST | `/bookings` | клиент / механик* | Заявки (*механик — все, клиент — свои) |
| PATCH | `/bookings/{id}/status` | механик | Смена статуса |

Защищённые запросы: заголовок `Authorization: Bearer <token>`.

## Переменные окружения

См. `.env.example`: PostgreSQL, `MECHANIC_EMAIL`, `MECHANIC_PASSWORD`, `JWT_SECRET`.

## Остановка

```bash
docker compose down
```

## Известные нюансы

1. **Flutter Web** — рендерер `html`, не CanvasKit (сеть/Google Fonts).
2. **После обновления API** — перелогиниться в приложении (нужен новый JWT).
3. **Механик видит заявки** только если клиенты их создали.
