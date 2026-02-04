# VPS Deployment

Portable VPS deployment using Docker + Compose.

## Prereqs
- Ubuntu 22.04+ (or Debian 12+)
- SSH access with sudo
- DNS A/AAAA for your domain

## Install Docker
```
$ sudo apt-get update -y
$ sudo apt-get install -y ca-certificates curl gnupg
$ sudo install -m 0755 -d /etc/apt/keyrings
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$ echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
$ sudo apt-get update -y
$ sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
$ sudo usermod -aG docker $USER
```
Re-login after adding your user to the docker group.

## Prepare config
```
$ cp infra/compose/.env.example infra/compose/.env
```
Fill secrets in `infra/compose/.env` (never commit it).

## Start stack
```
$ docker compose -f infra/compose/compose.yaml --env-file infra/compose/.env up -d
```

## Run smoke tests
```
$ ./scripts/smoke.sh
```

## Runbooks
- `infra/vps/runbooks/hardening.md`
- `infra/vps/runbooks/backup.md`
- `infra/vps/runbooks/restore.md`
- `infra/vps/runbooks/migration.md`
- `infra/vps/runbooks/smoke-tests.md`
