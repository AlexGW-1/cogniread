# Hardening (VPS)

## 1) SSH hardening
- Disable password login
- Use SSH keys only
- Change default SSH port (optional)

Example `/etc/ssh/sshd_config`:
```
PasswordAuthentication no
PermitRootLogin no
```
Then:
```
$ sudo systemctl reload sshd
```

## 2) Firewall (UFW)
Allow only SSH + HTTP/HTTPS:
```
$ sudo ufw default deny incoming
$ sudo ufw default allow outgoing
$ sudo ufw allow 22/tcp
$ sudo ufw allow 80/tcp
$ sudo ufw allow 443/tcp
$ sudo ufw enable
```

## 3) Fail2ban
```
$ sudo apt-get install -y fail2ban
$ sudo systemctl enable --now fail2ban
```

## 4) TLS termination
Use a reverse proxy (Caddy/Traefik/Nginx) with auto TLS.
- Expose only proxy ports (80/443)
- Keep internal services on compose network

## 5) Docker hardening
- Avoid privileged containers
- Use least-privilege volumes
- Keep images up to date

## 6) Backups
- Schedule `scripts/backup.sh` via cron
- Store backups off-host (rsync/S3)

## 7) Monitoring
- Enable basic host monitoring (CPU/RAM/disk)
- Alert on low disk and failed backups
