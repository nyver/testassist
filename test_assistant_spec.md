# Test Assistant — техническая спецификация

## 1. Общее описание

**Test Assistant** — Android-приложение для распознавания тестовых вопросов по фотографии и получения ответа от LLM с кратким объяснением.

Пользователь фотографирует вопрос с вариантами ответа либо выбирает изображение из галереи. Клиент распознаёт текст, выделяет вопрос и варианты, отправляет структурированные данные и при необходимости исходное изображение на собственный Go-сервер. Сервер обращается к выбранному LLM-провайдеру, получает структурированный ответ и возвращает пользователю правильный вариант, объяснение и оценку уверенности.

Система должна поддерживать:

- Android-клиент на Flutter;
- Go backend;
- запуск сервера через Docker Compose;
- HTTPS;
- обычные TLS-сертификаты от доверенного CA;
- самоподписанные TLS-сертификаты;
- подтверждение SHA-256 fingerprint сертификата на клиенте;
- автоматическую генерацию self-signed сертификата сервером при его отсутствии;
- OpenRouter;
- RouterAI;
- возможность дальнейшего подключения других OpenAI-compatible LLM API;
- текстовые и мультимодальные модели;
- локальную историю вопросов;
- OCR на устройстве.

---

## 2. Основные сценарии

### 2.1. Анализ вопроса по фотографии

1. Пользователь открывает экран камеры.
2. Делает фотографию вопроса.
3. Клиент выполняет OCR.
4. Клиент пытается выделить:
   - текст вопроса;
   - варианты ответа;
   - идентификаторы вариантов: A, B, C, D и т. п.
5. Пользователь при необходимости редактирует распознанный текст.
6. Клиент отправляет вопрос на сервер.
7. Сервер передаёт его выбранной LLM.
8. LLM возвращает структурированный ответ.
9. Пользователь видит:
   - правильный вариант;
   - текст правильного ответа;
   - краткое объяснение;
   - уровень уверенности;
   - предупреждение, если вопрос распознан не полностью.
10. Результат сохраняется в локальной истории.

### 2.2. Анализ изображения vision-моделью

Если вопрос содержит:

- формулу;
- график;
- схему;
- таблицу;
- программный код;
- геометрический рисунок;
- изображение как часть условия,

клиент может вместе с OCR отправить исходное изображение.

Сервер должен использовать изображение только при работе с моделью, поддерживающей vision input.

### 2.3. Повторный анализ

Пользователь может:

- изменить распознанный текст;
- выбрать другую модель;
- выбрать другого провайдера;
- повторить запрос;
- включить или отключить отправку изображения.

### 2.4. История

Приложение хранит локально:

- дату запроса;
- изображение или ссылку на локальный файл;
- распознанный вопрос;
- варианты ответа;
- полученный ответ;
- объяснение;
- confidence;
- использованный сервер;
- провайдера;
- модель.

---

## 3. UX

### 3.1. Главный экран

Основные действия:

- **Сфотографировать вопрос**;
- **Выбрать изображение**;
- **История**;
- **Настройки**.

### 3.2. Экран распознавания

Отображаются:

- исходное изображение;
- распознанный текст;
- вопрос;
- список вариантов ответа;
- переключатель `Отправить изображение модели`;
- кнопка `Получить ответ`.

Пользователь должен иметь возможность вручную исправить OCR.

### 3.3. Экран результата

Пример:

```text
Правильный ответ

B. HTTPS

HTTPS использует TLS для защищённой
передачи HTTP-трафика.

Уверенность: высокая
```

Дополнительные действия:

- `Подробнее`;
- `Повторить`;
- `Изменить модель`;
- `Скопировать`;
- `Поделиться`;
- `Удалить из истории`.

### 3.4. Режим отображения результата

Настройка:

```text
Ответ
○ Только правильный вариант
● Ответ + краткое объяснение
○ Подробное объяснение
```

---

## 4. Архитектура

