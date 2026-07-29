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
| `FROM alpine:3.23` | Image de base (ici Alpine, avant-dernière stable). **Jamais `latest`.** |
| `RUN` | Exécute une commande **au build** (installer des paquets…). |
| `COPY` | Copie un fichier du repo vers l'image. |
| `EXPOSE` | Documente le port utilisé (informatif). |
| `ENTRYPOINT` / `CMD` | La commande lancée **au démarrage du conteneur** (le processus PID 1). |

> ⚠️ **« Avant-dernière stable » = une cible mobile.** Alpine sort une version tous les
> ~6 mois : **vérifie** avant de rendre, ne recopie pas un tuto. État au **29/07/2026** :
> dernière = **3.24** (sortie 09/06/2026) → **avant-dernière = `3.23`** (sortie 03/12/2025).
> Pour contrôler (renvoie `v3.23`) :
> `curl -s https://alpinelinux.org/releases.json | jq -r '[.release_branches[] | select(.rel_branch != "edge")][1].rel_branch'`
> (ou la page <https://alpinelinux.org/releases/>). Idem côté Debian : stable = **13 trixie**,
> donc avant-dernière = **12 bookworm**.

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
**Ligne par ligne :**
- `mkdir -p srcs/requirements/mariadb/{conf,tools}` → crée d'un coup toute la chaîne de dossiers `srcs/requirements/mariadb/` et, dedans, `conf/` **et** `tools/`. `-p` = crée les parents manquants sans erreur si ça existe déjà. `{conf,tools}` = expansion d'accolades du shell (raccourci pour taper deux fois la commande).
- `mkdir -p srcs/requirements/wordpress/{conf,tools}` → idem pour le service **wordpress**.
- `mkdir -p srcs/requirements/nginx/{conf,tools}` → idem pour le service **nginx**.
- `mkdir -p secrets` → crée le dossier `secrets/` (à la racine) qui contiendra les mots de passe.
- `touch Makefile srcs/docker-compose.yml` → crée deux fichiers **vides** : le `Makefile` (racine) et le `docker-compose.yml` (dans `srcs/`).
- `touch srcs/requirements/{mariadb,wordpress,nginx}/Dockerfile` → crée un `Dockerfile` vide dans chacun des trois dossiers de service (encore l'expansion d'accolades).

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

### ✅ Tester l'étape 1 (le squelette)
**Objectif :** vérifier le **nommage** et l'**arborescence** (un caractère faux = refus à l'éval).
```bash
# Chaque service doit avoir Dockerfile + conf/ + tools/
for s in mariadb wordpress nginx; do
  test -f srcs/requirements/$s/Dockerfile && echo "OK   $s/Dockerfile" || echo "MANQUE $s/Dockerfile"
  test -d srcs/requirements/$s/conf       && echo "OK   $s/conf/"      || echo "MANQUE $s/conf/"
  test -d srcs/requirements/$s/tools      && echo "OK   $s/tools/"     || echo "MANQUE $s/tools/"
done
# Les fichiers racine
test -f Makefile && echo "OK Makefile" || echo "MANQUE Makefile"
test -f srcs/docker-compose.yml && echo "OK docker-compose.yml" || echo "MANQUE docker-compose.yml"
```
**Attendu :** que des `OK`. **Ce que ça prouve :** dossier `srcs` (avec `s`), `Dockerfile`
(D majuscule), et les 3 services bien structurés — la base saine avant d'écrire du code.

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
**Ligne par ligne :**
- `# srcs/.env` → simple commentaire (rappelle le chemin du fichier). Dans un `.env`, tout ce qui suit `#` est ignoré.
- `DOMAIN_NAME=tfournie.42.fr` → le nom de domaine du projet ; réutilisé ailleurs via `${DOMAIN_NAME}`.
- `# MariaDB` → commentaire de section.
- `MYSQL_DATABASE=wordpress` → nom de la base de données que MariaDB va créer.
- `MYSQL_USER=tfournie` → nom de l'utilisateur SQL (non-root) que WordPress utilisera pour se connecter.
- `# WordPress admin (nom SANS "admin")` → commentaire ; rappelle l'interdit du sujet.
- `WP_ADMIN_USER=bossman` → login de l'administrateur WordPress. **Ne doit pas** contenir `admin`.
- `WP_ADMIN_EMAIL=bossman@tfournie.42.fr` → email de l'admin.
- `# WordPress 2e utilisateur (obligatoire)` → commentaire.
- `WP_USER=alice` → login du **2e** utilisateur (obligatoire, rôle non-admin).
- `WP_USER_EMAIL=alice@tfournie.42.fr` → email du 2e utilisateur.
- `# Site` → commentaire.
- `WP_TITLE=Inception` → titre du site WordPress (affiché dans l'onglet / l'entête).
- `WP_URL=https://tfournie.42.fr` → URL complète du site (en HTTPS).

> Rappel : **aucun mot de passe** ici. Les mots de passe vont dans `secrets/` (bloc suivant).

### Les secrets (dans `secrets/`)
Un fichier = un mot de passe, **une seule ligne, sans retour à la ligne final** :
```bash
printf 'un_mdp_solide'        > secrets/db_password.txt
printf 'un_mdp_root_solide'   > secrets/db_root_password.txt
printf 'un_mdp_admin_wp'      > secrets/wp_admin_password.txt
printf 'un_mdp_user_wp'       > secrets/wp_user_password.txt
```
**Ligne par ligne :**
- `printf 'un_mdp_solide' > secrets/db_password.txt` → écrit le mot de passe de l'utilisateur SQL `tfournie` dans le fichier, **sans** `\n` final (contrairement à `echo`). Le `>` **écrase** le fichier s'il existe.
- `printf 'un_mdp_root_solide' > secrets/db_root_password.txt` → mot de passe du compte **root** de MariaDB.
- `printf 'un_mdp_admin_wp' > secrets/wp_admin_password.txt` → mot de passe de l'**admin** WordPress (`bossman`).
- `printf 'un_mdp_user_wp' > secrets/wp_user_password.txt` → mot de passe du **2e** utilisateur WordPress (`alice`).

