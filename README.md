# IT-Infrastructure-DevOps-Trainee-assignment

A hardened Ubuntu host running a multi-container stack (Nginx → Flask →
MySQL) with Prometheus/Node Exporter monitoring, automated health checks,
and scheduled database backups.

**Stack:** Ubuntu 22.04 LTS (VirtualBox, bridged adapter) · Docker &
Docker Compose · Nginx · Flask · MySQL 8 · Prometheus · Node Exporter ·
Bash · cron

Nginx (80) is published to the host's network interface and reachable from
any device on the network. Prometheus (9090) is published to `127.0.0.1`
only — reachable from inside the VM, not from the network (see Security
notes for why). The app, database, and node-exporter are only reachable
from other containers on the `devops-network` bridge network.

---

## 1. Prerequisites

- Ubuntu 22.04 LTS VM in VirtualBox (Bridged Adapter — gets its own LAN IP)
- An SSH key pair generated on your **host machine** (not the VM):
  ```powershell
  ssh-keygen -t ed25519 -C "devops"
  cat ~/.ssh/id_ed25519.pub
  ```
  Keep the private key on your host, you'll paste the public key onto the
  VM during setup.

---

## 2. Setup

### Step 1 — Provision & harden the host (Task 1)

Create the `trainee` user and add it to the `sudo` group:
```bash
sudo adduser trainee
sudo usermod -aG sudo trainee
```

Install your SSH public key for `trainee`:
```bash
sudo -iu trainee
mkdir -p ~/.ssh && chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys    # paste your public key, save, exit
chmod 600 ~/.ssh/authorized_keys
exit
```

Harden the SSH daemon — edit `/etc/ssh/sshd_config`:
```bash
sudo nano /etc/ssh/sshd_config
```
Set these directives:
```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```
Validate before restarting, then apply:
```bash
sudo sshd -t
sudo systemctl restart ssh
```

Configure ufw to allow only the required ports:
```bash
sudo ufw allow 2222/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

**Do not close your current session** until you've confirmed in a new
window that this works:
```bash
ssh -p 2222 trainee@<vm-ip>
```

<details>
<summary><strong>Troubleshooting: SSH still listening on port 22 after restart</strong></summary>

If the login above fails with **"Connection refused"**, check what's
actually listening:
```bash
sudo ss -tlnp | grep ssh
```
If it still shows port `22`, the cause is Ubuntu's **systemd socket
activation** for SSH — a separate `ssh.socket` unit binds to port 22
independently and never reads the `Port` directive in `sshd_config`.
Confirm with:
```bash
sudo systemctl status ssh
```
A `TriggeredBy: ● ssh.socket` line confirms this is the cause. Fix it:
```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep ssh    # should now show a new PID on 2222
```
If the PID is unchanged, `sudo reboot` to force a clean state and re-check.

</details>

### Step 2 — Install Docker
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker trainee
```
Log out and back in (`exit`, then reconnect) so the group membership takes
effect — group changes only apply to new sessions. Confirm with:
```bash
groups          # should list 'docker'
docker ps -a    # should run with no sudo
```

### Step 3 — Bring up the application stack (Task 2)
```bash
git clone https://github.com/AnubhavPradhan/IT-Infrastructure-DevOps-Trainee-assignment.git
cd IT-Infrastructure-DevOps-Trainee-assignment
docker compose up -d --build
```
This builds the Flask image and starts five containers: `nginx-reverse-proxy`,
`flask-app`, `mysql-db`, `prometheus`, and `node-exporter`.

### Step 4 — Install the health check script + cron (Task 3)
```bash
sudo mkdir -p /opt/scripts
sudo cp scripts/infra_health_check.sh /opt/scripts/
sudo chmod +x /opt/scripts/infra_health_check.sh
sudo /opt/scripts/infra_health_check.sh   # run once manually to confirm it works
```
Install the cron job (every 15 minutes) — open the root crontab:
```bash
sudo crontab -e
```
Add this line, then save and exit:
```
*/15 * * * * /opt/scripts/infra_health_check.sh
```
Confirm it's there:
```bash
sudo crontab -l
```

### Step 5 — Install the backup script (Task 4)
```bash
sudo cp scripts/db_backup.sh /opt/scripts/
sudo chmod +x /opt/scripts/db_backup.sh
sudo /opt/scripts/db_backup.sh
ls -lh /var/backups/db/
```

---

## 3. Verification commands