```text
┌──────────────────────────────────┐
│         Flutter Android          │
│                                  │
│ Camera / Gallery                 │
│ Image preprocessing              │
│ ML Kit OCR                       │
│ Question parser                  │
│ Drift / SQLite                   │
│ Secure Storage                   │
│ HTTPS + fingerprint pinning      │
└─────────────────┬────────────────┘
                  │
                HTTPS
                  │
┌─────────────────▼────────────────┐
│            Go Server             │
│                                  │
│ REST API                         │
│ Authentication                  │
│ Request validation              │
│ Prompt Builder                  │
│ LLM Provider abstraction        │
│ Structured response validation  │
│ TLS certificate manager         │
└──────────────┬───────────┬───────┘
               │           │
               ▼           ▼
          OpenRouter    RouterAI
```

---

## 5. Flutter-клиент

### 5.1. Технологии

Рекомендуемый стек:

- Flutter;
- Dart;
- Riverpod;
- go_router;
- Dio;
- Drift + SQLite;
- flutter_secure_storage;
- CameraX через Flutter camera plugin;
- image_picker;
- Google ML Kit Text Recognition.

### 5.2. Слои клиента

```text
presentation/
application/
domain/
data/
infrastructure/
```

Пример структуры:

```text
lib/
  app/
  core/
    network/
    security/
    storage/
    errors/
  features/
    capture/
    ocr/
    questions/
    history/
    servers/
    settings/
```

---

## 6. OCR

OCR выполняется локально.

Pipeline:

```text
Image
  ↓
Rotation correction
  ↓
Crop
  ↓
Perspective correction
  ↓
Contrast / sharpness normalization
  ↓
OCR
  ↓
Question parser
```

Парсер должен пытаться выделять варианты вида:

```text
A.
B.
C.
D.
```

а также:

```text
1.
2.
3.
4.
```

Необходимо сохранять оригинальный OCR-текст для ручного редактирования.

---

## 7. Go backend

### 7.1. Требования

- Go 1.25+;
- REST API;
- HTTPS;
- graceful shutdown;
- structured logging;
- request ID;
- timeout для внешних LLM API;
- retry только для безопасных transient ошибок;
- rate limiting;
- health endpoints;
- Docker image;
- Docker Compose.

### 7.2. Структура проекта

```text
cmd/
  server/

internal/
  api/
  auth/
  config/
  llm/
    provider/
    openai_compatible/
    prompt/
  questions/
  security/
  tls/
  storage/
  observability/
```

---

## 8. LLM Provider abstraction

Бизнес-логика не должна зависеть от конкретного провайдера.

Пример интерфейса:

```go
type Provider interface {
    AnalyzeQuestion(
        ctx context.Context,
        req AnalyzeRequest,
    ) (*AnalyzeResponse, error)

    ListModels(
        ctx context.Context,
    ) ([]Model, error)
}
```

Базовая реализация:

```text
OpenAICompatibleProvider
```

Конфигурация определяет:

- base URL;
- API key;
- дополнительные headers;
- модель;
- capabilities.

---

## 9. Поддерживаемые LLM-провайдеры

### 9.1. OpenRouter

Конфигурация:

```yaml
providers:
  openrouter:
    type: openai-compatible
    base_url: https://openrouter.ai/api/v1
    api_key_env: OPENROUTER_API_KEY
```

### 9.2. RouterAI

```yaml
providers:
  routerai:
    type: openai-compatible
    base_url: https://routerai.ru/api/v1
    api_key_env: ROUTERAI_API_KEY
```

### 9.3. Расширение

Архитектура должна позволять добавить:

```text
OpenAI
Ollama
vLLM
LM Studio
Custom OpenAI-compatible API
```

без изменения domain layer.

---

## 10. Модели

Для каждой модели желательно хранить:

```json
{
  "id": "provider/model-name",
  "name": "Model Name",
  "capabilities": {
    "text": true,
    "vision": true
  }
}
```

Клиент должен запрещать отправку изображения модели без vision capability.

---

## 11. Prompting

System prompt должен заставлять модель работать как движок анализа тестов.

Основные правила:

