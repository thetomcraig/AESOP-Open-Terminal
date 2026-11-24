# AESOP Open Terminal Configuration

> Audience: AI agents and engineers maintaining the AESOP Open Terminal deployment.
>
> This document describes the deployed design and operational decisions. Treat commands and configuration as the source of truth only after verifying them on the host; this document can become stale.

## 1. Purpose and architecture

AESOP is a Raspberry Pi 3 Model B Plus running Raspberry Pi OS (Debian 13/Trixie, 64-bit). It hosts Open Terminal in Docker as a separately isolated execution environment for Open WebUI on ARISTON.

The intended workflow is to let an AI execute shell commands and create/run scripts in a persistent workspace on AESOP, while keeping ARISTON's application data, Docker daemon, and other host services off the execution container.

### Hosts

| Host | Role | Known address |
|---|---|---|
| AESOP | Raspberry Pi running Open Terminal | `192.168.1.199` |
| ARISTON | Ubuntu server running Open WebUI and other services | `192.168.1.131` |
| Mac | Administrative workstation / SSH client | `192.168.1.85` |
| Router | LAN gateway | `192.168.1.1` |

These are recorded addresses, not guaranteed DHCP reservations. Verify current addresses before changing firewall rules or connection settings.

### AESOP hardware

- Raspberry Pi 3 Model B Plus, Rev 1.4
- 64-bit ARM (`aarch64`)
- Approximately 900 MiB usable RAM
- Four logical CPUs
- Approximately 15 GB storage
- Wireless interface: `wlan0`

This hardware constraint is why the deployment uses the Open Terminal `slim` image rather than the much larger full image.

## 2. Deployment summary

- Image: `ghcr.io/open-webui/open-terminal:slim`
- Container name: `open-terminal`
- Published endpoint: `http://192.168.1.199:8000`
- Container working directory: `/workspace`
- Host workspace: `/home/open-terminal/workspace`
- Compose directory: `/home/open-terminal/deployment`
- Compose file: `/home/open-terminal/deployment/compose.yml`
- API key file: `/home/open-terminal/api-key`
- Container API key secret path: `/run/secrets/api_key`
- Container runs application as UID/GID `1000:1000` (`user`)
- Workspace host ownership: UID `999`, GID `1000`, mode `0770` (recorded setup)
- Resource limits: 384 MiB memory, 512 MiB memory+swap, 1.5 CPUs, 128 PIDs
- `no-new-privileges` enabled
- No Docker socket mounted
- Only the workspace is bind-mounted from the host

The API key is a secret. Never print it, paste it into chat, commit it, or include it in logs or documentation.

## 3. Host preparation and security controls

### 3.1 Operating system and Docker

AESOP runs Raspberry Pi OS / Debian 13 Trixie, 64-bit. Docker Engine and Docker Compose plugin were installed from the appropriate Debian repository.

Recorded versions at setup:
- Docker Engine 29.9.3
- Docker Compose 5.7.0

Check installed versions rather than assuming these remain current:

```bash
cat /etc/os-release
uname -m
docker --version
docker compose version
```

### 3.2 SSH

SSH key authentication from the Mac administrative workstation is configured and tested.

- Password authentication disabled.
- Root SSH login disabled.
- SSH access is restricted by UFW to source `192.168.1.85` on TCP port 22.

Do not broaden SSH access without an explicit administrative decision. Before changing SSH settings, retain an existing working session and validate configuration with `sshd -t`.

### 3.3 UFW

Recorded host firewall policy:

- UFW active.
- Default incoming: deny.
- Default outgoing: allow.
- Default routed: deny.
- IPv6 enabled.
- SSH TCP/22 allowed only from `192.168.1.85`.

Inspect before modifying:

```bash
sudo ufw status verbose
sudo ufw status numbered
```

Docker manipulates its own forwarding and NAT rules. UFW's routed default policy must not be assumed to filter Docker-published traffic or container egress.

