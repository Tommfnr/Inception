# Developer documentation — Inception

This document is for someone who needs to **build, modify or maintain** the
stack: setting up a working environment from nothing, understanding what the
Makefile actually does, managing containers and volumes, and knowing where the
data lives.

For day-to-day usage (starting the site, accounts, health checks), see
[`USER_DOC.md`](USER_DOC.md). For the architecture and the design rationale, see
[`README.md`](README.md).

---

## 1. Setting up the environment from scratch

### 1.1 Prerequisites

The project must run inside a **virtual machine** (a subject requirement). The
host OS of that VM can be Debian or Alpine.

Inside the VM you need:

| Requirement | Check |
|---|---|
| Docker Engine | `docker --version` |
| The Compose plugin (v2) | `docker compose version` |
| `make` | `make --version` |
| Your user in the `docker` group | `docker ps` works without `sudo` |
| `openssl` | used by the Makefile to generate secrets |

Installing Docker on Debian, then granting your user access:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

⚠️ Log out and back in (or `reboot`) — a group change only applies to new
sessions.

### 1.2 Resolving the domain

The site is served for `tfournie.42.fr`, which is not a public domain. Point it
at the local machine:

```bash
echo "127.0.0.1 tfournie.42.fr" | sudo tee -a /etc/hosts
ping -c1 tfournie.42.fr        # must answer from 127.0.0.1
```

### 1.3 Getting the sources

```bash
git clone <repository-url> inception
cd inception
```

Two things are deliberately **absent** from the clone, because they are
git-ignored: `srcs/.env` and the contents of `secrets/`. You must create the
first; the second is generated for you.

### 1.4 The configuration file

```bash
cp srcs/.env.example srcs/.env
$EDITOR srcs/.env
```

Every variable and who consumes it:

| Variable | Consumed by | Purpose |
|---|---|---|
| `MYSQL_DATABASE` | `mariadb/tools/init.sh`, `wordpress/tools/init.sh` | Name of the database to create, then to connect to |
| `MYSQL_USER` | both `init.sh` | The database account WordPress uses |
| `WP_URL` | `wordpress/tools/init.sh` | Stored by WordPress as `siteurl`/`home`; all generated links are absolute and derive from it |
| `WP_TITLE` | `wordpress/tools/init.sh` | Site title |
| `WP_ADMIN_USER` | `wordpress/tools/init.sh` | Administrator login |
| `WP_ADMIN_EMAIL` | `wordpress/tools/init.sh` | Administrator email |
| `WP_USER` | `wordpress/tools/init.sh` | Second account, role `author` |
| `WP_USER_EMAIL` | `wordpress/tools/init.sh` | Second account email |
| `DOMAIN_NAME` | *nothing* | Declared for documentation only. The domain is hardcoded in `nginx/conf/nginx.conf` (`server_name`) and in the certificate subject of `nginx/Dockerfile`. Changing this variable alone has **no effect**. |

Two constraints that will fail the project if ignored:

- **`WP_ADMIN_USER` must not contain `admin` or `administrator`**, in any
  capitalisation. `admin`, `Admin-123`, `Administrator` are all rejected.
- **No trailing comments on a value line.** Write comments on their own lines.
  A trailing `# note` risks ending up inside the value, silently creating a
  database user named `wpuser       # note`.

### 1.5 Secrets

Four passwords are needed. They are **not** in `.env` and **not** in Git:

| File | Used for |
|---|---|
| `secrets/db_password.txt` | The `MYSQL_USER` database account |
| `secrets/db_root_password.txt` | The MariaDB `root` account |
| `secrets/wp_admin_password.txt` | WordPress administrator |
| `secrets/wp_user_password.txt` | WordPress second user |

You do **not** need to create them. The Makefile's `secrets` target generates
any missing file with `openssl rand -hex 16`, and never overwrites an existing
one:

```makefile
@test -f $(SECRETS)/db_password.txt || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/db_password.txt
```

