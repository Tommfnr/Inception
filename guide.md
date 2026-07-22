# Guide complet — Inception (42)

> **Note perso, pas un livrable.** Ce fichier t'accompagne pendant tout le projet :
> il explique les **notions** puis te **guide étape par étape**.
> À supprimer (ou garder gitignore) avant l'éval, comme `SETUP_VM.md`.
>
> Convention : `login = tfournie`, `domaine = tfournie.42.fr`. Remplace partout si besoin.

---

## Table des matières
1. [C'est quoi Inception ?](#1-cest-quoi-inception-)
2. [Les notions Docker à comprendre](#2-les-notions-docker-à-comprendre)
3. [Les règles du sujet (obligations + interdits)](#3-les-règles-du-sujet)
4. [L'architecture cible](#4-larchitecture-cible)
5. [Étape 1 — Le squelette](#étape-1--le-squelette)
6. [Étape 2 — `.env` + `secrets/`](#étape-2--env--secrets)
7. [Étape 3 — MariaDB](#étape-3--mariadb-la-base-de-la-stack)
8. [Étape 4 — WordPress + php-fpm](#étape-4--wordpress--php-fpm)
9. [Étape 5 — NGINX + TLS](#étape-5--nginx--tls)
10. [Étape 6 — docker-compose.yml (assemblage)](#étape-6--docker-composeyml-lassemblage)
11. [Étape 7 — Le Makefile](#étape-7--le-makefile)
12. [Tester & débugger](#tester--débugger)
13. [Préparation à l'éval](#préparation-à-léval)
14. [Checklist finale](#checklist-finale)

---

## 1. C'est quoi Inception ?

Tu dois monter une **petite infrastructure web** entièrement avec **Docker**, où chaque
brique tourne dans **son propre conteneur** que **tu construis toi-même** :

- **NGINX** — le serveur web, seule porte d'entrée (HTTPS/443 uniquement).
- **WordPress + php-fpm** — le site (CMS) et le moteur qui exécute le PHP.
- **MariaDB** — la base de données du site.

Le tout est orchestré par **docker-compose** et lancé par un **Makefile**.
L'objectif pédagogique : comprendre la **conteneurisation** (isolation, images,
volumes, réseau) et écrire des images **from scratch**, pas juste `docker pull`.

---

## 2. Les notions Docker à comprendre

### Image vs Conteneur
- **Image** = un modèle figé, en lecture seule (le « moule »). Construite à partir
  d'un **Dockerfile**. Ex : ton image `mariadb`.
- **Conteneur** = une **instance** qui tourne à partir d'une image (le « gâteau »).
  Tu peux lancer 1 image → N conteneurs. Un conteneur est **éphémère** : si tu le
  détruis, tout ce qui n'est pas dans un **volume** est perdu.

Analogie : l'image est une **classe**, le conteneur est un **objet** (instance).

### Le Dockerfile
Recette pour construire une image. Les instructions clés :
| Instruction | Rôle |
|---|---|
| `FROM alpine:3.20` | Image de base (ici Alpine, avant-dernière stable). **Jamais `latest`.** |
| `RUN` | Exécute une commande **au build** (installer des paquets…). |
| `COPY` | Copie un fichier du repo vers l'image. |
| `EXPOSE` | Documente le port utilisé (informatif). |
| `ENTRYPOINT` / `CMD` | La commande lancée **au démarrage du conteneur** (le processus PID 1). |

### Les layers (couches)
Chaque `RUN`/`COPY` crée une **couche** empilée et **mise en cache**. Si tu changes
une ligne, Docker rebuild à partir de cette ligne. D'où l'intérêt de grouper les
`RUN` (`apk add ... && ...`) pour une image plus légère.

### PID 1 & foreground — **LE concept central du sujet**
Un conteneur vit **tant que son processus principal (PID 1) tourne**. Dès que ce
processus s'arrête, le conteneur meurt. Donc :
- Le service (`nginx`, `php-fpm`, `mysqld`) doit tourner **au premier plan
  (foreground)**, PAS en démon/background.
- ❌ **Interdit** de « fausser » la vie du conteneur avec `tail -f /dev/null`,
  `sleep infinity`, `while true`, `bash` qui ne fait rien. C'est un **échec** direct.
- ✅ On lance le vrai service en foreground. Exemples :
  - NGINX → `nginx -g "daemon off;"`
  - php-fpm → `php-fpm8 -F` (ou `--nodaemonize`)
  - MariaDB → `mysqld` (ou `mysqld_safe`) au premier plan.

### Volumes
Un **volume** = un dossier persistant, géré par Docker, **hors** du cycle de vie du
conteneur. On l'utilise pour ce qui doit survivre : la **base MariaDB** et les
**fichiers WordPress**. Le sujet impose de les stocker dans `/home/tfournie/data`.
- Sans volume → tu perds la DB à chaque `docker compose down`.
- On déclare des **volumes nommés** dans le compose (voir étape 6).

### Réseau (network)
Les conteneurs se parlent via un **réseau Docker** privé. Un conteneur en joint un
autre **par son nom de service** (ex : WordPress se connecte à l'hôte `mariadb`,
pas à une IP). Le sujet **impose** de déclarer un `networks:` dans le compose.
- ❌ **Interdits** : `network: host`, `--link`, `links:`.

### docker-compose
Un fichier YAML (`docker-compose.yml`) qui décrit **tous** les services, leurs
images/Dockerfiles, volumes, réseau, variables d'env, dépendances, politique de
redémarrage. Une commande (`docker compose up`) monte toute l'infra.

### Variables d'env & secrets
- **`.env`** (dans `srcs/`) : config **non sensible** (nom de domaine, nom de la DB,
  nom d'utilisateur…). Injectée dans le compose via `${VARIABLE}`.
- **Docker secrets** (`secrets/`) : les **mots de passe**. Montés en lecture seule
  dans le conteneur sous `/run/secrets/<nom>`. **Jamais** de mot de passe en dur
  dans un Dockerfile ou committé dans git → échec immédiat si trouvé.

---

## 3. Les règles du sujet

### ✅ Obligations
- Un **Makefile** à la racine qui monte toute l'appli via docker-compose.
- **1 Dockerfile par service**, écrit par toi, appelé par le compose.
- Images basées sur l'**avant-dernière stable** d'Alpine **ou** Debian.
- Chaque image **nommée d'après son service** (`nginx`, `wordpress`, `mariadb`).
- **NGINX** : seul point d'entrée, **port 443 uniquement**, **TLS 1.2 / 1.3 only**.
- **WordPress + php-fpm** (sans nginx), **MariaDB** (sans nginx).
- **2 volumes** : la base de données + les fichiers du site, dans `/home/tfournie/data`.
- Un **réseau** `networks:` déclaré dans le compose.
- Conteneurs qui **redémarrent en cas de crash** (`restart: always`/`unless-stopped`).
- **WordPress** : **2 utilisateurs** en base, dont **1 admin**.
- Domaine **`tfournie.42.fr`** → pointe vers l'IP locale (via `/etc/hosts`).

### ❌ Interdits (= échec)
- Le tag **`latest`**.
- Mots de passe **en clair** dans les fichiers / committés dans git.
- **Hacks** pour garder un conteneur en vie : `tail -f`, `sleep infinity`,
  `while true`, `bash` infini…
- `network: host`, `--link`, `links:`.
- Le nom d'admin WordPress ne doit **pas** contenir `admin` / `Admin` /
  `administrator` / `Administrator` (ex : utilise `bossman`, `wpboss`…).
- Mettre les services dans un seul conteneur.

---

## 4. L'architecture cible

```
                Navigateur (https://tfournie.42.fr)
                              │  443 (TLS 1.2/1.3)
                              ▼
                   ┌────────────────────┐
                   │      NGINX         │   seul port exposé : 443
                   │  (reverse proxy)   │
                   └─────────┬──────────┘
                             │ fastcgi 9000
                             ▼
                   ┌────────────────────┐        ┌───────────────────┐
                   │  WordPress+php-fpm │ ─────▶  │     MariaDB       │
                   │      (9000)        │  3306   │      (3306)       │
                   └─────────┬──────────┘        └─────────┬─────────┘
                             │                             │
                    volume: wp_files                volume: db_data
                  /home/tfournie/data/wordpress   /home/tfournie/data/mariadb

   Réseau docker privé "inception"  ── les 3 conteneurs y sont connectés
```

**Ordre de construction (bas → haut)** : MariaDB → WordPress → NGINX.
On teste chaque service avant de passer au suivant.

---

## Étape 1 — Le squelette

> ⚠️ **NOMMAGE EXACT — un seul caractère faux = refus à l'éval.**
> - Le dossier est **`srcs`** (avec un **s**), **pas** `src`.
> - Le fichier est **`docker-compose.yml`**, **pas** `dockers-compose.yml`.
> - Les images/services : `mariadb`, `wordpress`, `nginx` (au singulier, minuscules).
> - Chaque service a **`Dockerfile`** (D majuscule), `conf/` et `tools/`.

Arborescence **imposée** :

```bash
mkdir -p srcs/requirements/mariadb/{conf,tools}
mkdir -p srcs/requirements/wordpress/{conf,tools}
mkdir -p srcs/requirements/nginx/{conf,tools}
mkdir -p secrets
touch Makefile srcs/docker-compose.yml
touch srcs/requirements/{mariadb,wordpress,nginx}/Dockerfile
```

Résultat attendu :
```
Makefile
secrets/
srcs/
├── .env
├── docker-compose.yml
└── requirements/
    ├── mariadb/    { Dockerfile, conf/, tools/ }
    ├── wordpress/  { Dockerfile, conf/, tools/ }
    └── nginx/      { Dockerfile, conf/, tools/ }
```

- `conf/` = fichiers de config copiés dans l'image.
- `tools/` = scripts d'init lancés au démarrage.

---

## Étape 2 — `.env` + `secrets/`

### Le `.env` (dans `srcs/.env`)
Copie ton `.env.example` et remplis-le. **Aucun mot de passe ici.**
```bash
# srcs/.env
DOMAIN_NAME=tfournie.42.fr

# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=tfournie

# WordPress admin (nom SANS "admin")
WP_ADMIN_USER=bossman
WP_ADMIN_EMAIL=bossman@tfournie.42.fr

# WordPress 2e utilisateur (obligatoire)
WP_USER=alice
WP_USER_EMAIL=alice@tfournie.42.fr

# Site
WP_TITLE=Inception
WP_URL=https://tfournie.42.fr
```

### Les secrets (dans `secrets/`)
Un fichier = un mot de passe, **une seule ligne, sans retour à la ligne final** :
```bash
printf 'un_mdp_solide'        > secrets/db_password.txt
printf 'un_mdp_root_solide'   > secrets/db_root_password.txt
printf 'un_mdp_admin_wp'      > secrets/wp_admin_password.txt
printf 'un_mdp_user_wp'       > secrets/wp_user_password.txt
```
> ⚠️ Vérifie qu'ils sont bien ignorés par git : `git status` ne doit **jamais**
> montrer `secrets/` ni `.env`. (Ton `.gitignore` les couvre déjà.)

**Comment un secret est lu dans le conteneur ?** Docker le monte dans
`/run/secrets/db_password`. Dans un script on fait :
`cat /run/secrets/db_password`. Beaucoup d'images officielles acceptent aussi la
variable `MYSQL_PASSWORD_FILE=/run/secrets/db_password`.

---

## Étape 3 — MariaDB (la base de la stack)

**But :** un conteneur qui, au premier lancement, crée la base `wordpress`, un
utilisateur, ses droits, puis lance `mysqld` en **foreground**.

### `srcs/requirements/mariadb/Dockerfile`
```dockerfile
FROM alpine:3.20

# Paquets : le serveur MariaDB + le client
RUN apk update && apk add --no-cache mariadb mariadb-client

# Dossiers attendus par mariadb
RUN mkdir -p /var/lib/mysql /run/mysqld \
    && chown -R mysql:mysql /var/lib/mysql /run/mysqld

# Config perso + script d'init
COPY conf/my.cnf   /etc/my.cnf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 3306
ENTRYPOINT ["init.sh"]
```
**Explication ligne par ligne :**
- `FROM alpine:3.20` → base légère, version figée (pas `latest`).
- `apk add --no-cache` → installe sans garder le cache = image plus petite.
- On crée `/run/mysqld` (socket) et on donne les droits à l'utilisateur `mysql`.
- On copie **notre** config et **notre** script d'init.
- `ENTRYPOINT` → le script s'occupe de l'init **puis** lance `mysqld` en foreground.

### `srcs/requirements/mariadb/conf/my.cnf`
```ini
[mysqld]
skip-networking=0
skip-name-resolve
bind-address=0.0.0.0
port=3306
datadir=/var/lib/mysql
socket=/run/mysqld/mysqld.sock
```
**Ligne par ligne :**
| Ligne | Signification |
|---|---|
| `[mysqld]` | En-tête de section : tout ce qui suit configure le **serveur** `mysqld`. |
| `skip-networking=0` | **Active le réseau TCP/IP.** À `1` la DB ne serait joignable que localement → WordPress (autre conteneur) ne pourrait pas se connecter. |
| `skip-name-resolve` | Pas de résolution DNS inverse des clients → connexions plus rapides, pas de blocage DNS. Les droits se définissent par IP/`%` (déjà le cas). |
| `bind-address=0.0.0.0` | Écoute sur **toutes** les interfaces → joignable via le réseau docker. `127.0.0.1` donnerait `Connection refused` côté WordPress. |
| `port=3306` | Port d'écoute standard MariaDB. Visé par WordPress avec `--dbhost=mariadb:3306`. |
| `datadir=/var/lib/mysql` | Répertoire physique des données (bases) → **branché sur le volume** pour la persistance. |
| `socket=/run/mysqld/mysqld.sock` | Socket Unix pour les connexions **locales** dans le conteneur (script d'init). Dossier créé/`chown` dans le Dockerfile. |
> **Le trio clé** `skip-networking=0` + `bind-address=0.0.0.0` + `port=3306` rend
> MariaDB **joignable par WordPress**. `datadir`/`socket` disent **où** sont les
> données et **par où** passent les connexions locales.

### `srcs/requirements/mariadb/tools/init.sh`
```sh
#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
DB_ROOT=$(cat /run/secrets/db_root_password)

# Init seulement au 1er lancement (si la base système n'existe pas encore)
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql

    # Fichier SQL d'initialisation
    cat > /tmp/init.sql <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT}';
FLUSH PRIVILEGES;
EOF

    # On lance mysqld le temps d'appliquer le SQL, puis on l'arrête
    mysqld --user=mysql --bootstrap < /tmp/init.sql
    rm -f /tmp/init.sql
fi

# Lancement DÉFINITIF en foreground → devient PID 1
exec mysqld --user=mysql
```
**Idées clés :**
- Le bloc `if [ ! -d ... ]` → l'init ne se fait **qu'une fois** (grâce au volume,
  au 2e démarrage la base existe déjà).
- `--bootstrap` applique le SQL sans ouvrir de réseau (mode init).
- `exec mysqld` remplace le shell → **mysqld devient PID 1**, foreground. ✅ Pas de hack.

### Tester MariaDB seul
On testera après avoir écrit le compose (étape 6). Objectif :
```bash
docker compose up mariadb
docker exec -it mariadb mariadb -u tfournie -p wordpress   # doit se connecter
```

---

## Étape 4 — WordPress + php-fpm

**But :** installer WordPress, le configurer pour parler à MariaDB, créer les
2 utilisateurs via **wp-cli**, puis lancer **php-fpm en foreground**.

### `srcs/requirements/wordpress/Dockerfile`
```dockerfile
FROM alpine:3.20

# PHP + extensions nécessaires à WordPress + fpm
RUN apk update && apk add --no-cache \
    php82 php82-fpm php82-mysqli php82-phar php82-json \
    php82-curl php82-dom php82-mbstring php82-gd php82-xml \
    curl bash

# wp-cli : l'outil en ligne de commande pour installer/configurer WordPress
RUN curl -o /usr/local/bin/wp \
      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Config php-fpm : écouter sur 9000 (réseau), pas sur un socket local
COPY conf/www.conf /etc/php82/php-fpm.d/www.conf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

RUN mkdir -p /var/www/html
WORKDIR /var/www/html

EXPOSE 9000
ENTRYPOINT ["init.sh"]
```

### `srcs/requirements/wordpress/conf/www.conf` (extrait clé)
```ini
[www]
user = nobody
group = nobody
listen = 9000
listen.owner = nobody
listen.group = nobody
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```
**Ligne par ligne :**
| Ligne | Signification |
|---|---|
| `[www]` | Nom du **pool** php-fpm (un pool = un groupe de processus PHP). Ici un seul pool nommé `www`. |
| `user = nobody` / `group = nobody` | **Sous quelle identité** tournent les processus PHP. `nobody` = utilisateur non privilégié → sécurité (le PHP ne tourne pas en root). |
| `listen = 9000` | php-fpm écoute sur le **port TCP 9000** (et non un socket unix local). **Essentiel** : NGINX, dans un autre conteneur, l'atteint via `wordpress:9000`. |
| `listen.owner = nobody` / `listen.group = nobody` | Propriétaire du point d'écoute → cohérent avec `user/group`, évite les soucis de permissions. |
| `pm = dynamic` | **Process manager dynamique** : php-fpm ajuste le nombre de processus enfants selon la charge (entre les bornes ci-dessous). |
| `pm.max_children = 5` | Nombre **max** de processus PHP simultanés (plafond). |
| `pm.start_servers = 2` | Nombre de processus **au démarrage**. |
| `pm.min_spare_servers = 1` | Minimum de processus **en attente** (prêts à servir). |
| `pm.max_spare_servers = 3` | Maximum de processus en attente (au-delà, php-fpm en tue). |
> **Ce qui compte pour le sujet** : `listen = 9000` (TCP, pas socket) → c'est ce qui
> permet à NGINX (autre conteneur) de joindre php-fpm. Les `pm.*` sont du réglage de
> perf, tu peux garder ces valeurs.

### `srcs/requirements/wordpress/tools/init.sh`
```sh
#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
WP_ADMIN_PASS=$(cat /run/secrets/wp_admin_password)
WP_USER_PASS=$(cat /run/secrets/wp_user_password)

cd /var/www/html

# Attendre que MariaDB accepte les connexions
until mysqladmin ping -h mariadb --silent 2>/dev/null; do
    echo "En attente de MariaDB..."; sleep 2
done

if [ ! -f wp-config.php ]; then
    wp core download --allow-root

    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost="mariadb:3306"

    wp core install --allow-root \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}"

    # 2e utilisateur obligatoire
    wp user create --allow-root \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author --user_pass="${WP_USER_PASS}"
fi

# php-fpm en foreground → PID 1
exec php-fpm82 -F
```
**Idées clés :**
- La boucle `until mysqladmin ping` = une **vraie** attente de dépendance
  (autorisée), pas un `while true` bidon.
- `wp core install` crée l'admin (nom **sans** « admin »), puis on crée le 2e user.
- `exec php-fpm82 -F` → foreground, PID 1. ✅

---

## Étape 5 — NGINX + TLS

**But :** point d'entrée unique, **443 uniquement**, TLS 1.2/1.3, qui transmet le
PHP à `wordpress:9000` (FastCGI).

### Générer le certificat TLS (auto-signé, dans le Dockerfile)
Le certificat est généré **dans l'image** (jamais committé — `*.pem`/`*.key` sont
dans le `.gitignore`).

### `srcs/requirements/nginx/Dockerfile`
```dockerfile
FROM alpine:3.20

RUN apk update && apk add --no-cache nginx openssl

# Certificat auto-signé TLS
RUN mkdir -p /etc/nginx/ssl \
    && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout /etc/nginx/ssl/tfournie.key \
       -out    /etc/nginx/ssl/tfournie.crt \
       -subj "/C=FR/L=Lyon/O=42/CN=tfournie.42.fr"

COPY conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443
ENTRYPOINT ["nginx", "-g", "daemon off;"]
```
**La commande `openssl`, morceau par morceau :**
| Bout | Rôle |
|---|---|
| `openssl req` | Génère une **requête/certificat** X.509. |
| `-x509` | Produit directement un **certificat auto-signé** (pas une simple demande à signer par une autorité). |
| `-nodes` | *"no DES"* → la clé privée **n'est pas chiffrée** par un mot de passe (sinon NGINX demanderait une passphrase au démarrage). |
| `-days 365` | Certificat **valide 1 an**. |
| `-newkey rsa:2048` | Génère **en même temps** une nouvelle clé RSA de 2048 bits. |
| `-keyout ...key` / `-out ...crt` | Où écrire la **clé privée** et le **certificat**. |
| `-subj "/CN=tfournie.42.fr"` | Remplit le sujet du certificat **sans prompt interactif**. Le `CN` (Common Name) = ton domaine. |
> Auto-signé = le navigateur affichera un avertissement (normal en local). En CLI on
> utilisera `curl -k` pour l'ignorer.

### `srcs/requirements/nginx/conf/nginx.conf`
```nginx
events {}

http {
    include /etc/nginx/mime.types;

    server {
        listen 443 ssl;
        server_name tfournie.42.fr;

        ssl_certificate     /etc/nginx/ssl/tfournie.crt;
        ssl_certificate_key /etc/nginx/ssl/tfournie.key;
        ssl_protocols TLSv1.2 TLSv1.3;      # SEULEMENT ces deux versions

        root  /var/www/html;                 # volume partagé avec WordPress
        index index.php;

        location / {
            try_files $uri $uri/ /index.php?$args;
        }

        # PHP → php-fpm dans le conteneur wordpress
        location ~ \.php$ {
            fastcgi_pass wordpress:9000;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
```
**Ligne par ligne :**
| Ligne | Signification |
|---|---|
| `events {}` | Bloc **obligatoire** dans une config NGINX (gestion des connexions). Vide = valeurs par défaut, suffisant ici. |
| `http { ... }` | Contexte des réglages **web** (HTTP/HTTPS). Tout le serveur vit dedans. |
| `include /etc/nginx/mime.types;` | Charge la table des **types de fichiers** (css, js, images…) pour que NGINX envoie le bon `Content-Type`. |
| `server { ... }` | Définit **un serveur virtuel** (un site). |
| `listen 443 ssl;` | Écoute **uniquement** sur le port **443 en TLS**. Pas de `listen 80` → une seule porte d'entrée, exigence du sujet. |
| `server_name tfournie.42.fr;` | Le **nom de domaine** que ce serveur gère. |
| `ssl_certificate` / `ssl_certificate_key` | Chemins du **certificat** et de la **clé privée** générés dans le Dockerfile. |
| `ssl_protocols TLSv1.2 TLSv1.3;` | **Autorise seulement** TLS 1.2 et 1.3 (exigence stricte). Les versions plus anciennes (TLS 1.0/1.1, SSLv3) sont refusées. |
| `root /var/www/html;` | **Racine des fichiers** servis = le **volume partagé** avec WordPress. |
| `index index.php;` | Fichier servi par défaut pour un dossier. |
| `location / { try_files ... }` | Pour toute URL : essaie le fichier, puis le dossier, sinon renvoie vers `index.php` (routage WordPress = *permaliens*). |
| `location ~ \.php$ { ... }` | Bloc **spécifique aux fichiers `.php`** (le `~` = correspondance regex). |
| `fastcgi_pass wordpress:9000;` | **Transmet le PHP** à php-fpm via le réseau docker (conteneur `wordpress`, port 9000). C'est le cœur du reverse proxy. |
| `fastcgi_index index.php;` | Fichier PHP par défaut si l'URL cible un dossier. |
| `include fastcgi_params;` | Charge les **variables standard** FastCGI (méthode, URI, headers…). |
| `fastcgi_param SCRIPT_FILENAME ...;` | Indique à php-fpm **quel fichier .php exécuter** (chemin absolu = racine + script). |
> **À retenir** : NGINX **sert les fichiers statiques** (`root`) et **délègue le PHP**
> à php-fpm (`fastcgi_pass wordpress:9000`). L'`ENTRYPOINT nginx -g "daemon off;"`
> le garde en **foreground / PID 1**. ✅

---

## Étape 6 — docker-compose.yml (l'assemblage)

`srcs/docker-compose.yml` :
```yaml
services:
  mariadb:
    build: ./requirements/mariadb
    image: mariadb                 # image nommée d'après le service
    container_name: mariadb
    restart: always                # redémarre en cas de crash
    env_file: .env
    secrets:
      - db_password
      - db_root_password
    volumes:
      - db_data:/var/lib/mysql
    networks:
      - inception

  wordpress:
    build: ./requirements/wordpress
    image: wordpress
    container_name: wordpress
    restart: always
    depends_on:
      - mariadb
    env_file: .env
    secrets:
      - db_password
      - wp_admin_password
      - wp_user_password
    volumes:
      - wp_files:/var/www/html
    networks:
      - inception

  nginx:
    build: ./requirements/nginx
    image: nginx
    container_name: nginx
    restart: always
    depends_on:
      - wordpress
    ports:
      - "443:443"                  # SEUL port publié vers l'extérieur
    volumes:
      - wp_files:/var/www/html     # même volume que WordPress
    networks:
      - inception

# Volumes nommés, stockés dans /home/tfournie/data
volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tfournie/data/mariadb
  wp_files:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/tfournie/data/wordpress

networks:
  inception:
    driver: bridge

secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  wp_admin_password:
    file: ../secrets/wp_admin_password.txt
  wp_user_password:
    file: ../secrets/wp_user_password.txt
```
**Points à comprendre :**
- `build:` → construit **ton** image via ton Dockerfile (pas un pull).
- `image:` → nom = nom du service (exigé).
- `restart: always` → redémarrage auto (exigé).
- `ports:` **uniquement** sur nginx (443) → seul point d'entrée.
- Le volume `wp_files` est monté dans **nginx ET wordpress** → ils partagent les fichiers.
- `driver_opts ... device:` → le volume nommé pointe vers `/home/tfournie/data/...`
  comme exigé (crée ces dossiers : `mkdir -p /home/tfournie/data/{mariadb,wordpress}`).
- `networks:` déclaré → conforme (pas de `network: host`).

---

## Étape 7 — Le Makefile

`Makefile` (à la racine) :
```makefile
NAME = inception
COMPOSE = srcs/docker-compose.yml
DATA = /home/tfournie/data

all: up

# Crée les dossiers des volumes puis build+démarre
up:
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	docker compose -f $(COMPOSE) up -d --build

down:
	docker compose -f $(COMPOSE) down

# Stop + suppression volumes + images (remise à zéro)
clean: down
	docker system prune -af

fclean: clean
	sudo rm -rf $(DATA)/mariadb $(DATA)/wordpress

re: fclean up

.PHONY: all up down clean fclean re
```
> ⚠️ Tabulations (pas d'espaces) pour l'indentation des recettes Makefile.

---

## Tester & débugger

```bash
# Lancer
make

# Voir les conteneurs (doivent être "Up")
docker compose -f srcs/docker-compose.yml ps

# Suivre les logs d'un service
docker compose -f srcs/docker-compose.yml logs -f wordpress

# Entrer dans un conteneur
docker exec -it mariadb sh

# Vérifier la DB
docker exec -it mariadb mariadb -u tfournie -p wordpress

# Tester le site en CLI (l'auto-signé => -k pour ignorer l'avertissement)
curl -kI https://tfournie.42.fr
```

**Pannes fréquentes :**
| Symptôme | Piste |
|---|---|
| `wordpress` redémarre en boucle | MariaDB pas prête → vérifie la boucle `mysqladmin ping` et l'hôte `mariadb`. |
| `Error establishing a database connection` | mauvais `--dbhost` (doit être `mariadb:3306`) ou `bind-address` de MariaDB. |
| NGINX 502 | `fastcgi_pass` ne pointe pas sur `wordpress:9000`, ou php-fpm pas en 9000. |
| Certif refusé | normal (auto-signé) → `curl -k` ou « accepter le risque » dans le navigateur. |
| DB pas persistée après `down/up` | le volume ne pointe pas vers `/home/tfournie/data/...`. |

---

## Préparation à l'éval

Sois capable d'**expliquer**, pas juste de faire tourner :
- **Différence image / conteneur ?** (moule vs instance)
- **C'est quoi un Docker daemon ?** Le service en arrière-plan qui gère
  images/conteneurs (`dockerd`).
- **Pourquoi PID 1 en foreground ?** Le conteneur vit tant que PID 1 tourne ;
  démoniser le tue → d'où `daemon off`, `-F`, `exec mysqld`.
- **Différence avec une VM ?** Le conteneur partage le noyau de l'hôte (pas d'OS
  invité complet) → léger et rapide ; la VM virtualise tout le matériel.
- **Pourquoi pas `latest` ?** Non reproductible : le build peut changer sans
  prévenir → on fige la version.
- **Où sont les mots de passe ?** Dans `secrets/`, jamais dans git, montés dans
  `/run/secrets/`.
- **Comment les conteneurs communiquent ?** Réseau docker `inception`, par **nom
  de service** (`mariadb`, `wordpress`).
- **Rôle de chaque service ?** NGINX (front TLS), php-fpm (exécute PHP),
  MariaDB (données).
- **Montre** que `git log`/`git status` ne contiennent **aucun** secret.

---

## Checklist finale

- [ ] Arborescence exacte (`srcs/requirements/<service>/{Dockerfile,conf,tools}`).
- [ ] Aucun `latest`, aucune image « toute faite » pullée pour les 3 services.
- [ ] `.env` sans mot de passe ; `secrets/` gitignoré ; rien de sensible dans git.
- [ ] 3 services séparés, chacun son conteneur, chacun son Dockerfile.
- [ ] NGINX : **443 only**, TLS 1.2/1.3, seul port publié.
- [ ] Services en **foreground** (aucun `tail -f`/`sleep infinity`/`while true`).
- [ ] `restart:` sur les 3 services.
- [ ] 2 volumes dans `/home/tfournie/data`.
- [ ] `networks:` déclaré (pas de `network: host`/`--link`).
- [ ] WordPress : 2 users, admin **sans** « admin » dans le nom.
- [ ] `tfournie.42.fr` dans `/etc/hosts` → HTTPS s'ouvre dans le navigateur.
- [ ] `make` monte tout ; `make re` repart de zéro proprement.
- [ ] Supprimer `SETUP_VM.md` et `guide.md` (notes perso) avant de rendre.

---

> **Prochaine action concrète :** Étape 1 (le squelette), puis Étape 2 (`.env` +
> `secrets/`), puis on code **MariaDB** et on le teste avant de continuer.