> Pourquoi `printf` et pas `echo` ? `echo` ajoute un retour à la ligne à la fin ; ce `\n` parasite ferait échouer l'authentification (le mot de passe lu vaudrait `"un_mdp_solide\n"`).

> 💡 **Alternative (recommandée) :** au lieu de créer ces fichiers à la main, tu peux
> laisser le `Makefile` les **générer automatiquement** au premier `make` (mots de passe
> aléatoires). Voir *« Variante : générer les secrets au `make` »* à l'Étape 7.

> ⚠️ Vérifie qu'ils sont bien ignorés par git : `git status` ne doit **jamais**
> montrer `secrets/` ni `.env`. (Ton `.gitignore` les couvre déjà.)

**Comment un secret est lu dans le conteneur ?** Docker le monte dans
`/run/secrets/db_password`. Dans un script on fait :
`cat /run/secrets/db_password`. Beaucoup d'images officielles acceptent aussi la
variable `MYSQL_PASSWORD_FILE=/run/secrets/db_password`.

### ✅ Tester l'étape 2 (`.env` + secrets)
**Objectif :** un `.env` propre, des secrets **sans `\n` final**, et **rien** de sensible suivi par git.
```bash
# 1. Aucun commentaire colle a une valeur dans .env (piege classique avec --env-file)
grep -nE '=.*#' srcs/.env && echo ">>> commentaire inline a deplacer sur sa propre ligne" \
                          || echo "OK .env sans commentaire inline"

# 2. Chaque secret = 1 seule ligne, SANS retour final
for f in secrets/*.txt; do
  printf '%-34s %2d octets, %d retour-ligne\n' "$f" "$(wc -c <"$f")" "$(wc -l <"$f")"
done
# Attendu : "0 retour-ligne" partout (sinon tu as utilise echo au lieu de printf)

# 3. git ne doit voir NI .env NI secrets/
git status --porcelain | grep -E '\.env|secrets/' && echo ">>> DANGER: suivi par git" \
                                                   || echo "OK ignores par git"
```
**Attendu :** `OK` partout et `0 retour-ligne`. **Ce que ça prouve :** aucun mot de passe ne
fuira dans git, et les secrets seront lus proprement par les scripts (`cat /run/secrets/...`).

---

## Étape 3 — MariaDB (la base de la stack)

**But :** un conteneur qui, au premier lancement, crée la base `wordpress`, un
utilisateur, ses droits, puis lance `mysqld` en **foreground**.