### 3.4 Unneeded services

The following were disabled during hardening:

- `rpcbind.service`
- `rpcbind.socket`
- `nfs-blkmap.service`
- `wayvnc`
- `wayvnc-control`

LightDM/Xorg were retained for local monitor diagnostics. There is no intended remote desktop/VNC service.

Check current state before making changes:

```bash
systemctl is-enabled rpcbind.service rpcbind.socket nfs-blkmap.service
systemctl is-enabled wayvnc.service wayvnc-control.service
```

Some unit names may not exist on a later OS image; inspect rather than blindly applying commands.

### 3.5 Docker cgroups

The Raspberry Pi firmware command line was updated to enable the memory cgroup controller:

```text
cgroup_enable=memory
```

This was appended to `/boot/firmware/cmdline.txt`, preserving the file as a single line, and the host was rebooted. Memory limits were subsequently verified from inside a test container.

Do not overwrite the firmware command line. If editing it, preserve all existing parameters and its single-line format.

### 3.6 Host service account and paths

A dedicated host account was created:

```text
open-terminal:x:999:983::/home/open-terminal:/usr/sbin/nologin
```

Recorded directories:

| Path | Purpose |
|---|---|
| `/home/open-terminal` | Dedicated host account home; mode `0700` |
| `/home/open-terminal/deployment` | Compose deployment; root-owned, mode `0755` |
| `/home/open-terminal/workspace` | Persistent AI workspace |
| `/home/open-terminal/api-key` | API key file; root:root, mode `0600` |

The workspace is writable by container UID 1000 through host group GID 1000. Do not change ownership or permissions casually; the container's `gosu` startup path resets supplementary groups.

Inspect permissions:

```bash
sudo stat -c '%A %U:%G %n' \
  /home/open-terminal \
  /home/open-terminal/deployment \
  /home/open-terminal/workspace \
  /home/open-terminal/api-key
```

### 3.7 API key

The API key was generated as 32 random bytes encoded as hex and stored outside the deployment directory:

```bash
sudo sh -c 'umask 077; openssl rand -hex 32 > /home/open-terminal/api-key'
sudo chown root:root /home/open-terminal/api-key
sudo chmod 0600 /home/open-terminal/api-key
```

Compose mounts it as a Docker secret at `/run/secrets/api_key`; the application reads it through `OPEN_TERMINAL_API_KEY_FILE`.

Never rotate the key without also updating the Open WebUI connection. Never disclose the key value.

## 4. Docker Compose deployment

Current intended file: `/home/open-terminal/deployment/compose.yml`

```yaml
services:
  open-terminal:
    image: ghcr.io/open-webui/open-terminal:slim
    container_name: open-terminal
    restart: unless-stopped
    ports:
      - "192.168.1.199:8000:8000"

    command:
      - run
      - --host
      - "0.0.0.0"
      - --port
      - "8000"
      - --cwd
      - /workspace
      - --isolated
      - --cors-allowed-origins
      - ""

    environment:
      OPEN_TERMINAL_API_KEY_FILE: /run/secrets/api_key

    secrets:
      - api_key

    volumes:
      - type: bind
        source: /home/open-terminal/workspace
        target: /workspace

    cap_drop:
      - ALL
    cap_add:
      - NET_ADMIN
      - SETUID
      - SETGID
      - SETPCAP
      - CHOWN
      - DAC_OVERRIDE

    security_opt:
      - no-new-privileges:true

    mem_limit: 384m
    memswap_limit: 512m
    cpus: 1.5
    pids_limit: 128

secrets:
  api_key:
    file: /home/open-terminal/api-key
```

**Important current-state detail:** `OPEN_TERMINAL_ALLOWED_DOMAINS` is intentionally absent. It was previously set to an empty string, which caused the container's entrypoint to configure deny-all egress. The variable was removed and the container recreated so scripts can reach public Internet services and download Python dependencies.

