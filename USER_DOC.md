# User documentation — Inception

This document is for someone who wants to **run and use** the stack: start it,
stop it, reach the website, manage its accounts, and confirm everything is
healthy. No knowledge of the internals is required.

For the developer-side documentation (building from scratch, managing volumes),
see [`DEV_DOC.md`](DEV_DOC.md).

---

## 1. What this stack provides

Inception runs a **WordPress website served over HTTPS**, built from three
independent services. Each one runs in its own container and has a single
responsibility:

| Service | What it does for you |
|---|---|
| **nginx** | Receives every request from your browser, handles the HTTPS encryption, serves images and stylesheets directly, and forwards anything dynamic to WordPress. It is the only door into the infrastructure. |
| **wordpress** | Runs the WordPress application itself (PHP). It builds each page on demand. It is not reachable from outside. |
| **mariadb** | Stores all the site content — articles, pages, comments, accounts, settings. It is not reachable from outside. |

Everything you type into the site is stored in MariaDB; every uploaded file and
theme lives on a shared storage area. Both survive a restart of the stack.

The website is available at **https://tfournie.42.fr**.

---

## 2. Starting and stopping the project

All commands are run from the root of the project, inside the virtual machine.

### Start

```bash
make
```

This builds the images if needed and starts the three containers in the
background. The **first** run takes a few minutes: the images are compiled, then
WordPress is downloaded and installed. Later starts take only a few seconds.

### Stop

```bash
make down
```

This stops and removes the containers **but keeps all your data**. Your articles,
accounts and settings are still there when you run `make` again.

### Restart

```bash
make down && make
```

### Reset everything

```bash
make fclean
```

⚠️ **This erases the site permanently** — database, uploaded files, accounts.
Use it only to start over from a blank installation.

---

## 3. Reaching the website

Before the domain works, it must point to the local machine. This is done once:

```bash
echo "127.0.0.1 tfournie.42.fr" | sudo tee -a /etc/hosts
```

Then open in a browser:

| What | Address |
|---|---|
| The website | **https://tfournie.42.fr** |
| The administration panel | **https://tfournie.42.fr/wp-admin** |

### About the security warning

On the first visit your browser will display a warning such as *"Warning:
Potential Security Risk Ahead"* or *"Your connection is not private"*.

**This is expected and is not a malfunction.** The site uses a certificate it
generated and signed itself, because `tfournie.42.fr` is a local domain that no
public certificate authority can vouch for. The connection *is* encrypted — the
browser simply cannot verify who is on the other end.

Click *Advanced*, then *Accept the risk and continue*.

---

## 4. Accounts and passwords

The stack is created with **two WordPress accounts**, as required:

| Role | Where the username is defined | Where the password is stored |
|---|---|---|
| Administrator | `WP_ADMIN_USER` in `srcs/.env` | `secrets/wp_admin_password.txt` |
| Author | `WP_USER` in `srcs/.env` | `secrets/wp_user_password.txt` |

Two more passwords exist for the database and are never needed for normal use:
`secrets/db_password.txt` (the WordPress database account) and
`secrets/db_root_password.txt` (the MariaDB superuser).

### Reading a password

```bash
cat secrets/wp_admin_password.txt
```

### Where they come from

The password files are **generated automatically** the first time you run `make`,
with `openssl rand -hex 16`. They are random, different on every installation,
and they are **never committed to Git** — both `secrets/` and `srcs/.env` are
listed in `.gitignore`.

### Changing a password

Change it from the WordPress interface (*Users → Profile → New password*). Do
**not** edit the file in `secrets/` afterwards: it is only read once, when the
site is first installed, so editing it later has no effect and would only make
the file misleading.

---

## 5. Checking that everything works

### Are the three containers running?

```bash
docker ps
```

The three services must appear with the status `Up`. A container in `Restarting`
is crash-looping — see *Troubleshooting* below.

### Does the site answer?

```bash
curl -k https://tfournie.42.fr
```

You should get HTML. The `-k` flag tells `curl` to accept the self-signed
certificate, exactly as you do in the browser.

### Is only TLS 1.2 / 1.3 accepted?

```bash
curl -k --tlsv1.2 --tls-max 1.2 https://tfournie.42.fr -o /dev/null -s -w "TLS1.2 -> %{http_code}\n"
curl -k --tlsv1.3            https://tfournie.42.fr -o /dev/null -s -w "TLS1.3 -> %{http_code}\n"
curl -k --tlsv1.1 --tls-max 1.1 https://tfournie.42.fr    # must fail
```

The first two must return `200`. The third **must fail** — older, insecure
protocol versions are deliberately refused.

### Is the content really in the database?

```bash
docker exec -it wordpress wp post list --allow-root
```

### Does the data survive a restart?

```bash
make down && make
```

Reload the site: your content is still there. This is what the two persistent
volumes are for.

---

## 6. Troubleshooting

**The browser says the site is unreachable.**
Check that the containers are up (`docker compose -f srcs/docker-compose.yml ps`)
and that the line `127.0.0.1 tfournie.42.fr` is present in `/etc/hosts`.

**The page shows `502 Bad Gateway`.**
NGINX is running but cannot reach WordPress. Look at the logs:

```bash
docker logs wordpress
```

**The page shows `Error establishing a database connection`.**
WordPress is running but MariaDB is not answering:

```bash
docker logs mariadb
```

**A container keeps restarting.**
Read its logs to see why it exits:

```bash
docker logs --tail 50 nginx
docker logs --tail 50 wordpress
docker logs --tail 50 mariadb
```

**Nothing helps.**
Rebuild from scratch — but remember this **erases the site content**:

```bash
make re
```