### `srcs/requirements/mariadb/Dockerfile`
```dockerfile
FROM alpine:3.23

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
**Ligne par ligne :**
- `FROM alpine:3.23` → image de base **Alpine 3.23** (légère, version figée — jamais `latest`). Toutes les instructions suivantes partent de là.
- `# Paquets : le serveur MariaDB + le client` → commentaire.
- `RUN apk update && apk add --no-cache mariadb mariadb-client` → **au build**, met à jour l'index des paquets (`apk update`) puis installe le serveur `mariadb` et le client `mariadb-client`. `--no-cache` = ne garde pas l'index téléchargé → image plus petite. Le `&&` groupe les deux commandes dans **une seule couche**.
- `# Dossiers attendus par mariadb` → commentaire.
- `RUN mkdir -p /var/lib/mysql /run/mysqld \` → crée le dossier des **données** (`/var/lib/mysql`) et celui du **socket** (`/run/mysqld`). Le `\` en fin de ligne = la commande continue à la ligne suivante.
- `    && chown -R mysql:mysql /var/lib/mysql /run/mysqld` → donne la propriété de ces deux dossiers à l'utilisateur/groupe `mysql` (créé par le paquet). `-R` = récursif. Sans ça, `mysqld` (qui tourne en `mysql`) ne pourrait pas écrire.
- `# Config perso + script d'init` → commentaire.
- `COPY conf/my.cnf   /etc/my.cnf` → copie **notre** config depuis le repo (`conf/my.cnf`) vers `/etc/my.cnf` dans l'image.
- `COPY tools/init.sh /usr/local/bin/init.sh` → copie **notre** script d'init dans un dossier du `PATH` (`/usr/local/bin`).
- `RUN chmod +x /usr/local/bin/init.sh` → rend le script **exécutable** (sinon `ENTRYPOINT` échouerait avec "permission denied").
- `EXPOSE 3306` → **documente** que le conteneur utilise le port 3306 (purement informatif ; ne publie rien).
- `ENTRYPOINT ["init.sh"]` → commande lancée **au démarrage du conteneur** (forme *exec*, la bonne). Le script gère l'init **puis** lance `mysqld` en foreground → il devient PID 1.

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
**Ligne par ligne :**
- `#!/bin/sh` → *shebang* : indique que le script s'exécute avec le shell `/bin/sh` (celui d'Alpine).
- `set -e` → le script **s'arrête à la première erreur** (toute commande qui échoue coupe le script). Évite de continuer dans un état cassé.
- `DB_PASS=$(cat /run/secrets/db_password)` → lit le secret monté par Docker et stocke le mot de passe SQL dans `DB_PASS`. `$(...)` = capture la sortie de la commande.
- `DB_ROOT=$(cat /run/secrets/db_root_password)` → idem pour le mot de passe **root**.
- `# Init seulement au 1er lancement...` → commentaire.
- `if [ ! -d /var/lib/mysql/mysql ]; then` → teste **si le dossier `mysql` n'existe pas** dans le datadir. Présent = base déjà initialisée (2e démarrage) → on saute le bloc. Absent = **1er lancement** → on initialise.
- `    mysql_install_db --user=mysql --datadir=/var/lib/mysql` → crée les **tables système** de MariaDB dans le datadir, en tant qu'utilisateur `mysql`.
- `    # Fichier SQL d'initialisation` → commentaire.
- `    cat > /tmp/init.sql <<EOF` → écrit tout ce qui suit (jusqu'à la ligne `EOF`) dans `/tmp/init.sql`. C'est un *here-document*.
- `CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;` → crée la base (nom = variable `.env`) si elle n'existe pas. Les backticks protègent le nom.
- `CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';` → crée l'utilisateur SQL, autorisé depuis **n'importe quel hôte** (`'%'`, indispensable car WordPress est un **autre** conteneur), avec son mot de passe.
- `GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';` → donne **tous les droits** à cet utilisateur, mais **uniquement** sur la base `wordpress` (`.* ` = toutes ses tables).
- `ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT}';` → définit le mot de passe du compte **root** (accès local seulement).
- `FLUSH PRIVILEGES;` → recharge les tables de droits pour que les changements prennent effet.
- `EOF` → marque la **fin** du here-document.
- `    mysqld --user=mysql --bootstrap < /tmp/init.sql` → lance `mysqld` en mode **bootstrap** (init, **sans réseau**) et lui envoie le SQL par l'entrée standard. Il applique tout puis s'arrête.
- `    rm -f /tmp/init.sql` → supprime le fichier SQL temporaire (il contient un mot de passe → on ne le laisse pas traîner).
- `fi` → fin du bloc `if`.
- `# Lancement DÉFINITIF en foreground → devient PID 1` → commentaire.
- `exec mysqld --user=mysql` → lance le vrai serveur. `exec` **remplace** le shell par `mysqld` → celui-ci devient **PID 1**, en **foreground**. ✅ Pas de hack (`tail -f`, `sleep`…).

### Tester MariaDB seul

**Bonne nouvelle : MariaDB se teste isolément**, avant même d'écrire WordPress et
NGINX (c'est tout l'intérêt de l'ordre « bas → haut »). Pas besoin du
`docker-compose.yml` : on build l'image et on la lance à la main.

#### Avant de tester — 5 pièges à vérifier
- [ ] **`init.sh` est complet** : il doit faire l'init **puis** finir par
  `exec mysqld --user=mysql`. Sans `exec mysqld`, le conteneur exécute le script
  puis **s'arrête aussitôt** → rien à tester.
- [ ] **Les `secrets/` existent** : `init.sh` fait `cat /run/secrets/...` avec
  `set -e`. Si les fichiers ne sont pas montés → le script quitte immédiatement.
- [ ] **Dossier du socket cohérent** : le dossier créé/`chown` dans le Dockerfile
  doit être **le même** que le `socket=` de `my.cnf` (ici `/run/mysqld`). Un
  `/run/mysql` d'un côté et `/run/mysqld` de l'autre = mysqld ne démarre pas.
- [ ] **Pas d'espace après le `\`** en fin de ligne dans le Dockerfile : un
  backslash suivi d'un espace **ne continue pas** la ligne → build cassé
  (`unknown instruction: &&`).
- [ ] **Pas de commentaire en fin de ligne dans `.env`** : avec `--env-file`,
  `MYSQL_USER=tfournie   # ex` donne la valeur `tfournie   # ex` (commentaire
  **inclus**). Mets les commentaires sur leur **propre** ligne.

#### Le test (build + run, sans compose)
```bash
# 1. secrets (init.sh les lit → obligatoires)
mkdir -p secrets
printf 'pass_user' > secrets/db_password.txt
printf 'pass_root' > secrets/db_root_password.txt

# 2. dossier du volume sur l'hôte
mkdir -p /home/tfournie/data/mariadb

# 3. build de TON image (pas un pull)
docker build -t mariadb srcs/requirements/mariadb

# 4. lancement : secrets + .env + volume montés à la main
docker run -d --name mariadb \
  --env-file srcs/.env \
  -v /home/tfournie/data/mariadb:/var/lib/mysql \
  -v "$(pwd)/secrets/db_password.txt:/run/secrets/db_password:ro" \
  -v "$(pwd)/secrets/db_root_password.txt:/run/secrets/db_root_password:ro" \
  mariadb
```
**Ligne par ligne :**
- `mkdir -p secrets` → crée le dossier des secrets s'il n'existe pas.
- `printf 'pass_user' > secrets/db_password.txt` → mot de passe de l'utilisateur SQL (sans `\n` final).
- `printf 'pass_root' > secrets/db_root_password.txt` → mot de passe root.
- `mkdir -p /home/tfournie/data/mariadb` → crée le dossier hôte du volume (sinon le montage `-v` crée un dossier vide, mais autant l'avoir).
- `docker build -t mariadb srcs/requirements/mariadb` → construit l'image et la nomme `mariadb` à partir du Dockerfile de ce dossier.
- `docker run -d --name mariadb \` → lance le conteneur en arrière-plan (`-d`), nommé `mariadb`.
- `  --env-file srcs/.env \` → injecte les variables du `.env` (comme le fait `env_file:` dans le compose).
- `  -v /home/tfournie/data/mariadb:/var/lib/mysql \` → monte le volume des données (persistance).
- `  -v "$(pwd)/secrets/db_password.txt:/run/secrets/db_password:ro" \` → simule le secret Docker : monte le fichier en lecture seule (`:ro`) sous `/run/secrets/db_password`.
- `  -v "$(pwd)/secrets/db_root_password.txt:/run/secrets/db_root_password:ro" \` → idem pour le secret root.
- `  mariadb` → l'image à lancer.

#### Ce que tu vérifies (les 4 signaux qui comptent)
```bash
docker ps            # mariadb doit être "Up" et NON "Exited" → PID 1 foreground OK
docker logs mariadb  # aucune erreur ("ready for connections")
docker exec -it mariadb mariadb -u tfournie -p wordpress   # doit se connecter
#   dans le client SQL :  SHOW DATABASES;   → 'wordpress' doit apparaître
```
- Conteneur reste **Up** = ton `exec mysqld` en foreground marche (PID 1). ✅
- Connexion avec l'utilisateur = base + user + droits bien créés. ✅
- `SHOW DATABASES;` liste `wordpress` = le SQL d'init a été appliqué. ✅

#### Test de persistance (important pour l'éval)
```bash
docker rm -f mariadb     # on détruit le conteneur
# on relance l'étape 4 (docker run ...) → la base est TOUJOURS là,
#   et init.sh NE refait PAS l'install (grâce au if [ ! -d /var/lib/mysql/mysql ])
```
Base encore présente après recréation = volume + garde `if [ ! -d ]` OK. ✅

#### Plus tard, via le compose (étape 6)
Une fois le `docker-compose.yml` écrit, le même test se fait plus simplement :
```bash
docker compose -f srcs/docker-compose.yml up mariadb --build
docker exec -it mariadb mariadb -u tfournie -p wordpress   # doit se connecter
```

---

## Étape 4 — WordPress + php-fpm

**But :** installer WordPress, le configurer pour parler à MariaDB, créer les
2 utilisateurs via **wp-cli**, puis lancer **php-fpm en foreground**.

### `srcs/requirements/wordpress/Dockerfile`
```dockerfile
FROM alpine:3.23

# PHP + extensions nécessaires à WordPress + fpm
RUN apk update && apk add --no-cache \
    php83 php83-fpm php83-mysqli php83-phar php83-session \
    php83-curl php83-dom php83-mbstring php83-gd php83-xml \
    curl bash

# wp-cli cherche une commande "php" ; Alpine n'installe que "php83"
RUN ln -sf /usr/bin/php83 /usr/bin/php

# wp-cli : l'outil en ligne de commande pour installer/configurer WordPress
RUN curl -o /usr/local/bin/wp \
      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Config php-fpm : écouter sur 9000 (réseau), pas sur un socket local
COPY conf/www.conf /etc/php83/php-fpm.d/www.conf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

RUN mkdir -p /var/www/html
WORKDIR /var/www/html

EXPOSE 9000
ENTRYPOINT ["init.sh"]
```
**Ligne par ligne :**
- `FROM alpine:3.23` → image de base Alpine 3.23 (version figée).
- `# PHP + extensions nécessaires à WordPress + fpm` → commentaire.
- `RUN apk update && apk add --no-cache \` → installe (au build) PHP et ses modules. Le `\` continue la commande sur plusieurs lignes.
- `    php83 php83-fpm php83-mysqli php83-phar php83-session \` → le cœur **PHP 8.3** (la version packagée par Alpine 3.23 ; `php82` **n'existe plus** dans ses dépôts), **php-fpm** (le gestionnaire FastCGI), `mysqli` (connexion MariaDB), `phar` (archives PHP, requis par wp-cli), `session` (sessions PHP, utilisées par WordPress).
- `    php83-curl php83-dom php83-mbstring php83-gd php83-xml \` → modules requis par WordPress : `curl` (requêtes HTTP), `dom`/`xml` (XML), `mbstring` (chaînes multi-octets), `gd` (images).
- `    curl bash` → l'outil `curl` (pour télécharger wp-cli) et `bash`.
- `RUN ln -sf /usr/bin/php83 /usr/bin/php` → wp-cli démarre par `#!/usr/bin/env php` : il lui faut une commande **`php`** dans le `PATH`. Or Alpine n'installe que `/usr/bin/php83` → sans ce lien symbolique, `wp` répond `not found` au démarrage du conteneur.

> ℹ️ **Pas de `php83-json`** : depuis PHP 8.0 l'extension JSON est **intégrée au cœur**, le
> paquet séparé n'existe plus. L'ajouter ferait échouer le `apk add` (donc le build).
- `# wp-cli : l'outil en ligne de commande...` → commentaire.
- `RUN curl -o /usr/local/bin/wp \` → télécharge wp-cli ; `-o` = enregistre la sortie dans le fichier indiqué.
- `      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \` → l'URL du binaire `.phar` de wp-cli.
- `    && chmod +x /usr/local/bin/wp` → rend `wp` exécutable.
- `# Config php-fpm : écouter sur 9000...` → commentaire.
- `COPY conf/www.conf /etc/php83/php-fpm.d/www.conf` → remplace la config du pool php-fpm par **la nôtre** (écoute sur le port 9000).
- `COPY tools/init.sh /usr/local/bin/init.sh` → copie notre script d'init.
- `RUN chmod +x /usr/local/bin/init.sh` → le rend exécutable.
- `RUN mkdir -p /var/www/html` → crée le dossier racine du site (où WordPress sera installé et où le volume sera monté).
- `WORKDIR /var/www/html` → définit ce dossier comme **répertoire de travail** par défaut (les commandes suivantes s'y exécutent).
- `EXPOSE 9000` → documente le port 9000 (informatif).
- `ENTRYPOINT ["init.sh"]` → au démarrage, lance notre script (install WordPress **puis** php-fpm en foreground).

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
exec php-fpm83 -F
```
**Ligne par ligne :**
- `#!/bin/sh` → shebang : exécution avec `/bin/sh`.
- `set -e` → arrêt à la première erreur.
- `DB_PASS=$(cat /run/secrets/db_password)` → lit le mot de passe SQL depuis le secret.
- `WP_ADMIN_PASS=$(cat /run/secrets/wp_admin_password)` → lit le mot de passe de l'admin WordPress.
- `WP_USER_PASS=$(cat /run/secrets/wp_user_password)` → lit le mot de passe du 2e utilisateur.
- `cd /var/www/html` → se place dans le dossier du site (où wp-cli travaille).
- `# Attendre que MariaDB accepte les connexions` → commentaire.
- `until mysqladmin ping -h mariadb --silent 2>/dev/null; do` → **boucle** tant que MariaDB ne répond pas : `mysqladmin ping` teste la DB sur l'hôte `mariadb` ; `--silent` réduit le bruit ; `2>/dev/null` masque les erreurs. La boucle s'arrête dès que la commande réussit.
- `    echo "En attente de MariaDB..."; sleep 2` → affiche un message et attend 2 s avant de réessayer.
- `done` → fin de la boucle d'attente.
- `if [ ! -f wp-config.php ]; then` → **si** WordPress n'est pas encore installé (pas de `wp-config.php`) → on installe. Au 2e démarrage il existe → on saute le bloc.
- `    wp core download --allow-root` → télécharge les fichiers du cœur WordPress. `--allow-root` autorise wp-cli à tourner en root.
- `    wp config create --allow-root \` → génère le fichier `wp-config.php`…
- `        --dbname="${MYSQL_DATABASE}" \` → nom de la base.
- `        --dbuser="${MYSQL_USER}" \` → utilisateur SQL.
- `        --dbpass="${DB_PASS}" \` → mot de passe SQL (lu du secret).
- `        --dbhost="mariadb:3306"` → **hôte de la DB** = le conteneur `mariadb`, port 3306 (résolution par nom via le réseau docker).
- `    wp core install --allow-root \` → installe réellement le site (crée les tables, l'admin)…
- `        --url="${WP_URL}" \` → URL du site.
- `        --title="${WP_TITLE}" \` → titre du site.
- `        --admin_user="${WP_ADMIN_USER}" \` → login admin (**sans** « admin »).
- `        --admin_password="${WP_ADMIN_PASS}" \` → mot de passe admin.
- `        --admin_email="${WP_ADMIN_EMAIL}"` → email admin.
- `    # 2e utilisateur obligatoire` → commentaire.
- `    wp user create --allow-root \` → crée le 2e utilisateur…
- `        "${WP_USER}" "${WP_USER_EMAIL}" \` → son login et son email (arguments positionnels).
- `        --role=author --user_pass="${WP_USER_PASS}"` → rôle **author** (non-admin) et son mot de passe.
- `fi` → fin du bloc d'installation.
- `# php-fpm en foreground → PID 1` → commentaire.
- `exec php-fpm83 -F` → lance php-fpm en **foreground** (`-F` = *no daemonize*). `exec` remplace le shell → php-fpm devient **PID 1**. ✅

> À noter : la boucle `until mysqladmin ping` est une **vraie** attente de dépendance (autorisée), **pas** un `while true` bidon. C'est la différence entre attendre un service et « fausser » la vie du conteneur.

### ✅ Tester l'étape 4 (WordPress + php-fpm)
**Objectif :** php-fpm démarre en **foreground** (port 9000), WordPress s'installe, et les
**2 utilisateurs** existent. WordPress a besoin de MariaDB → on met les deux sur un réseau commun.
```bash
mkdir -p /home/tfournie/data/wordpress
docker network create inception_test 2>/dev/null || true

# 1. MariaDB sur le reseau (image de l'etape 3)
docker rm -f mariadb 2>/dev/null || true
docker run -d --name mariadb --network inception_test --env-file srcs/.env \
  -v /home/tfournie/data/mariadb:/var/lib/mysql \
  -v "$(pwd)/secrets/db_password.txt:/run/secrets/db_password:ro" \
  -v "$(pwd)/secrets/db_root_password.txt:/run/secrets/db_root_password:ro" \
  mariadb

# 2. Build + run WordPress sur le MEME reseau
docker build -t wordpress srcs/requirements/wordpress
docker rm -f wordpress 2>/dev/null || true
docker run -d --name wordpress --network inception_test --env-file srcs/.env \
  -v /home/tfournie/data/wordpress:/var/www/html \
  -v "$(pwd)/secrets/db_password.txt:/run/secrets/db_password:ro" \
  -v "$(pwd)/secrets/wp_admin_password.txt:/run/secrets/wp_admin_password:ro" \
  -v "$(pwd)/secrets/wp_user_password.txt:/run/secrets/wp_user_password:ro" \
  wordpress
```
Vérifs :
```bash
docker logs wordpress    # doit montrer "En attente de MariaDB..." PUIS l'install WP
docker ps                # wordpress "Up" (pas "Exited") = php-fpm foreground OK
# Les 2 utilisateurs sont-ils crees ?
docker exec -it wordpress wp user list --allow-root --path=/var/www/html
```
**Attendu :** conteneur `Up`, et `wp user list` affiche **2 users** (l'admin sans « admin »
+ l'author). **Ce que ça prouve :** connexion à la DB OK, WordPress installé, contrainte
« 2 users dont 1 admin » respectée.
> Nettoyage quand tu as fini : `docker rm -f wordpress mariadb` (on garde le réseau pour l'étape 5).

---

## Étape 5 — NGINX + TLS

**But :** point d'entrée unique, **443 uniquement**, TLS 1.2/1.3, qui transmet le
PHP à `wordpress:9000` (FastCGI).

### Générer le certificat TLS (auto-signé, dans le Dockerfile)
Le certificat est généré **dans l'image** (jamais committé — `*.pem`/`*.key` sont
dans le `.gitignore`).

### `srcs/requirements/nginx/Dockerfile`
```dockerfile
FROM alpine:3.23

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
**Ligne par ligne :**
- `FROM alpine:3.23` → image de base Alpine 3.23.
- `RUN apk update && apk add --no-cache nginx openssl` → installe le serveur web **nginx** et **openssl** (pour générer le certificat).
- `# Certificat auto-signé TLS` → commentaire.
- `RUN mkdir -p /etc/nginx/ssl \` → crée le dossier où stocker la clé et le certificat.
- `    && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \` → génère le certificat auto-signé (détails dans le tableau ci-dessous).
- `       -keyout /etc/nginx/ssl/tfournie.key \` → chemin de la **clé privée**.
- `       -out    /etc/nginx/ssl/tfournie.crt \` → chemin du **certificat**.
- `       -subj "/C=FR/L=Lyon/O=42/CN=tfournie.42.fr"` → renseigne le sujet sans prompt (pays, ville, organisation, **CN = domaine**).
- `COPY conf/nginx.conf /etc/nginx/nginx.conf` → remplace la config nginx par **la nôtre**.
- `EXPOSE 443` → documente le port 443 (informatif).
- `ENTRYPOINT ["nginx", "-g", "daemon off;"]` → lance nginx en **foreground** grâce à la directive `daemon off;` → nginx devient **PID 1**. ✅

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

### ✅ Tester l'étape 5 (NGINX + TLS)
**Objectif :** config valide, **443 uniquement**, **TLS 1.2/1.3 seulement**, et le PHP délégué
à `wordpress:9000`. (Reprend les conteneurs `mariadb`+`wordpress` de l'étape 4, relancés sur
`inception_test`.)
```bash
# 1. Syntaxe de la config, SANS lancer le serveur (--entrypoint pour ne pas heriter du "daemon off;")
docker build -t nginx srcs/requirements/nginx
docker run --rm --entrypoint nginx nginx -t     # "syntax is ok" + "test is successful"

# 2. Lancer NGINX sur le reseau et publier 443
docker rm -f nginx 2>/dev/null || true
docker run -d --name nginx --network inception_test -p 443:443 \
  -v /home/tfournie/data/wordpress:/var/www/html \
  nginx

# 3. HTTPS repond, HTTP (80) non
curl -kI https://localhost              # -> 200 ou 302 (page WordPress)
curl -I  http://localhost 2>&1 | head -1   # -> "Connection refused" (pas de listen 80) = OK

# 4. TLS : 1.2 accepte, 1.0 refuse
openssl s_client -connect localhost:443 -tls1_2 </dev/null 2>/dev/null | grep -E "Protocol|Cipher"
openssl s_client -connect localhost:443 -tls1   </dev/null 2>&1 \
  | grep -Ei "alert|failure|no protocols" && echo "OK TLS 1.0 refuse"
```
**Attendu :** `nginx -t` OK ; HTTPS répond ; HTTP refusé ; TLS 1.2 négocié, TLS 1.0 rejeté.
**Ce que ça prouve :** point d'entrée unique 443, versions TLS conformes, reverse-proxy vers
php-fpm fonctionnel.
> Note : ton `openssl` local peut refuser `-tls1` de lui-même (TLS 1.0 désactivé côté client)
> → l'échec est attendu dans les deux cas, c'est bien la preuve que 1.0 ne passe pas.

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
**Ligne par ligne :**
- `services:` → début de la liste des conteneurs à lancer.
- `  mariadb:` → 1er service.
- `    build: ./requirements/mariadb` → construit l'image à partir du Dockerfile de ce dossier (chemin relatif à `srcs/`).
- `    image: mariadb` → nomme l'image construite `mariadb` (exigé : nom = service).
- `    container_name: mariadb` → nom fixe du conteneur (permet `docker exec -it mariadb ...`).
- `    restart: always` → redémarre automatiquement le conteneur s'il crashe (exigé).
- `    env_file: .env` → injecte les variables du fichier `.env` dans le conteneur.
- `    secrets:` → liste des secrets montés dans ce conteneur…
- `      - db_password` → monte `/run/secrets/db_password`.
- `      - db_root_password` → monte `/run/secrets/db_root_password`.
- `    volumes:` → montages de volumes…
- `      - db_data:/var/lib/mysql` → monte le volume nommé `db_data` sur le datadir MariaDB (persistance de la base).
- `    networks:` / `      - inception` → rattache le conteneur au réseau privé `inception`.
- `  wordpress:` → 2e service.
- `    build: ./requirements/wordpress` → build depuis son Dockerfile.
- `    image: wordpress` / `    container_name: wordpress` → nom de l'image et du conteneur.
- `    restart: always` → redémarrage auto.
- `    depends_on:` / `      - mariadb` → démarre **après** mariadb (ordre de lancement ; n'attend pas que la DB soit *prête*, d'où la boucle `mysqladmin ping`).
- `    env_file: .env` → variables d'env.
- `    secrets:` (`db_password`, `wp_admin_password`, `wp_user_password`) → les 3 secrets utiles à WordPress.
- `    volumes:` / `      - wp_files:/var/www/html` → monte le volume des fichiers du site.
- `    networks:` / `      - inception` → même réseau.
- `  nginx:` → 3e service.
- `    build: ./requirements/nginx` → build depuis son Dockerfile.
- `    image: nginx` / `    container_name: nginx` → nom de l'image et du conteneur.
- `    restart: always` → redémarrage auto.
- `    depends_on:` / `      - wordpress` → démarre après wordpress.
- `    ports:` / `      - "443:443"` → **publie** le port 443 du conteneur vers l'hôte. **Seul** service exposé à l'extérieur.
- `    volumes:` / `      - wp_files:/var/www/html` → monte **le même** volume que WordPress → nginx sert les fichiers statiques du site.
- `    networks:` / `      - inception` → même réseau.
- `volumes:` → déclaration des **volumes nommés**.
- `  db_data:` → volume de la base.
- `    driver: local` → volume géré localement par Docker.
- `    driver_opts:` → options du driver…
- `      type: none` / `      o: bind` / `      device: /home/tfournie/data/mariadb` → configure un *bind mount* : le volume pointe vers le **dossier réel** `/home/tfournie/data/mariadb` (exigé par le sujet).
- `  wp_files:` → volume des fichiers WordPress, pointant vers `/home/tfournie/data/wordpress` (mêmes options).
- `networks:` / `  inception:` / `    driver: bridge` → crée un réseau privé de type **bridge** (le défaut) reliant les 3 conteneurs. **Pas** de `network: host`.
- `secrets:` → déclare **où** sont les fichiers de secrets sur l'hôte.
- `  db_password:` / `    file: ../secrets/db_password.txt` → le secret `db_password` lit ce fichier (chemin relatif à `srcs/`). Idem pour `db_root_password`, `wp_admin_password`, `wp_user_password`.

**Points à comprendre :**
- `build:` → construit **ton** image via ton Dockerfile (pas un pull).
- `image:` → nom = nom du service (exigé).
- `restart: always` → redémarrage auto (exigé).
- `ports:` **uniquement** sur nginx (443) → seul point d'entrée.
- Le volume `wp_files` est monté dans **nginx ET wordpress** → ils partagent les fichiers.
- `driver_opts ... device:` → le volume nommé pointe vers `/home/tfournie/data/...`
  comme exigé (crée ces dossiers : `mkdir -p /home/tfournie/data/{mariadb,wordpress}`).
- `networks:` déclaré → conforme (pas de `network: host`).

### ✅ Tester l'étape 6 (docker-compose)
**Objectif :** tout monte d'**une seule commande**, les 3 conteneurs tournent, se voient par
**nom**, et **seul NGINX** est exposé.
```bash
# 0. Nettoyer les tests manuels precedents
docker rm -f nginx wordpress mariadb 2>/dev/null || true
docker network rm inception_test 2>/dev/null || true

# 1. Valider le fichier (syntaxe + variables ${...} interpolees)
docker compose -f srcs/docker-compose.yml config >/dev/null && echo "OK compose valide"

# 2. Monter toute l'infra
mkdir -p /home/tfournie/data/mariadb /home/tfournie/data/wordpress
docker compose -f srcs/docker-compose.yml up -d --build

# 3. Les 3 doivent etre "Up" ; SEUL nginx publie un port
docker compose -f srcs/docker-compose.yml ps

# 4. Resolution par nom sur le reseau prive
docker exec wordpress ping -c1 mariadb    # doit repondre (nom -> IP du conteneur)

# 5. Bout-en-bout (necessite "127.0.0.1 tfournie.42.fr" dans /etc/hosts)
curl -kI https://tfournie.42.fr           # -> 200 ou 302
```
**Attendu :** `ps` montre **3× `Up`** et `0.0.0.0:443->443` **uniquement** sur nginx ; `ping`
résout `mariadb` ; `curl` répond. **Ce que ça prouve :** réseau, volumes partagés, dépendances
et point d'entrée unique fonctionnent **ensemble**.

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
**Ligne par ligne :**
- `NAME = inception` → variable (nom du projet) ; surtout pour la lisibilité.
- `COMPOSE = srcs/docker-compose.yml` → variable = chemin du compose (évite de le retaper).
- `DATA = /home/tfournie/data` → variable = dossier des volumes sur l'hôte.
- `all: up` → cible par défaut (celle lancée par `make` seul) → appelle `up`.
- `# Crée les dossiers des volumes puis build+démarre` → commentaire.
- `up:` → cible `up`.
- `→ mkdir -p $(DATA)/mariadb $(DATA)/wordpress` → crée les dossiers hôtes des deux volumes (sinon le *bind mount* échoue). **Indentation = tabulation**.
- `→ docker compose -f $(COMPOSE) up -d --build` → build les images puis démarre les conteneurs en arrière-plan (`-d`). `-f` désigne le fichier compose.
- `down:` → cible `down`.
- `→ docker compose -f $(COMPOSE) down` → arrête et supprime les conteneurs et le réseau (garde les volumes/données).
- `clean: down` → `clean` exécute d'abord `down`…
- `→ docker system prune -af` → supprime **tout** ce qui est inutilisé (images, conteneurs arrêtés, réseaux…). `-a` = tout, `-f` = sans confirmation.
- `fclean: clean` → `fclean` exécute d'abord `clean`…
- `→ sudo rm -rf $(DATA)/mariadb $(DATA)/wordpress` → **supprime les données** des volumes sur l'hôte (remise à zéro totale). `sudo` car les fichiers appartiennent à des UID internes aux conteneurs.
- `re: fclean up` → **rebuild total** : `fclean` puis `up`.
- `.PHONY: all up down clean fclean re` → déclare ces cibles comme « fausses » (pas des fichiers) → make les exécute toujours, même si un fichier du même nom existe.

> ⚠️ Tabulations (pas d'espaces) pour l'indentation des recettes Makefile.

### Variante : générer les secrets au `make`

**Oui, c'est possible et propre.** Plutôt que de créer les `secrets/*.txt` à la main
avec `printf`, tu peux laisser le `Makefile` les **générer** (mots de passe aléatoires)
au premier `make`. Rien n'est committé (le dossier reste gitignoré), aucun mot de passe
en dur. On ajoute une cible `secrets` :

```makefile
SECRETS = secrets

# Génère chaque secret UNE fois (seulement s'il n'existe pas déjà)
secrets:
	@mkdir -p $(SECRETS)
	@test -f $(SECRETS)/db_password.txt      || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/db_password.txt
	@test -f $(SECRETS)/db_root_password.txt  || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/db_root_password.txt
	@test -f $(SECRETS)/wp_admin_password.txt || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/wp_admin_password.txt
	@test -f $(SECRETS)/wp_user_password.txt  || openssl rand -hex 16 | tr -d '\n' > $(SECRETS)/wp_user_password.txt
	@echo "secrets prets."
```

Puis on fait **dépendre `up` de `secrets`** (créés avant le lancement) et on ajoute
`secrets` au `.PHONY` :
```makefile
up: secrets
	mkdir -p $(DATA)/mariadb $(DATA)/wordpress
	docker compose -f $(COMPOSE) up -d --build

.PHONY: all up down clean fclean re secrets
```

**Ligne par ligne :**
- `SECRETS = secrets` → variable = dossier des secrets.
- `secrets:` → nouvelle cible.
- `@mkdir -p $(SECRETS)` → crée le dossier. Le `@` = n'affiche pas la commande exécutée.
- `@test -f $(SECRETS)/db_password.txt || openssl rand -hex 16 | tr -d '\n' > ...` →
  **si** le fichier existe déjà (`test -f`), on ne fait rien ; **sinon** (`||`) on génère
  le mot de passe. `openssl rand -hex 16` = 16 octets aléatoires en hexadécimal
  (32 caractères, uniquement `0-9a-f`). `tr -d '\n'` retire le retour à la ligne →
  **une seule ligne, sans `\n` final** (comme l'exige un secret).
- Les 3 lignes suivantes → idem pour `db_root_password`, `wp_admin_password`, `wp_user_password`.
- `@echo "secrets prets."` → petit message de confirmation.
- `up: secrets` → `up` **dépend** de `secrets` → make génère les secrets **avant** de builder/lancer.
- `.PHONY: ... secrets` → on déclare aussi `secrets` comme cible « fausse ».

**Pourquoi `-hex` et pas `-base64` ?** `openssl rand -base64` peut produire `+ / =`,
qui peuvent poser souci selon le contexte (chaîne SQL, URL…). `-hex` ne sort que de
l'alphanumérique → **zéro surprise**.

> ⚠️ **Piège à comprendre (spécifique MariaDB) :** la base n'est initialisée
> **qu'une seule fois** (garde `if [ ! -d /var/lib/mysql/mysql ]`). Si tu **régénères**
> un mot de passe alors que le volume contient déjà la base créée avec l'**ancien**, le
> nouveau ne sera **pas** appliqué → *Access denied*. D'où le `test -f` : on génère
> **seulement si le fichier n'existe pas**. Règle simple :
> - Tu **gardes** les `secrets/*.txt` → ils restent en phase avec le volume.
> - Pour repartir de zéro : `make fclean` **efface les données** ; si tu veux aussi des
>   mots de passe neufs, supprime les secrets (`rm -f secrets/*.txt`) avant le prochain
>   `make` → base fraîche **et** secrets cohérents.

> 💡 **Éval :** tu dois pouvoir **retrouver** un mot de passe pour te connecter
> (ex. wp-admin ou la DB) → `cat secrets/wp_admin_password.txt`.

### ✅ Tester l'étape 7 (Makefile)
**Objectif :** les cibles marchent, et les **données survivent** à un `down`/`up`.
```bash
# 1. Voir ce que fait 'up' SANS l'executer (dry-run)
make -n up

# 2. Cycle complet
make                                           # = make up
docker compose -f srcs/docker-compose.yml ps   # 3x Up

# 3. Persistance : on cree une donnee, on redemarre, elle doit rester
docker exec wordpress wp post create --post_title="persist-test" \
  --post_status=publish --allow-root --path=/var/www/html
make down
make up
docker exec wordpress wp post list --allow-root --path=/var/www/html | grep persist-test \
  && echo "OK donnees persistees" || echo ">>> volume mal branche"

# 4. Remise a zero complete
make fclean                                    # conteneurs + images + volumes/donnees
```
**Attendu :** `make -n` liste les commandes sans les lancer ; 3× `Up` ; le post `persist-test`
**toujours là** après `down`/`up`. **Ce que ça prouve :** le Makefile orchestre toute l'infra,
et les volumes pointent bien vers `/home/tfournie/data` (données non perdues).
> Le post est stocké **dans la DB** (volume `db_data`) → ce test valide la persistance MariaDB
> à travers un cycle `down`/`up`, le point le plus souvent raté à l'éval.

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
**Ligne par ligne :**
- `make` → lance tout (cible `all` → `up`).
- `docker compose -f srcs/docker-compose.yml ps` → liste l'état des conteneurs (doivent afficher `Up`).
- `docker compose -f srcs/docker-compose.yml logs -f wordpress` → affiche et **suit** (`-f`) les logs du service `wordpress` (utile pour voir l'attente de MariaDB / l'install).
- `docker exec -it mariadb sh` → ouvre un shell interactif (`-it`) **dans** le conteneur `mariadb`.
- `docker exec -it mariadb mariadb -u tfournie -p wordpress` → se connecte au client MariaDB en tant que `tfournie` sur la base `wordpress` ; `-p` demande le mot de passe.
- `curl -kI https://tfournie.42.fr` → teste le site : `-I` ne demande que les en-têtes HTTP, `-k` **ignore** l'avertissement du certificat auto-signé.

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