- отвечать только на переданный вопрос;
- не придумывать отсутствующие варианты;
- поддерживать один или несколько правильных ответов;
- объяснять ответ кратко и предметно;
- явно сообщать о недостаточных данных;
- учитывать изображение, если оно передано;
- возвращать только структурированный JSON.

Пример логики ответа:

```json
{
  "status": "answered",
  "correctOptionIds": ["B"],
  "explanation": "HTTPS использует TLS для защищённой передачи HTTP-трафика.",
  "confidence": 0.96,
  "warnings": []
}
```

Неопределённый ответ:

```json
{
  "status": "uncertain",
  "correctOptionIds": [],
  "explanation": null,
  "confidence": 0.31,
  "warnings": [
    "Option C is not readable"
  ]
}
```

---

## 12. Confidence

Числовое значение используется внутренне:

```text
0.0 .. 1.0
```

В UI рекомендуется показывать:

```text
HIGH
MEDIUM
LOW
```

Пример отображения:

```text
>= 0.85    HIGH
0.60–0.84  MEDIUM
< 0.60     LOW
```

Пороговые значения должны быть конфигурируемыми.

Confidence от LLM не следует считать калиброванной вероятностью правильности.

---

## 13. API

### 13.1. Server info

```http
GET /api/v1/server/info
```

Ответ:

```json
{
  "serverId": "019d1234-...",
  "name": "Test Assistant Server",
  "version": "1.0.0"
}
```

### 13.2. Providers

```http
GET /api/v1/llm/providers
```

```json
[
  {
    "id": "openrouter",
    "name": "OpenRouter"
  },
  {
    "id": "routerai",
    "name": "RouterAI"
  }
]
```

### 13.3. Models

```http
GET /api/v1/llm/models?provider=openrouter
```

### 13.4. Analyze question

```http
POST /api/v1/questions/analyze
Content-Type: multipart/form-data
```

Поля:

```text
question
options
language
provider
model
image (optional)
```

Ответ:

```json
{
  "requestId": "...",
  "status": "answered",
  "correctOptionIds": ["B"],
  "answerText": "HTTPS",
  "explanation": "...",
  "confidence": 0.96,
  "confidenceLevel": "high",
  "warnings": []
}
```

---

## 14. Ошибки API

Формат:

```json
{
  "error": {
    "code": "LLM_TIMEOUT",
    "message": "The LLM provider did not respond in time",
    "requestId": "..."
  }
}
```

Пример кодов:

```text
INVALID_REQUEST
UNAUTHORIZED
MODEL_NOT_FOUND
MODEL_DOES_NOT_SUPPORT_VISION
LLM_PROVIDER_UNAVAILABLE
LLM_TIMEOUT
LLM_INVALID_RESPONSE
IMAGE_TOO_LARGE
TLS_CONFIGURATION_ERROR
INTERNAL_ERROR
```

---

## 15. TLS

HTTPS обязателен.

Сервер должен поддерживать:

1. сертификат, переданный администратором;
2. self-signed сертификат.

### 15.1. Автоматическая генерация

При запуске:

```text
server.crt exists?
server.key exists?
       │
       ├── yes → load
       │
       └── no
            ↓
       generate private key
            ↓
       generate X.509 certificate
            ↓
       persist certificate and key
```

Рекомендуемый ключ:

```text
ECDSA P-256
```

Fingerprint:

```text
SHA-256(DER certificate)
```

---

## 16. Хранение сертификатов

```text
/certs/server.crt
/certs/server.key
```

Каталог должен быть persistent Docker volume или bind mount.

Нельзя генерировать новый сертификат при каждом рестарте контейнера.

---

## 17. Fingerprint pinning

### 17.1. Первое подключение

При подключении к серверу с неизвестным self-signed сертификатом:

1. TLS handshake получает сертификат.
2. Клиент вычисляет SHA-256 fingerprint.
3. Пользователь видит fingerprint.
4. Пользователь самостоятельно сравнивает fingerprint с fingerprint сервера.
5. Пользователь подтверждает доверие.
6. Fingerprint сохраняется в Secure Storage.