**Firewall rules:**
```bash
sudo ufw status verbose
```
![The firewall status](docs/screenshots/The%20firewall%20status%20%28ufw%20status%20verbose%29.png)

**Running containers:**
```bash
docker ps
```
![Running containers](docs/screenshots/Running%20containers%20%28docker%20ps%29.png)

**App via reverse proxy:**
```bash
curl http://localhost/
```
![Browser output accessing the reverse-proxied application](docs/screenshots/Browser%20output%20accessing%20the%20reverse-proxied%20application.png)

**App ↔ DB connectivity:**
```bash
curl http://localhost/db
```

**Basic app status:**
```bash
curl http://localhost/health
```

**Health check script — manual run and log output:**
```bash
sudo /opt/scripts/infra_health_check.sh
cat /var/log/infra_health.log
```
![Successful execution of infra_health_check.sh and log outputs](docs/screenshots/Successful%20execution%20of%20infra_health_check.sh%20and%20log%20outputs.png)

**Cron job installed:**
```bash
sudo crontab -l
```

**Backup created:**
```bash
ls -lh /var/backups/db/
```

---

## 4. Monitoring (Task 4)

Prometheus scrapes Node Exporter every 15 seconds (config in
`monitoring/prometheus.yml`) for host-level metrics — CPU, memory, disk,
network — with no extra setup on the host itself.

**Access is restricted to the VM itself** (see Security notes below for
why) — view the dashboard from inside the VM, not from the host or
another device on the network:
- Dashboard/targets page: `http://localhost:9090`
- Confirm both targets are `UP`: `http://localhost:9090/targets`
- Example queries to try in the Prometheus UI:
  - `node_cpu_seconds_total` — per-core CPU time breakdown
  - `node_memory_MemAvailable_bytes` — available memory over time

Port 9090 is bound to `127.0.0.1` only in `docker-compose.yml` — unlike
Nginx's port 80, it is intentionally **not** reachable from the network.

---

## 5. Database backup & restore (Task 4)

Backups are stored at `/var/backups/db/db_backup_YYYYMMDD.sql.gz`,
retained for 7 days (older files are pruned automatically by the script).

**Restore procedure** (tested manually, do not run blindly):
```bash
sudo zcat /var/backups/db/db_backup_$(date +%Y%m%d).sql.gz | \
  docker exec -i mysql-db mysql -udevops -pdevopspass devopsdb
```
`$(date +%Y%m%d)` assumes you're restoring today's backup — replace it
with an explicit date (e.g. `db_backup_20260911.sql.gz`) when restoring
an older one.

---

## 6. Teardown

```bash
docker compose down          # stop stack, keep mysql-data and prometheus-data volumes
docker compose down -v       # stop stack AND delete all volumes (destructive)
```

To remove the cron job:
```bash
sudo crontab -e   # delete the infra_health_check.sh line, save and exit
```

---

## 7. Security notes

- Root SSH login disabled; password auth disabled; SSH moved off the default port.
- ufw default-denies everything except 2222 (SSH), 80 (HTTP), 443 (HTTPS).
- The app, database, and node-exporter are **not** published to the host —
  only reachable via the `devops-network` Docker network, so Nginx is the
  only entry point reachable from the network at all (Prometheus is
  published only to `127.0.0.1`, see below).
- Database credentials in `docker-compose.yml` are placeholders for this
  assignment; in production these would move to a `.env` file (already
  git-ignored) or a secrets manager.
- **Prometheus has no built-in authentication**, and Docker-published
  container ports bypass `ufw`'s ruleset entirely (Docker inserts its own
  rules into the `DOCKER-USER` iptables chain, which take precedence over
  `ufw`). This meant Prometheus's port 9090 was reachable from any device
  on the local network despite `ufw` only listing 2222/80/443 as allowed —
  confirmed by accessing it from a phone on the same Wi-Fi. Since an
  unauthenticated monitoring dashboard shouldn't be exposed to the network,
  `docker-compose.yml` now binds it to the loopback interface only:
  ```yaml
  prometheus:
    ports:
      - "127.0.0.1:9090:9090"
  ```
  This restricts access to the VM itself — verified by confirming the
  dashboard loads at `http://localhost:9090` from inside the VM, while
  `http://<vm-ip>:9090` now times out from any other device on the
  network. In a real deployment, the equivalent (and more common) approach
  would be putting Prometheus behind a reverse proxy with authentication,
  or restricting it to an internal-only network segment rather than
  exposing the port directly at all.