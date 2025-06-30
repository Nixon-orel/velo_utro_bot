# Veloutro Bot (Ruby)

Telegram-бот для организации около велосипедных мероприятий сообщества Велоутро Орел, написанный на Ruby.

## Описание

Veloutro Bot позволяет пользователям создавать мероприятия, искать существующие, присоединяться к ним и управлять своими мероприятиями. Бот также поддерживает публикацию анонсов мероприятий в публичный канал.

## Технический стек

- **Язык программирования**: Ruby
- **Фреймворк для Telegram**: telegram-bot-ruby
- **База данных**: PostgreSQL
- **ORM**: ActiveRecord
- **Веб-фреймворк**: Sinatra
- **Шаблонизатор**: Mustache
- **Локализация**: I18n

## Установка и запуск

### Предварительные требования

- Ruby 3.2.1
- PostgreSQL
- Telegram Bot Token

### Установка

1. Клонируйте репозиторий:

```bash
git clone https://github.com/nixon-orel/velo_utro_bot.git
cd velo_utro_bot
```

2. Установите системные зависимости PostgreSQL:

```bash
sudo apt update
sudo apt install libpq-dev postgresql-client postgresql postgresql-contrib
```

3. Установите зависимости Ruby:

```bash
bundle install
```

4. Создайте файл `.env` и заполните его своими данными:

```bash
cp .env.example .env
```

Отредактируйте файл `.env` и укажите свой Telegram Bot Token и другие настройки.

### Запуск

#### Настройка переменных окружения:

Создайте файл `.env` со следующим содержимым:
```
# Telegram Bot Token
TG_TOKEN=ваш_токен_телеграм_бота

# Database Configuration
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=localhost
DB_PORT=5432
DB_NAME=velo_utro_bot_development

# Application Configuration
RACK_ENV=development
PORT=4567
PUBLIC_CHANNEL_ID=ваш_id_канала
BOT_USERNAME=имя_вашего_бота

# Admin IDs (comma-separated)
ADMIN_IDS=ваши_admin_id

# Static Events (comma-separated)
STATIC_EVENTS=Встреча,Обсуждение

# Daily Announcement Settings
DAILY_ANNOUNCEMENT_ENABLED=true
DAILY_ANNOUNCEMENT_TIME=08:00
TIMEZONE=Europe/Moscow
```

#### Создание базы данных:

1. Создайте пользователя PostgreSQL:
```bash
sudo -u postgres -H createuser -s $USER
```

2. Создайте базы данных:
```bash
source .env
createdb velo_utro_bot_development
createdb velo_utro_bot_production
```

#### Применение миграций:

```bash
source .env
bundle exec ruby migrate_only.rb
```

#### Запуск бота:

```bash
source .env
bundle exec ruby app.rb
```

**Важно**: Всегда выполняйте `source .env` перед запуском команд, чтобы загрузить переменные окружения.

## Команды бота

- `/start` - Начало работы с ботом, регистрация пользователя
- `/menu` - Показать главное меню
- `/help` - Получение справки по использованию бота
- `/create` - Создание нового мероприятия
- `/find` - Поиск существующих мероприятий
- `/my_events` - Управление своими мероприятиями
- `/announcement` - Публикация анонса мероприятий на сегодня (только для администраторов)

## Структура проекта

```
velo_utro_bot/
├── app/                    # Код приложения
│   ├── bot/                # Код бота
│   │   ├── callbacks/      # Обработчики callback-запросов
│   │   ├── commands/       # Обработчики команд
│   │   ├── helpers/        # Вспомогательные классы
│   │   ├── states/         # Обработчики состояний диалога
│   │   ├── callbacks.rb    # Модуль для загрузки обработчиков callback-запросов
│   │   ├── commands.rb     # Модуль для загрузки обработчиков команд
│   │   └── states.rb       # Модуль для загрузки обработчиков состояний
│   ├── models/             # Модели данных
│   ├── controllers/        # Контроллеры (для веб-интерфейса)
│   └── views/              # Представления (для веб-интерфейса)
├── config/                 # Конфигурационные файлы
│   ├── environments/       # Настройки для разных окружений
│   ├── initializers/       # Инициализаторы
│   └── locales/            # Файлы локализации
├── db/                     # Файлы для работы с базой данных
│   └── migrations/         # Миграции базы данных
├── public/                 # Публичные файлы (для веб-интерфейса)
├── .env                    # Переменные окружения
├── .gitignore              # Файлы, исключенные из системы контроля версий
├── app.rb                  # Основной файл приложения
├── Gemfile                 # Зависимости проекта
├── Gemfile.lock            # Фиксированные версии зависимостей
├── Rakefile                # Задачи Rake
└── README.md               # Документация проекта
```

## Функциональность

### Основные возможности
- Создание и управление мероприятиями
- Поиск мероприятий по дате
- Присоединение к мероприятиям и отказ от участия
- Редактирование мероприятий (время, место, трек, карта, описание)
- Автоматические ежедневные анонсы
- Публикация мероприятий в публичный канал
- Система уведомлений участников

### Типы мероприятий
- Статические (встречи, обсуждения)
- Динамические (с дистанцией, темпом, треком и картой)

## Разработка

### Добавление новых команд

1. Создайте новый файл в директории `app/bot/commands/` с именем команды
2. Наследуйте класс от `Bot::CommandHandler`
3. Реализуйте метод `execute`

### Добавление новых обработчиков callback-запросов

1. Создайте новый файл в директории `app/bot/callbacks/`
2. Наследуйте класс от `Bot::CallbackHandler` или `ParticipationHandler`
3. Реализуйте метод `process`

### Добавление новых обработчиков состояний

1. Создайте новый файл в директории `app/bot/states/`
2. Наследуйте класс от `Bot::StateHandler` или `EditHandler`
3. Реализуйте метод `process`

## Автор

https://github.com/Nixon-orel

TG: @nixonicus

## Идея и основная логика

https://github.com/tulaman/sport-event-bot

## Лицензия

GPL-3.0