Пример UI:

```text
Новый сервер

https://192.168.1.10:8447

SHA-256 fingerprint

A3:41:9C:7F:38:0B:21:EF:...

[Отмена]
[Доверять]
```

### 17.2. Повторное подключение

```text
received fingerprint
        ↓
compare
        ↓
┌───────┴───────┐
│               │
match        mismatch
│               │
allow           block
```

### 17.3. Изменение сертификата

Если fingerprint изменился:

```text
CERTIFICATE_CHANGED
```

Клиент должен заблокировать соединение.

Пользователь должен явно выполнить:

```text
Настройки сервера
→ Сбросить доверенный сертификат
```

после чего процедура доверия выполняется заново.

### 17.4. Запрещённая реализация

Нельзя использовать глобальное:

```dart
badCertificateCallback = (...) => true;
```

Допускается принятие self-signed сертификата только после проверки pinned fingerprint.

---

## 18. Отображение fingerprint на сервере

При запуске сервер выводит:

```text
HTTPS listening on :8447

Certificate SHA-256 fingerprint:
A3:41:9C:7F:38:0B:21:EF:...
```

Можно дополнительно предоставить CLI-команду:

```bash
./server certificate fingerprint
```

Fingerprint нельзя считать доверенным только потому, что он получен через тот же непроверенный HTTPS-канал.

---

## 19. Идентификатор сервера

При первом запуске генерируется постоянный:

```text
serverId = UUID
```

Хранение:

```text
/data/server.json
```

Пример:

```json
{
  "serverId": "019d1234-...",
  "name": "Home Test Assistant"
}
```

---

## 20. Несколько серверов

Flutter-клиент может хранить несколько серверов:

```text
Домашний
https://192.168.1.15:8447

VPS
https://test.example.com:8447
```

Для каждого сервера отдельно хранятся:

- serverId;
- URL;
- fingerprint;
- display name;
- auth data.

---

## 21. Аутентификация

Для MVP рекомендуется простой Bearer token.

```http
Authorization: Bearer <token>
```

Token генерируется сервером и сохраняется клиентом в Secure Storage.

В дальнейшем можно добавить:

- API keys;
- user accounts;
- OAuth/OIDC.

---

## 22. Хранение на клиенте

Рекомендуется:

```text
Drift / SQLite
```

### Таблица servers

```text
id
server_id
name
base_url
created_at
last_used_at
```

Fingerprint и credentials в SQLite не хранить.

### Таблица test_sessions

```text
id
name
created_at
updated_at
```

### Таблица questions

```text
id
session_id
image_path
ocr_text
question_text
options_json
answer_json
provider
model
confidence
created_at
```

---

## 23. Secure Storage

В `flutter_secure_storage` хранить:

```text
server fingerprint
Bearer token
other server secrets
```

Не хранить там историю тестов и изображения.

---

## 24. Серверное хранение

Для MVP сервер может быть stateless.

Постоянно хранятся только:

```text
/data/server.json
/certs/server.crt
/certs/server.key
```

API keys передаются через environment variables или Docker secrets.

PostgreSQL для MVP не требуется.

---

## 25. Docker Compose

Пример:

```yaml
services:
  test-assistant:
    image: test-assistant-server:latest
    restart: unless-stopped

    ports:
      - "8447:8447"

    volumes:
      - ./data:/data
      - ./certs:/certs

    environment:
      APP_LISTEN_ADDR: ":8447"

      TLS_CERT_FILE: /certs/server.crt
      TLS_KEY_FILE: /certs/server.key

      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY}
      ROUTERAI_API_KEY: ${ROUTERAI_API_KEY}
```

---

## 26. Конфигурация сервера

Пример:

```yaml
server:
  name: Home Test Assistant
  listen: :8447

storage:
  data_dir: /data

security:
  auth_enabled: true

llm:
  default_provider: openrouter
  default_model: google/gemini-2.5-flash

providers:
  openrouter:
    type: openai-compatible
    base_url: https://openrouter.ai/api/v1
    api_key_env: OPENROUTER_API_KEY

  routerai:
    type: openai-compatible
    base_url: https://routerai.ru/api/v1
    api_key_env: ROUTERAI_API_KEY
```

