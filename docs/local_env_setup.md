# Локальные конфиги (.env и sync_oauth.json)

Все локальные секреты создаются вручную и **не коммитятся**.

## 1) Compose (local/dev/VPS)
```
$ cp infra/compose/.env.example infra/compose/.env
```
Заполни значения в `infra/compose/.env`.

## 2) GCP (Cloud Run)
```
$ cp infra/gcp/prod.env.example infra/gcp/prod.env
```
Заполни значения в `infra/gcp/prod.env`.

## 3) Server (локально, если нужно)
Создай `server/.env` вручную с нужными переменными.

## 4) OAuth для синка
Скопируй пример и заполни:
```
$ cp docs/examples/sync_oauth.example.json assets/sync_oauth.json
```

## Важно
- `infra/compose/.env`, `infra/gcp/prod.env`, `server/.env`, `assets/sync_oauth.json` — **в .gitignore**.
- Если секреты попадали в git‑историю, сделай ротацию и очистку истории.
