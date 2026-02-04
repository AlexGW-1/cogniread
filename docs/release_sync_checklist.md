# Памятка перед релизом (Sync: Google Drive + OneDrive)

## 1) Секреты и ключи
- Не хранить client_secret в репозитории.
- Вынести OAuth‑креды в CI/CD секреты или закрытый `sync_oauth.json` (пример: `docs/examples/sync_oauth.example.json`).
- Перегенерировать Client Secret (Google/Microsoft), если когда‑либо попадал в git.
- При утечке секретов — **сделать ротацию ключей** и обновить локальные `.env`/`sync_oauth.json`.
- Если секреты попадали в историю Git — **очистить историю** (git filter-repo) и форс‑пуш:\n  `git filter-repo --path assets/sync_oauth.json --path client_secret_*.json --path infra/gcp/prod.env --invert-paths`\n  Затем: `git push --force --all`.

## 1.1 Secret scanning
- Включить secret scanning (GitHub) или gitleaks workflow (`.github/workflows/secret-scan.yml`).

## 2) Google Cloud
- OAuth consent screen → статус **In production** (если доступ всем).
- Включён **Google Drive API**.
- Scope минимальный: `drive.appdata`.
- iOS/Android клиенты зарегистрированы корректно:
  - iOS: Bundle ID = `com.cogniread.cogniread`
  - Android: package = `com.cogniread.cogniread`, SHA‑1/256 **release‑подписи**

## 3) Microsoft Entra (OneDrive)
- Redirect URI:
  - iOS/macOS: `msauth.com.cogniread.cogniread://auth`
  - Android: `msauth://com.cogniread.cogniread/<RELEASE_HASH>`
- **Allow public client flows = Yes**
- API permissions → Microsoft Graph → Delegated:
  - `Files.ReadWrite.AppFolder`
- Нажать **Grant admin consent** (если требуется).

## 4) Android release signing
- Создать release keystore.
- Добавить `signingConfig` в `android/app/build.gradle.kts`.
- Получить SHA‑1 (Base64) release‑ключа и обновить Android redirect в Azure.
- Убедиться, что release‑билд не подписывается debug‑ключом.

## 5) iOS/macOS URL‑schemes
- `Info.plist` содержит:
  - `com.googleusercontent.apps.<iOS_client_id>` (Google)
  - `msauth.com.cogniread.cogniread` (OneDrive)

## 6) Конфиг приложения
- `sync_oauth.json` для релиза использует **release‑клиенты**:
  - Google: iOS/Android/desktop
  - OneDrive: iOS/Android/desktop
- В debug можно оставлять тестовые креды, в release — только продовые.

## 7) Проверки перед выкладкой
- iOS/Android/macOS: вход в Google/OneDrive проходит.
- Первичная синхронизация создаёт app‑folder и файлы.
- «Проверить подключение» возвращает успех.
- Отзыв доступа → приложение показывает ошибку и предлагает переподключение.