The `tr -d '\n'` matters: a trailing newline would become part of the password
and the database authentication would fail.

Each is exposed to the containers as a Docker secret, mounted read-only on a
tmpfs at `/run/secrets/<name>`, and read by the entrypoints with
`cat /run/secrets/db_password`. No password is ever passed as an environment
variable, and none appears in a `Dockerfile`.

---

## 2. Building and launching

### 2.1 With the Makefile

```bash
make
```

`make` (i.e. `make all` → `make up`) performs three steps:

```makefile
up: secrets
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	docker compose -f $(COMPOSE) up -d --build
```

1. **`secrets`** — generate any missing password file.
2. **`mkdir -p /home/tfournie/data/{mariadb,wordpress}`** — the volumes bind to
   these paths, and a bind source must exist beforehand. Without this, Docker
   would fail to start the containers.
3. **`docker compose up -d --build`** — build the three images, then start the
   stack detached.

All targets:

| Target | What it does | Destroys data? |
|---|---|---|
| `make` / `make up` | Secrets, data dirs, build, start detached | No |
| `make down` | `docker compose down` — stop and remove the containers | No |
| `make clean` | `down`, then `docker system prune -af` | No |
| `make fclean` | `down -v`, wipe `/home/tfournie/data/*`, prune images | **Yes** |
| `make re` | `fclean` then `up` — full rebuild from zero | **Yes** |

⚠️ `clean` and `fclean` run `docker system prune -af`, which removes **every**
unused image on the machine, not only this project's. That is acceptable inside
a dedicated VM; be careful running it on a shared workstation.

`fclean` deletes the data through a throwaway container:

```makefile
docker run --rm -v $(DATA):/data alpine:3.23 rm -rf /data/mariadb /data/wordpress
```

This is deliberate. The files in those directories belong to UIDs internal to
the containers (`mysql`, `nobody`), so a plain `rm -rf` from your shell would be
denied. Deleting from inside a container running as root works in both rootful
and rootless Docker, without needing `sudo` on the host.

### 2.2 With Docker Compose directly

The Makefile is a thin wrapper. The equivalent raw commands:

```bash
docker compose -f srcs/docker-compose.yml build           # build only
docker compose -f srcs/docker-compose.yml up -d           # start detached
docker compose -f srcs/docker-compose.yml up              # start in foreground, logs on screen
docker compose -f srcs/docker-compose.yml down            # stop, keep volumes
docker compose -f srcs/docker-compose.yml down -v         # stop and delete volumes
docker compose -f srcs/docker-compose.yml config          # resolved config, with .env substituted
```

`config` is the fastest way to debug a variable that is not being picked up: it
prints the file as Compose actually understands it.

### 2.3 What gets built

Three images, each named after its service as the subject requires
(`image: nginx`, `image: wordpress`, `image: mariadb`), all built from
`alpine:3.23` — the penultimate stable Alpine release.

| Service | Build steps | Entrypoint (PID 1) |
|---|---|---|
| **mariadb** | `apk add mariadb mariadb-client`, create `/var/lib/mysql` and `/run/mysqld`, copy `my.cnf` | `init.sh` → `exec mysqld --user=mysql` |
| **wordpress** | `apk add php83 + extensions`, raise `memory_limit` to 512M, download `wp-cli.phar`, copy `www.conf` | `init.sh` → `exec php-fpm83 -F` |
| **nginx** | `apk add nginx openssl`, generate a self-signed certificate valid 365 days, copy `nginx.conf` | `nginx -g "daemon off;"` |

Every service ends with `exec`, so the daemon **replaces** the shell and becomes
PID 1. It therefore receives `SIGTERM` directly and shuts down cleanly on
`docker stop`. There is no `tail -f`, no `sleep infinity`, no `while true`.

The `memory_limit = 512M` override is not cosmetic: the PHP default of 128M is
not enough for wp-cli to extract the WordPress archive, and the install fails
without it.