Validate and deploy:

```bash
cd /home/open-terminal/deployment
sudo docker compose config -q
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail=100 open-terminal
```

The Compose file above reflects the recorded configuration. Always inspect the actual file before overwriting it; the deployed file may have changed.

## 5. Container behavior and isolation

### 5.1 Image and runtime

The `slim` image is ARM64-compatible. Recorded image characteristics:

- Python 3.12.16
- `git` and `curl` available
- `apt` and `apt-get` available
- `pip` is not installed globally
- Entrypoint: `/usr/bin/tini -- /app/entrypoint-slim.sh`
- Default application port: 8000

The container's startup script initializes `/home/user`, seeds user dotfiles, adjusts ownership, and drops privileges to the `user` account. The running application has been verified as UID/GID 1000.

### 5.2 Filesystem boundaries

Only this host path is mounted into the container:

```text
/home/open-terminal/workspace -> /workspace
```

The following were checked and were not mounted/available from the container during isolation testing:

- `/home/open-terminal`
- `/home/tom`
- `/disks`
- `/var/run/docker.sock`

Do not add host mounts without reviewing the security implications. In particular, never mount the Docker socket into this execution container.

A read-only root filesystem was explicitly deferred. Do not treat it as enabled.

### 5.3 Privileges

Recorded container tests showed:

- Application UID/GID: `1000:1000`
- Effective, permitted, and inheritable capability sets were zero for the application process.
- `NoNewPrivs: 1`
- `sudo` absent.
- Attempts to mount a filesystem failed.
- `su` authentication failed.

The Compose file grants selected capabilities to the container entrypoint so it can initialize ownership and drop privileges. The application process itself was observed with no effective capabilities. Since `OPEN_TERMINAL_ALLOWED_DOMAINS` is now unset, review whether `NET_ADMIN` and `SETPCAP` remain necessary before removing them; do not change capabilities without testing container startup and runtime behavior.

Useful inspection:

```bash
sudo docker exec open-terminal id
sudo docker exec open-terminal sh -c \
  'grep -E "^(Uid|Gid|CapInh|CapPrm|CapEff|CapBnd|NoNewPrivs):" /proc/1/status'
sudo docker inspect open-terminal --format '{{json .HostConfig.CapDrop}} {{json .HostConfig.CapAdd}}'
```

The main application process may not always be PID 1. Find it by name if `/proc/1/status` describes `tini`:

```bash
sudo docker exec open-terminal sh -c \
  'ps -eo pid,user,comm,args'
```

### 5.4 Resource limits

Compose limits:

- Memory: 384 MiB
- Memory + swap: 512 MiB
- CPU: 1.5
- PIDs: 128

Check effective limits:

```bash
sudo docker inspect open-terminal --format \
  'Memory={{.HostConfig.Memory}} MemorySwap={{.HostConfig.MemorySwap}} NanoCpus={{.HostConfig.NanoCpus}} PidsLimit={{.HostConfig.PidsLimit}}'
```

On this hardware, avoid heavy concurrent tasks, large browser automation workloads, or memory-intensive data processing. Monitor host memory and container OOM events.

## 6. Networking and firewall policy

### 6.1 Published service ingress

The service is published only on AESOP's LAN address:

```text
192.168.1.199:8000
```

It is not intentionally published on all host interfaces. The host has a persistent `DOCKER-USER` firewall policy to restrict access to this published port.

### 6.2 DOCKER-USER rules

A persistent script and systemd service were created:

- Script: `/usr/local/sbin/open-terminal-firewall`
- Unit: `/etc/systemd/system/open-terminal-firewall.service`
- Unit is enabled and ordered with Docker.
- The script rebuilds the custom `DOCKER-USER` chain.

Recorded intended rules:

