# Veloutro Bot (Ruby)

Telegram-бот для организации около велосипедных мероприятий сообщества Велоутро Орел, написанный на Ruby.

## Описание

Veloutro Bot позволяет пользователям создавать мероприятия, искать существующие, присоединяться к ним и управлять своими мероприятиями. Бот также поддерживает публикацию анонсов мероприятий в публичный канал и интегрирован с системой прогноза погоды для повышения безопасности велосипедных поездок.

## Технический стек

- **Язык программирования**: Ruby
- **Фреймворк для Telegram**: telegram-bot-ruby
- **База данных**: PostgreSQL
- **ORM**: ActiveRecord
- **Веб-фреймворк**: Sinatra
- **Шаблонизатор**: Mustache
- **Локализация**: I18n
- **HTTP клиент**: Faraday (для WeatherAPI)
- **Планировщик**: Rufus-scheduler

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
DAILY_ANNOUNCEMENT_TIME=18:30  # UTC время (21:30 Moscow Time)

# Monthly Statistics Settings
MONTHLY_STATS_DAY=15  # день месяца для отправки статистики (1-28)

# Timezone Settings
TIMEZONE=Europe/Moscow

# Weather Integration Settings (optional)
WEATHER_API_KEY=your_weatherapi_key_here
WEATHER_ENABLED=true
DEFAULT_WEATHER_COORDINATES=52.9651,36.0785
DEFAULT_WEATHER_CITY_NAME=Орёл
WEATHER_ADMIN_ALERTS=true
WEATHER_DEBUG=false
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
- `/my_events` - Управление своими мероприятиями (показывает только предстоящие события)
- `/announcement` - Публикация анонса мероприятий на сегодня (только для администраторов)
- `/statistics` - Просмотр статистики за прошлый месяц (только для администраторов)
- `/scheduler_status` - Проверка статуса планировщика анонсов (только для администраторов)
- `/weather_status` - Проверка статуса погодной системы (только для администраторов)

## Структура проекта

```
velo_utro_bot/
├── app/                    # Код приложения
│   ├── bot/                # Код бота
│   │   ├── callbacks/      # Обработчики callback-запросов
│   │   ├── commands/       # Обработчики команд
│   │   ├── handlers/       # Базовые классы обработчиков
│   │   ├── helpers/        # Вспомогательные классы
│   │   ├── states/         # Обработчики состояний диалога
│   │   ├── callbacks.rb    # Модуль для загрузки обработчиков callback-запросов
│   │   ├── commands.rb     # Модуль для загрузки обработчиков команд
│   │   └── states.rb       # Модуль для загрузки обработчиков состояний
│   ├── models/             # Модели данных
│   ├── services/           # Сервисы (погода, рекомендации)
│   ├── controllers/        # Контроллеры (для веб-интерфейса)
│   └── views/              # Представления (для веб-интерфейса)
├── config/                 # Конфигурационные файлы
│   ├── environments/       # Настройки для разных окружений
│   ├── initializers/       # Инициализаторы
│   └── locales/            # Файлы локализации
├── db/                     # Файлы для работы с базой данных
│   └── migrations/         # Миграции базы данных
│       ├── 001_create_tables.rb           # Создание основных таблиц
│       ├── 002_add_track_and_map_to_events.rb # Добавление полей track и map
│       ├── 003_add_channel_message_id_to_events.rb # Добавление поля channel_message_id
│       ├── 004_add_weather_fields_to_events.rb # Добавление полей для интеграции с погодой
│       └── 005_add_published_to_events.rb # Добавление статуса публикации событий
├── public/                 # Публичные файлы (для веб-интерфейса)
├── .env                    # Переменные окружения
├── .gitignore              # Файлы, исключенные из системы контроля версий
├── app.rb                  # Основной файл приложения
├── Gemfile                 # Зависимости проекта
├── Gemfile.lock            # Фиксированные версии зависимостей
├── Rakefile                # Задачи Rake
├── REFACTORING_PLAN.md     # План рефакторинга кода
└── README.md               # Документация проекта
```

## Функциональность

### Основные возможности
- Создание и управление мероприятиями с точным временем начала
- Поиск мероприятий по различным временным периодам
- Присоединение к мероприятиям и отказ от участия
- Полное редактирование мероприятий (дата, время, место, трек, карта, описание)
- Автоматические ежедневные анонсы событий на следующие 24 часа
- Автоматическая ежемесячная статистика использования бота
- Публикация мероприятий в публичный канал с кнопками участия
- Система уведомлений участников об изменениях
- Ссылки на оригинальные сообщения о событиях в уведомлениях об изменениях
- Детальная статистика с анализом активности пользователей
- **Интеграция с прогнозом погоды**: автоматические обновления, уведомления о критичных изменениях, персонализированные рекомендации по экипировке

### Типы мероприятий
- **Статические**: встречи, обсуждения, настольные игры - без дистанции и темпа
- **Активные**: велосипедные поездки, пробежки, активности на воде - с указанием дистанции, темпа, маршрута и карты

### Система уведомлений
- Уведомления участников при изменении деталей мероприятия
- Краткие уведомления в публичный канал со ссылками на оригинальные события
- Автоматические ежедневные анонсы с учетом точного времени событий

## Разработка

### Добавление новых команд

1. Создайте новый файл в директории `app/bot/commands/` с именем команды
2. Наследуйте класс от `Bot::CommandHandler` или `Bot::Handlers::InfoCommandHandler` (для информационных команд)
3. Реализуйте метод `execute` (или `message_key` для InfoCommandHandler)

**Пример информационной команды:**
```ruby
require_relative '../handlers/info_command_handler'

module Bot
  module Commands
    class MyCommand < Bot::Handlers::InfoCommandHandler
      private
      
      def message_key
        'my_command'  # ключ в config/locales/ru.yml
      end
    end
  end
end
```

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

TG: @nixon_tut

## Идея и базовая логика

https://github.com/tulaman/sport-event-bot

## Лицензия

GPL-3.0