### 2.4 Startup order

`depends_on` guarantees start *order*, not *readiness* — MariaDB accepts
connections several seconds after its container starts. The WordPress entrypoint
therefore polls explicitly:

```sh
until nc -z mariadb 3306; do ... done      # 30 attempts, 2s apart, then exit 1
```

Failing loudly after 60 seconds is better than letting `wp core install` fail
halfway and leave a half-written `wp-config.php` in the volume.

---

## 3. Managing containers

```bash
docker ps                                   # running containers
docker compose -f srcs/docker-compose.yml ps
docker logs -f nginx                        # follow one service's logs
docker logs --tail 50 wordpress
docker compose -f srcs/docker-compose.yml logs -f     # all services, interleaved
```

Getting a shell inside a container (they are Alpine, so `sh`, not `bash`):

```bash
docker exec -it nginx     sh
docker exec -it wordpress sh
docker exec -it mariadb   sh
```

Useful one-liners:

```bash
docker exec nginx nginx -t                            # validate the NGINX config
docker exec -it wordpress wp option get siteurl --allow-root
docker exec -it wordpress wp user list --allow-root
docker exec -it mariadb mariadb -u root -p -e "SHOW DATABASES;"
docker inspect -f '{{.State.Status}} {{.RestartCount}}' wordpress
```

Restarting a single service after a code change:

```bash
docker compose -f srcs/docker-compose.yml up -d --build nginx
```

⚠️ **Configuration files are copied into the images at build time** (`COPY
conf/nginx.conf /etc/nginx/nginx.conf`), not mounted. A `docker compose restart`
therefore reuses the **old** configuration. Any change under
`srcs/requirements/*/conf/` or `tools/` requires a rebuild — `--build`, or
`make re`.

### Inspecting the network

```bash
docker network ls
docker network inspect srcs_inception
docker exec wordpress getent hosts mariadb    # service-name DNS resolution
```

The `srcs_` prefix is the Compose **project name**, derived from the directory
containing `docker-compose.yml`. The containers themselves keep plain names
(`nginx`, `wordpress`, `mariadb`) because `container_name` is set explicitly.

---

## 4. Managing volumes and data

### 4.1 The two volumes

| Volume | Mounted in | At | Contains |
|---|---|---|---|
| `db_data` | `mariadb` | `/var/lib/mysql` | The MariaDB data files: all site content, accounts, settings |
| `wp_files` | `wordpress` **and** `nginx` | `/var/www/html` | The WordPress installation: core, themes, plugins, uploads, `wp-config.php` |

`wp_files` is mounted twice on purpose. NGINX does not execute PHP — it sends a
*path* over FastCGI (`SCRIPT_FILENAME $document_root$fastcgi_script_name`) and
php-fpm opens that path itself. Both containers must therefore see the same
files at the same location. NGINX additionally serves the static assets (CSS,
JS, images) straight from this volume, without involving PHP.

### 4.2 Where the data physically lives

Both volumes are declared as named volumes whose `local` driver is pointed at a
fixed host directory:

```yaml
volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tfournie/data/mariadb
```

So the bytes are here, inside the VM:

```
/home/tfournie/data/
├── mariadb/       <- db_data
└── wordpress/     <- wp_files
```

Inspect them:

```bash
docker volume ls
docker volume inspect srcs_db_data          # see Options and Mountpoint
sudo ls -la /home/tfournie/data/wordpress   # sudo: files belong to container UIDs
```

### 4.3 How persistence actually works

Persistence is not only the volume — it is the volume **plus** an idempotency
guard in each entrypoint. Both scripts run their one-time setup only if the
volume is empty:

```sh
# mariadb/tools/init.sh
if [ ! -d /var/lib/mysql/mysql ]; then    # the system database
    mariadb-install-db ...                # bootstrap, create DB and users
fi
exec mysqld --user=mysql

# wordpress/tools/init.sh
if [ ! -f wp-config.php ]; then           # marker of a completed install
    wp core download; wp config create; wp core install; wp user create
fi
exec php-fpm83 -F
```