```text
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -s 192.168.1.131/32 -p tcp -m conntrack --ctorigdst 192.168.1.199 --ctorigdstport 8000 -j RETURN
-A DOCKER-USER -p tcp -m conntrack --ctorigdst 192.168.1.199 --ctorigdstport 8000 -j DROP
-A DOCKER-USER -j RETURN
```

The allow rule uses `RETURN`, not `ACCEPT`, so Docker's normal forwarding rules can continue processing the connection. The established/related rule must precede the drop rule so response packets are not dropped.

The policy allows ARISTON (`192.168.1.131`) to reach the service and blocks other source addresses from reaching this published destination port. The Mac (`192.168.1.85`) was tested and blocked.

Inspect current state:

```bash
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
sudo systemctl status open-terminal-firewall.service
sudo systemctl cat open-terminal-firewall.service
sudo sed -n '1,240p' /usr/local/sbin/open-terminal-firewall
```

Do not edit Docker-managed nftables chains directly. The persistent custom-chain script is the intended place for this policy.

### 6.3 Outbound networking — current intentional policy

**The container currently has ordinary Docker outbound networking.** `OPEN_TERMINAL_ALLOWED_DOMAINS` was removed because the user wants simple access to public websites, APIs, and package repositories.

A test run from the Open WebUI terminal successfully fetched `https://example.com` and returned HTTP status `200`.

This means:
- DNS and public HTTPS requests work.
- Python scripts can call public APIs and web services.
- Package downloads can reach public package repositories.
- The container may also be able to initiate connections to LAN hosts, including other home infrastructure.

**Do not claim that outbound LAN access is blocked.** The `DOCKER-USER` rules described above restrict inbound connections to the published Open Terminal service; they do not restrict connections initiated by the container. UFW's default routed policy must not be assumed to block container egress.

This LAN reachability is an accepted trade-off for a simple unrestricted outbound configuration. If the security policy changes, design and test explicit egress controls rather than assuming existing ingress rules provide them.

### 6.4 CORS

The Open Terminal command includes `--cors-allowed-origins` with an empty value. This was the recorded deployment configuration. Do not broaden CORS without understanding the Open Terminal version's exact option semantics and the Open WebUI integration requirements.

## 7. Python and system package installation

### 7.1 Dynamic Python dependencies — supported workflow

The slim image does not include global `pip`, but Python's `venv` module works and bootstraps pip into each virtual environment. This was tested successfully:

```bash
python -m venv /workspace/.venv-test
/workspace/.venv-test/bin/python -m pip --version
```

The result was pip 25.0.1 under Python 3.12.

Use a separate virtual environment for each project:

```bash
cd /workspace/my-project
python -m venv .venv
.venv/bin/python -m pip install requests beautifulsoup4
.venv/bin/python script.py
```

Or activate it in an interactive shell:

```bash
source .venv/bin/activate
python -m pip install requests
python script.py
```

The workspace is a persistent bind mount, so virtual environments and downloaded packages survive container recreation as long as the host workspace is preserved.

Recommended project hygiene:
- Keep `.venv` inside the project workspace when persistence is desired.
- Record dependencies in `requirements.txt` or `pyproject.toml`.
- Prefer `python -m pip` over relying on a global `pip` executable.
- Do not install packages globally as root.
- Do not reuse one virtual environment across unrelated projects.
- Recreate a virtual environment if the Python interpreter version or architecture changes.

Example reproducible requirements workflow:

```bash
.venv/bin/python -m pip freeze > requirements.txt
.venv/bin/python -m pip install -r requirements.txt
```

### 7.2 OS packages

The image has `apt` and `apt-get`, but the application runs as an unprivileged user and should not be granted root access merely to install system packages dynamically.

For a required OS package:
1. Identify the package and why it is needed.
2. Add it to a reviewed custom image build, or ask the host administrator to rebuild/update the image.
3. Do not run privileged package-management commands from an AI-controlled shell.
4. Keep the base image pinned or otherwise update it deliberately, and rebuild/test when updating.