---

## 27. Сетевые timeout

Рекомендуемые значения:

```text
connect timeout: 10 s
request timeout: 60 s
LLM timeout:     45 s
```

Должны быть конфигурируемыми.

---

## 28. Retry

Retry допускается только для transient ошибок:

```text
HTTP 429
HTTP 502
HTTP 503
HTTP 504
connection reset
```

Пример:

```text
attempt 1
↓ 500 ms
attempt 2
↓ 1500 ms
attempt 3
```

Не retry:

```text
400
401
403
404
```

---

## 29. Ограничения изображений

Сервер должен ограничивать:

```text
maximum image size
maximum request size
allowed MIME types
```

Например:

```text
JPEG
PNG
WEBP
```

Изображение можно ресайзить на клиенте до разумного разрешения до отправки.

---

## 30. Безопасность

### Обязательно

- HTTPS;
- certificate pinning для self-signed TLS;
- LLM API keys только на сервере;
- secrets не писать в логи;
- ограничение размера запроса;
- input validation;
- rate limiting;
- request timeout;
- secure local storage;
- Docker process запускать не от root;
- минимальный runtime image;
- регулярное обновление зависимостей.

### Не делать

- отключать проверку TLS глобально;
- помещать LLM API key в APK;
- логировать изображения и полный OCR по умолчанию;
- автоматически доверять изменившемуся сертификату;
- хранить Bearer token в обычном SQLite.

---

## 31. Privacy

По умолчанию сервер не должен сохранять:

- фотографии вопросов;
- OCR;
- LLM prompts;
- ответы LLM.

Они используются только в рамках запроса.

Локальную историю хранит Android-клиент.

В настройках можно добавить:

```text
Удалять изображения после анализа
```

---

## 32. Логирование

Structured JSON logs:

```json
{
  "level": "info",
  "request_id": "...",
  "method": "POST",
  "path": "/api/v1/questions/analyze",
  "duration_ms": 1250,
  "provider": "openrouter",
  "model": "...",
  "status": 200
}
```

Не логировать:

- API keys;
- Bearer tokens;
- изображения;
- полный prompt;
- полный ответ LLM.

---

## 33. Health endpoints

```http
GET /health/live
GET /health/ready
```

`live` проверяет процесс.

`ready` проверяет:

- конфигурацию;
- доступность локального storage;
- корректность TLS configuration.

LLM provider не должен обязательно вызываться на каждом readiness check.

---

## 34. Метрики

Опционально:

```text
requests_total
request_duration_seconds
llm_requests_total
llm_request_duration_seconds
llm_errors_total
ocr_requests_total
```

В будущем можно добавить Prometheus endpoint.

---

## 35. Test Session

В следующей версии добавить режим:

```text
Новый тест
   ↓
Question 1
Question 2
Question 3
...
```

И итог:

```text
Всего вопросов: 40
Высокая уверенность: 32
Средняя: 6
Низкая: 2
```

---

## 36. Режим обучения

Опциональный режим:

1. Пользователь сначала выбирает свой ответ.
2. Затем запрашивает проверку.
3. Приложение показывает:
   - его выбор;
   - правильный ответ;
   - объяснение.

Это позволяет использовать приложение не только как помощник, но и как инструмент подготовки.

---

## 37. Обработка ошибок UX

### Нет сети

```text
Не удалось подключиться к серверу.
Проверьте сеть и адрес сервера.
```

### Изменился сертификат

```text
Сертификат сервера изменился.
Соединение заблокировано.
```

### OCR плохого качества

```text
Не удалось надёжно распознать вопрос.
Попробуйте сделать фотографию ещё раз.
```

### LLM timeout

```text
Модель не ответила вовремя.
Попробуйте повторить запрос.
```

### Нет vision support

```text
Выбранная модель не поддерживает изображения.
Будет отправлен только распознанный текст.
```