On a restart the marker exists, the block is skipped, and the daemon starts on
the existing data. **Your content is never reinitialised by `make down && make`.**

One consequence worth remembering: values consumed only inside those guards are
read **once ever**. Changing `WP_TITLE`, `WP_ADMIN_USER` or `MYSQL_USER` in
`.env` after the first install has no effect, because the block never runs
again. To apply such a change you must either edit it through WordPress / SQL,
or wipe the volumes with `make fclean`.

### 4.4 Deleting the data

```bash
make fclean                                          # everything, via the Makefile
docker compose -f srcs/docker-compose.yml down -v    # containers + volumes only
```

Note that `down -v` removes the Docker volume *declarations*, but since the data
sits in a bind-mounted directory the files under `/home/tfournie/data/` remain.
That is exactly why `fclean` follows up with the throwaway-container `rm -rf`.

### 4.5 Backing up

```bash
docker exec mariadb mariadb-dump -u root -p"$(cat secrets/db_root_password.txt)" \
  --all-databases > backup.sql

sudo tar czf wp_files.tar.gz -C /home/tfournie/data wordpress
```

---

## 5. Modifying the project

### Changing a service configuration

Edit the file under `srcs/requirements/<service>/conf/`, then rebuild — a
restart is not enough, since configs are baked into the image:

```bash
docker compose -f srcs/docker-compose.yml up -d --build <service>
```

### Changing a port

A port always exists in **two** places: where the server listens, and where the
client connects. Change both, or the stack breaks.

| Port | Server side | Client side |
|---|---|---|
| `443` | `nginx.conf` → `listen 443 ssl` | `docker-compose.yml` → `ports: "443:443"` (host side) |
| `9000` | `wordpress/conf/www.conf` → `listen = 9000` | `nginx.conf` → `fastcgi_pass wordpress:9000` |
| `3306` | `mariadb/conf/my.cnf` → `port=3306` | `wordpress/tools/init.sh` → `--dbhost="mariadb:3306"` **and** `nc -z mariadb 3306` |

`EXPOSE` in a Dockerfile is documentation only — it publishes nothing.

Note that `--dbhost` is written into `wp-config.php` at first install only.
Changing the MariaDB port afterwards also requires either `make fclean`, or:

```bash
docker exec -it wordpress wp config set DB_HOST mariadb:3307 --allow-root
```

### Adding a service

1. Create `srcs/requirements/<name>/` with a `Dockerfile`, and `conf/` or
   `tools/` as needed.
2. Add the service to `docker-compose.yml`: `build`, `image: <name>` (the image
   must be named after the service), `container_name`, `restart: always`,
   `networks: [inception]`, and a volume if it needs one.
3. Publish a port only if the service genuinely must be reachable from outside.
   Everything internal stays on the private network.
4. Rebuild: `make re`.

---

## 6. Debugging checklist

| Symptom | Where to look |
|---|---|
| `502 Bad Gateway` | php-fpm is unreachable. Check `fastcgi_pass` against `listen` in `www.conf`, then `docker logs wordpress` |
| `Error establishing a database connection` | `docker logs mariadb`; check `MYSQL_USER` and that `secrets/db_password.txt` has no trailing newline |
| `File not found` from NGINX | The `wp_files` volume is missing from the `nginx` service, or `root` does not match the WordPress path |
| WordPress container exits after 60s | MariaDB never became ready — read `docker logs mariadb` |
| A config change has no effect | You restarted instead of rebuilding. Use `--build` |
| An `.env` change has no effect | It is consumed inside a one-time install guard. See §4.3 |
| Broken CSS, redirect loops | `WP_URL` does not match the address actually used in the browser |

Reading the effective configuration, with variables substituted:

```bash
docker compose -f srcs/docker-compose.yml config
```