The full upstream Open Terminal image has package-installation environment variables, but it is much larger and is not appropriate for the Pi's constrained memory/storage. The current deployment uses the slim image.

## 8. Open WebUI connection

Open WebUI on ARISTON connects to AESOP with:

| Setting | Value |
|---|---|
| Name | `AESOP` |
| URL | `http://192.168.1.199:8000` |
| Authentication | Bearer API key stored in `/home/open-terminal/api-key` |
| Chat uploads | Default |
| Working directory context | On |
| User shell tools | Automatic |
| Forward cookies | Off |

The API key must match the contents of AESOP's key file. Do not include the key in prompts, source control, or documentation.

The connection was tested successfully. Open Terminal logs showed WebSocket connections from ARISTON and successful `GET /git/status` responses.

## 9. Operations and troubleshooting

### 9.1 Common commands

```bash
# Container status
sudo docker compose -f /home/open-terminal/deployment/compose.yml ps

# Follow logs
sudo docker compose -f /home/open-terminal/deployment/compose.yml logs -f --tail=100

# Restart
sudo docker compose -f /home/open-terminal/deployment/compose.yml restart

# Recreate after Compose changes
sudo docker compose -f /home/open-terminal/deployment/compose.yml up -d

# Validate Compose
sudo docker compose -f /home/open-terminal/deployment/compose.yml config -q

# Shell inside container (administrative inspection)
sudo docker exec -it open-terminal sh

# Container resource usage
sudo docker stats open-terminal

# Disk usage
df -h
sudo du -sh /home/open-terminal/workspace
```

Use `vim` for terminal editing. Do not use `nano`.

### 9.2 Test API connectivity from Open WebUI

From the Open WebUI terminal connected to AESOP:

```bash
hostname
pwd
id
python -c "import urllib.request; print(urllib.request.urlopen('https://example.com', timeout=10).status)"
```

Expected:
- Working directory `/workspace`
- Runtime user UID/GID 1000
- HTTPS test returns `200` when external connectivity is healthy

### 9.3 Test package installation

```bash
python -m venv /workspace/.venv-test
/workspace/.venv-test/bin/python -m pip --version
/workspace/.venv-test/bin/python -m pip install requests
```

A successful pip version check confirms venv bootstrapping. A successful install confirms access to the configured package index.

### 9.4 Check container and firewall logs

```bash
sudo docker logs --tail=200 open-terminal
sudo journalctl -u docker.service -n 100 --no-pager
sudo journalctl -u open-terminal-firewall.service -n 100 --no-pager
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
```

### 9.5 Common failure modes

| Symptom | Checks |
|---|---|
| Open WebUI cannot connect | Container status/logs, AESOP IP, published port, API key, `DOCKER-USER`, systemd firewall service |
| HTTPS request fails | DNS, container outbound connectivity, route, remote service availability |
| `python -m pip` says no module | Create a venv and use `.venv/bin/python -m pip` |
| Permission denied in workspace | Check host workspace group/mode and container UID/GID |
| Container exits on startup | Compose validation, logs, secret path/mode, resource pressure |
| Container is OOM-killed | `docker stats`, kernel logs, lower workload or reassess limits |
| Connection blocked from an admin device | This is expected for sources other than ARISTON under the current published-port policy |

## 10. Backups and data lifecycle

The persistent workspace is the primary user data created by the AI on AESOP. Back it up independently of the container image.

- Workspace: `/home/open-terminal/workspace`
- Compose/deployment: `/home/open-terminal/deployment`
- API key: `/home/open-terminal/api-key` (back up securely, or retain a secure recovery/rotation procedure)

Do not back up the API key into an unencrypted or broadly accessible location. Exclude virtual environments from backups if they are easily reproducible and storage is constrained, but preserve source files, lockfiles, and requirements metadata.