---

## 38. Roadmap

### MVP 0.1

- Flutter Android;
- камера;
- выбор изображения;
- ML Kit OCR;
- ручное редактирование OCR;
- определение вопроса и вариантов;
- Go backend;
- Docker Compose;
- HTTPS;
- self-signed certificate generation;
- fingerprint verification;
- один сервер;
- Bearer token;
- OpenRouter;
- RouterAI;
- выбор provider/model;
- text-only анализ;
- JSON structured answer;
- Drift/SQLite history.

### Version 0.2

- vision models;
- передача изображения;
- automatic model capability detection;
- улучшенный image preprocessing;
- несколько серверов;
- Test Session;
- повторный анализ;
- фильтры истории;
- экспорт результата.

### Version 0.3

- continuous camera mode;
- автоматический захват вопроса;
- пакетная обработка нескольких вопросов;
- режим обучения;
- статистика;
- custom OpenAI-compatible provider;
- server-side configurable prompts;
- model fallback.

### Version 1.0

- стабильная миграция DB;
- backup/restore истории;
- localization;
- accessibility;
- advanced TLS management;
- optional Prometheus metrics;
- configurable rate limits;
- provider failover;
- hardened Docker image;
- automated integration tests;
- release pipeline.

---

## 39. Нефункциональные требования

### Производительность

- запуск приложения: < 3 секунд на среднем устройстве;
- OCR: желательно < 2 секунд;
- локальная навигация: без видимых задержек;
- UI не должен блокироваться во время LLM запроса.

### Надёжность

- graceful handling network errors;
- повтор запроса пользователем;
- сохранение OCR перед отправкой;
- сохранение черновика при закрытии экрана;
- восстановление состояния после process recreation.

### Совместимость

Минимальная целевая версия:

```text
Android 10+
```

Можно пересмотреть перед релизом.

---

## 40. Тестирование

### Flutter

- unit tests;
- widget tests;
- repository tests;
- TLS fingerprint tests;
- SQLite migration tests;
- OCR parser tests.

### Go

- unit tests;
- API tests;
- provider adapter tests;
- TLS generation tests;
- certificate fingerprint tests;
- malformed LLM response tests;
- timeout/retry tests.

### Integration

Необходимы сценарии:

1. trusted public certificate;
2. первый self-signed certificate;
3. сохранённый self-signed fingerprint;
4. изменившийся сертификат;
5. OpenRouter response;
6. RouterAI response;
7. LLM timeout;
8. invalid JSON from LLM;
9. vision model;
10. text-only model with image request.

---

## 41. Основные архитектурные решения

| Область | Решение |
|---|---|
| Client | Flutter |
| Platform | Android |
| State management | Riverpod |
| Local DB | Drift / SQLite |
| Secrets | flutter_secure_storage |
| OCR | Google ML Kit |
| HTTP client | Dio |
| Backend | Go |
| Deployment | Docker Compose |
| Transport | HTTPS |
| Self-signed trust | SHA-256 fingerprint pinning |
| Server certificate | Generated automatically if absent |
| LLM integration | OpenAI-compatible provider abstraction |
| Initial providers | OpenRouter, RouterAI |
| Images | Optional vision input |
| Server database | Not required for MVP |
| LLM keys | Server-side only |

---

## 42. Итоговая MVP-схема

```text
Android / Flutter
       │
       ├── Camera
       ├── ML Kit OCR
       ├── Drift / SQLite
       ├── Secure Storage
       │
       ▼
 HTTPS + certificate pinning
       │
       ▼
Go Server / Docker Compose
       │
       ├── REST API
       ├── Authentication
       ├── Prompt Builder
       ├── JSON validation
       ├── TLS certificate manager
       │
       ├───────────────┐
       ▼               ▼
   OpenRouter       RouterAI
```

Главный принцип архитектуры:

> Клиент отвечает за UX, OCR, локальную историю и доверие к серверу. Сервер отвечает за безопасность LLM API keys, маршрутизацию запросов к моделям, prompt management и нормализацию ответа.