Container recreation does not remove the bind-mounted workspace. Removing the host workspace does.

### 10.1 rpi-clone shutdown backup

AESOP uses `rpi-clone` to create a full disk backup before shutdown via a systemd service:

**Service file:** `/etc/systemd/system/rpi-clone-shutdown.service`

```ini
[Unit]
Description=Run rpi-clone before shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/rpi-clone -f sda
TimeoutStartSec=infinity

[Install]
WantedBy=halt.target reboot.target shutdown.target

## 11. Change-management rules for AI agents

AI agents operating on AESOP must follow `/home/open-terminal/AGENTS.md` if present, and the repository's `AGENTS.md` when working in a repository.

Minimum requirements:
1. Inspect before modifying. Do not assume this document is current.
2. Do not expose, print, copy into chat, or commit API keys or other secrets.
3. Do not modify SSH, UFW, Docker firewall rules, systemd units, Docker daemon configuration, or network settings without explicit user authorization.
4. Never mount `/var/run/docker.sock` into Open Terminal.
5. Never add host mounts outside the dedicated workspace without explicit approval.
6. Do not run package managers with elevated privileges from AI-controlled commands.
7. Keep dynamic Python dependencies inside project virtual environments.
8. Preserve resource limits and `no-new-privileges`.
9. Do not change container UID/GID or workspace ownership without understanding the host/container mapping.
10. Do not claim that container egress is restricted to the Internet: LAN egress is currently possible.
11. Do not disable the persistent `DOCKER-USER` firewall service.
12. Do not make destructive changes or delete workspace data without explicit confirmation.
13. Use `vim`/`vi`, not `nano`, for terminal editing.
14. Make one logical change at a time, validate it, and report the exact result.

## 12. Deferred or intentionally accepted items

- Read-only container root filesystem: deferred.
- Domain allowlist / outbound proxy: intentionally removed in favor of ordinary Docker outbound access.
- Explicit container-to-LAN egress blocking: not configured.
- Dynamic privileged `apt` installation: not enabled; use a reviewed image build.
- Full Open Terminal image: not selected because of Pi resource constraints.

## 13. Monthly security review

A monthly reminder was created for the AESOP security review. The review is a human checklist, not an automated scan.

Review:
- OS updates and reboot status.
- Open Terminal image and Compose changes.
- Container UID, effective capabilities, `no-new-privileges`, resource limits.
- No Docker socket or unnecessary host mounts.
- Internet egress still works as intended; explicitly review LAN reachability and whether the accepted policy remains appropriate.
- `DOCKER-USER` rules and persistence service.
- SSH key-only access and UFW policy.
- Container/system logs and disk usage.
- API key exposure/rotation needs.
- Workspace backup status.

## 14. Current-state verification checklist

Run these checks before relying on this document after a period of time:

```bash
# Host and Docker
hostname
cat /etc/os-release
uname -m
docker --version
docker compose version

# Deployment
sudo docker compose -f /home/open-terminal/deployment/compose.yml config -q
sudo docker compose -f /home/open-terminal/deployment/compose.yml ps
sudo docker inspect open-terminal --format '{{.Config.Image}}'

# Host firewall and persistent rule service
sudo ufw status verbose
sudo iptables -S DOCKER-USER
sudo ip6tables -S DOCKER-USER
sudo systemctl is-enabled open-terminal-firewall.service
sudo systemctl status open-terminal-firewall.service --no-pager

# Filesystem permissions (does not reveal secret contents)
sudo stat -c '%A %U:%G %n' \
  /home/open-terminal \
  /home/open-terminal/deployment \
  /home/open-terminal/workspace \
  /home/open-terminal/api-key

# Runtime identity
sudo docker exec open-terminal id
sudo docker exec open-terminal sh -c 'python --version; command -v apt apt-get'
```

Update this document when configuration changes. Record the date, rationale, exact changed files, validation performed, and any security trade-off.
