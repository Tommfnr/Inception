# Préparation à l'évaluation — Inception

> **Note perso, pas un livrable.** À supprimer avant de rendre, comme `guide.md` et `SETUP_VM.md`.
>
> Ce fichier ne réexplique pas *comment construire* le projet (c'est `guide.md`). Il te prépare à
> le **défendre à l'oral** : la logique d'ensemble, les questions posées, les tests à dérouler.

**Ta config :** domaine `tfournie.42.fr` · admin `boss` · 2e user `little` · Alpine 3.23 ·
PHP 8.3 · MariaDB 11.4 · NGINX 1.28 · données dans `/home/tfournie/data`

---

## Table des matières
1. [Le trajet d'une requête](#1-le-trajet-dune-requête--le-modèle-mental)
2. [Les 6 concepts à maîtriser](#2-les-6-concepts-à-maîtriser)
3. [Questions d'éval — Docker](#3-questions-déval--docker)
4. [Questions d'éval — docker-compose](#4-questions-déval--docker-compose)
5. [Questions d'éval — réseau & volumes](#5-questions-déval--réseau--volumes)
6. [Questions d'éval — sécurité & secrets](#6-questions-déval--sécurité--secrets)
7. [Questions d'éval — NGINX & TLS](#7-questions-déval--nginx--tls)
8. [Questions sur TON code](#8-questions-sur-ton-code-les-plus-dures)
9. [Les tests à dérouler devant le correcteur](#9-les-tests-à-dérouler-devant-le-correcteur)
10. [Les pièges qui font échouer](#10-les-pièges-qui-font-échouer)
11. [Antisèche de dernière minute](#11-antisèche-de-dernière-minute)

---

## 1. Le trajet d'une requête — le modèle mental

**Si tu ne retiens qu'une chose, retiens ce schéma.** La plupart des questions d'éval sont une
variation autour de « qui fait quoi, à quel moment ».

```
Navigateur : https://tfournie.42.fr
      │
      │  1. /etc/hosts traduit tfournie.42.fr -> 127.0.0.1
      │  2. connexion TCP sur le port 443 de la VM
      ▼
┌──────────────────────────────────────────────┐
│  NGINX (seul conteneur exposé)               │
│  - termine le TLS (déchiffre)                │
│  - regarde l'URL demandée                    │
└───────────────┬──────────────────────────────┘
                │
       ┌────────┴─────────┐
       │                  │
   fichier statique   fichier .php
   (.css .js .png)         │
       │                   │  3. protocole FastCGI, port 9000
       │                   ▼
       │      ┌────────────────────────────────┐
       │      │  php-fpm (conteneur wordpress) │
       │      │  - exécute le code PHP         │
       │      └───────────┬────────────────────┘
       │                  │  4. requête SQL, port 3306
       │                  ▼
       │      ┌────────────────────────────────┐
       │      │  MariaDB (conteneur mariadb)   │
       │      │  - renvoie les données du site │
       │      └────────────────────────────────┘
       │                  │
       │                  │  5. PHP génère du HTML
       ▼                  ▼
   NGINX renvoie la réponse au navigateur (chiffrée)
```

**Les trois idées à savoir formuler :**

1. **NGINX ne sait pas exécuter du PHP.** Il sert les fichiers statiques lui-même et **délègue**
   tout ce qui finit par `.php` à php-fpm. C'est la ligne `fastcgi_pass wordpress:9000;`.
2. **php-fpm n'est pas un serveur web.** Il n'écoute pas le HTTP, il ne parle que FastCGI. On ne
   peut pas l'atteindre depuis un navigateur, seulement depuis NGINX.
3. **Les trois conteneurs se trouvent par leur nom** (`wordpress`, `mariadb`), jamais par IP :
   c'est le DNS interne du réseau docker `inception`.

> 💡 **Pourquoi NGINX et WordPress partagent le volume `wp_files` ?** Question fréquente.
> Parce qu'ils ont besoin des **mêmes fichiers pour deux usages différents** : NGINX lit le CSS,
> le JS et les images pour les servir directement ; php-fpm lit les `.php` pour les exécuter.
> Un seul dossier, deux lecteurs.

---

## 2. Les 6 concepts à maîtriser

Si tu sais expliquer ces six-là avec tes mots, tu tiens 80 % de la soutenance.

| Concept | La phrase à savoir dire |
|---|---|
| **Image vs conteneur** | L'image est un modèle figé en lecture seule, le conteneur est une instance qui tourne. Une image → N conteneurs. Comme une classe et ses objets. |
| **PID 1** | Le conteneur vit tant que son processus principal tourne. Il s'arrête, le conteneur meurt. |
| **Volume** | Un dossier qui survit à la destruction du conteneur. Sans lui, la base est perdue à chaque `down`. |
| **Réseau docker** | Un réseau privé où chaque conteneur a une IP et où les noms de service sont résolus par un DNS interne. |
| **Secret** | Un fichier de mot de passe monté en lecture seule dans `/run/secrets/`, jamais dans l'image ni dans git. |
| **Layer** | Chaque `RUN`/`COPY` crée une couche empilée et mise en cache. Modifier une ligne invalide tout ce qui suit. |

---

## 3. Questions d'éval — Docker

### « Quelle est la différence entre un conteneur et une machine virtuelle ? »

**La VM** virtualise du **matériel**. Elle embarque un OS invité complet, avec son propre noyau.
Coût : plusieurs Go, démarrage en dizaines de secondes.

**Le conteneur** partage le **noyau de l'hôte**. Il n'isole que ce qu'il faut, via deux
mécanismes du noyau Linux :
- les **namespaces** → ce que le processus *voit* (ses propres PID, son réseau, ses montages)
- les **cgroups** → ce qu'il peut *consommer* (CPU, RAM)

Coût : quelques Mo, démarrage en millisecondes.

**La conséquence à mentionner :** un conteneur Linux ne peut tourner que sur un noyau Linux.
Docker Desktop sur Mac ou Windows fait tourner une VM Linux en coulisses.

### « Quel est l'intérêt de Docker par rapport à une VM ? »

Trois arguments, dans cet ordre :

1. **Légèreté** — pas d'OS invité à dupliquer, donc on peut faire tourner un service par
   conteneur sans exploser la machine. C'est ce qui rend l'architecture de ce projet viable.
2. **Reproductibilité** — le Dockerfile décrit l'environnement. Le même build donne le même
   résultat chez moi, sur la VM, chez le correcteur.
3. **Isolation par service** — si WordPress tombe, MariaDB continue. Et je peux mettre à jour PHP
   sans toucher à la base.

### « C'est quoi le Docker daemon ? »

`dockerd`, le service qui tourne en arrière-plan sur la machine. C'est **lui** qui construit les
images, crée les conteneurs, gère les réseaux et les volumes.

La commande `docker` que je tape n'est qu'un **client** : elle envoie des requêtes au daemon via
une socket Unix. Quand je fais `docker ps`, c'est le daemon qui répond.

> Sur mon poste, Docker tourne en mode **rootless** : le daemon tourne sous mon utilisateur et pas
> en root. C'est plus sûr, mais ça interdit d'ouvrir les ports sous 1024 — d'où l'obligation de
> tester sur la VM pour le port 443.

### « Pourquoi ne pas utiliser le tag `latest` ? »

Parce qu'il n'est **pas reproductible**. `latest` pointe vers la dernière version publiée, qui
change dans le temps. Un build qui marche aujourd'hui peut casser demain sans qu'une seule ligne
de mon code ait bougé.

J'ai figé `alpine:3.23` : l'avant-dernière stable, comme le sujet le demande.

### « Explique-moi ce que fait ton Dockerfile. »

Prends celui de NGINX, c'est le plus court :

```dockerfile
FROM alpine:3.23                       # on part d'Alpine, version figée
RUN apk add --no-cache nginx openssl   # on installe le serveur + de quoi faire le certificat
RUN mkdir -p /etc/nginx/ssl && openssl req -x509 ...   # on génère le certificat auto-signé
COPY conf/nginx.conf /etc/nginx/nginx.conf             # on met NOTRE config
EXPOSE 443
ENTRYPOINT ["nginx", "-g", "daemon off;"]              # on lance nginx en foreground
```

Points à souligner spontanément : `--no-cache` (image plus légère), le certificat généré **au
build** (donc présent dès le démarrage), et surtout `daemon off;`.

### « Pourquoi `daemon off;` ? Pourquoi le foreground ? »

**C'est LA question du sujet.** Réponse :

Un conteneur vit tant que son **PID 1** tourne. Si je lance nginx normalement, il se
*démonise* : il se détache, rend la main, et le processus de départ se termine. Docker voit son
PID 1 s'arrêter et **tue le conteneur**.

`daemon off;` lui dit de rester au premier plan. Pareil pour les autres :
- php-fpm → `-F` (*no daemonize*)
- MariaDB → `exec mysqld`

### « Pourquoi `exec` devant `mysqld` et `php-fpm` ? »

Bonne question à anticiper, elle distingue ceux qui ont compris.

`exec` **remplace** le processus shell par la commande, au lieu de la lancer comme enfant.
Deux conséquences :

1. Le service devient **PID 1** lui-même, il n'y a pas un `sh` inutile au-dessus.
2. Surtout : il **reçoit les signaux**. Quand je fais `docker stop`, Docker envoie un `SIGTERM`
   au PID 1. Sans `exec`, c'est le shell qui le reçoit, et il ne le transmet pas à MariaDB → la
   base est tuée brutalement au bout du délai de grâce, avec un risque de corruption.

Avec `exec`, MariaDB reçoit le signal directement et s'arrête proprement.

### « Pourquoi `tail -f /dev/null` est-il interdit ? »

Parce que c'est un **mensonge**. Le conteneur paraît « Up », mais son PID 1 ne fait rien : c'est
le vrai service qui tourne en arrière-plan, invisible pour Docker.

Concrètement : si MariaDB crashe, Docker ne le voit pas — `tail` tourne toujours. Le conteneur
reste « Up » alors que le service est mort, et `restart: always` ne se déclenche jamais.

Un conteneur = un processus qu'on surveille. Le hack casse cette garantie.

---

## 4. Questions d'éval — docker-compose

### « Qu'est-ce que docker-compose apporte ? »

Sans lui, il faudrait lancer trois `docker run` à la main, avec pour chacun le réseau, les
volumes, les variables d'environnement, les secrets, l'ordre de démarrage. Des dizaines de flags
à ne pas se tromper, à retaper à chaque fois.

Compose décrit **toute l'infrastructure dans un seul fichier déclaratif**, versionné avec le
code. Une commande monte l'ensemble. Et il crée automatiquement le réseau et les volumes.

### « Quelle différence entre une image utilisée avec et sans docker-compose ? »

**Piège : l'image est exactement la même.** Ce qui change, c'est la façon de la *lancer*.

Sans compose, la configuration d'exécution (réseau, volumes, env) vit dans ma ligne de commande,
donc nulle part : elle est perdue dès que je ferme le terminal.

Avec compose, elle vit dans un fichier versionné, lisible, reproductible.

### « Explique ton `docker-compose.yml`. »

Déroule dans cet ordre :

- **3 services**, chacun avec `build:` (mon Dockerfile) et `image:` (nom = nom du service)
- **`restart: always`** sur les trois → redémarrage automatique en cas de crash, exigé
- **`ports:` uniquement sur nginx** (`443:443`) → seul point d'entrée vers l'extérieur
- **`depends_on:`** → ordre de démarrage
- **2 volumes nommés** pointant vers `/home/tfournie/data`
- **1 réseau** `inception` en bridge
- **4 secrets** lus depuis `../secrets/`

### « `depends_on` garantit-il que MariaDB est prête ? »

**Non, et c'est important.** `depends_on` garantit seulement l'**ordre de démarrage** des
conteneurs : Docker lance mariadb avant wordpress. Mais il n'attend pas que MariaDB soit **prête
à répondre** — il y a plusieurs secondes entre « le conteneur démarre » et « la base accepte des
connexions ».

C'est pour ça que mon `init.sh` WordPress attend activement :

```sh
until nc -z mariadb 3306; do ... done
```

Sans cette boucle, `wp core install` partirait trop tôt et échouerait sur « connexion refusée ».

---

## 5. Questions d'éval — réseau & volumes

### « Explique le réseau docker. »

Compose crée un réseau **bridge** privé nommé `inception`. C'est un commutateur virtuel : chaque
conteneur y reçoit une IP (ici en `172.18.0.x`).

Le point clé : Docker fournit un **DNS interne**. Mes conteneurs se joignent **par leur nom de
service** — `fastcgi_pass wordpress:9000`, `--dbhost=mariadb:3306`. Jamais par IP, parce que les
IP changent à chaque recréation.

### « Pourquoi `network: host` est-il interdit ? »

Parce qu'il **supprime l'isolation réseau** : le conteneur utilise directement la pile réseau de
l'hôte. Plus de réseau privé, plus de DNS interne, et les ports entrent en conflit avec ceux de
la machine.

Ça vide de son sens tout l'intérêt de la conteneurisation. Idem pour `links:`, qui est de toute
façon **déprécié** — les réseaux le remplacent depuis longtemps.

### « C'est quoi un volume, et pourquoi en as-tu besoin ? »

Un conteneur est **éphémère** : sa couche d'écriture disparaît avec lui. Sans volume, un
`make down` effacerait toute la base de données.

Le volume est un espace de stockage **hors du cycle de vie du conteneur**. J'en ai deux :

| Volume | Contenu | Chemin sur l'hôte |
|---|---|---|
| `db_data` | la base MariaDB | `/home/tfournie/data/mariadb` |
| `wp_files` | les fichiers WordPress | `/home/tfournie/data/wordpress` |

### « Pourquoi ces `driver_opts` bizarres dans tes volumes ? »

```yaml
db_data:
  driver_opts:
    type: none
    o: bind
    device: /home/tfournie/data/mariadb
```

Par défaut, un volume nommé est rangé où Docker veut (`/var/lib/docker/volumes/...`). Or le sujet
**impose** que les données soient dans `/home/login/data`.

Ces options transforment le volume nommé en **bind mount** : il garde son nom et sa gestion par
compose, mais pointe vers un dossier précis que je choisis.

---

## 6. Questions d'éval — sécurité & secrets

### « Où sont tes mots de passe ? »

Dans `secrets/`, **un fichier par mot de passe**, jamais dans git (le dossier est dans
`.gitignore`). Compose les monte en lecture seule dans `/run/secrets/` à l'intérieur des
conteneurs, et mes scripts les lisent avec `cat`.

**Preuve à donner spontanément :** `git ls-files | grep secrets` → aucun résultat.

### « Pourquoi ne pas mettre les mots de passe dans le Dockerfile ? »

Deux raisons, donne les deux :

1. **Le Dockerfile est committé** → le mot de passe se retrouve dans git, en clair, pour toujours
   (même après suppression, il reste dans l'historique).
2. **Les layers d'une image sont inspectables.** N'importe qui peut faire `docker history` sur
   mon image et lire les commandes du build. Un `ENV MYSQL_PASSWORD=xxx` s'y voit en clair.

### « Différence entre `.env` et les secrets ? »

| | `.env` | `secrets/` |
|---|---|---|
| Contenu | config **non sensible** (domaine, nom de base, logins) | **mots de passe** uniquement |
| Injection | variables d'environnement | fichiers dans `/run/secrets/` |
| Visible dans | `docker inspect`, `env` | ni l'un ni l'autre |

Les variables d'environnement sont visibles par n'importe quel processus du conteneur et
apparaissent dans `docker inspect`. C'est acceptable pour un nom de base, pas pour un mot de
passe. D'où la séparation.

### « Pourquoi php-fpm tourne en `nobody` et pas en root ? »

**Principe du moindre privilège.** Si une faille d'un plugin WordPress est exploitée, l'attaquant
hérite des droits du processus PHP. En `nobody`, il n'atteint que les fichiers du site ; en root,
il contrôlerait tout le conteneur.

C'est aussi pour ça que mon `init.sh` finit par `chown -R nobody:nobody /var/www/html` : wp-cli
tourne en root pendant l'installation, donc les fichiers lui appartiennent. Sans ce `chown`,
php-fpm — qui tourne en `nobody` — ne pourrait rien écrire : pas d'upload d'image, pas
d'installation de plugin.

---

## 7. Questions d'éval — NGINX & TLS

### « Pourquoi seul NGINX est exposé ? »

C'est le principe du **point d'entrée unique**. Un seul port ouvert vers l'extérieur = une seule
surface d'attaque. MariaDB et php-fpm ne sont joignables que depuis le réseau privé `inception`,
jamais depuis la machine hôte ni depuis Internet.

**Preuve :** dans `docker compose ps`, seul nginx affiche `0.0.0.0:443->443/tcp`. Les deux autres
n'ont aucun port publié.

### « C'est quoi TLS ? »

Le protocole qui sécurise HTTPS. Il fait **deux choses** :

1. **Chiffrer** la connexion → personne sur le réseau ne peut lire ce qui passe
2. **Prouver l'identité** du serveur → je parle bien au bon site, pas à un imposteur

Le certificat sert aux deux.

### « Ton certificat est auto-signé, ça veut dire quoi ? »

Normalement une **autorité de certification** (Let's Encrypt, DigiCert…) vérifie que je possède
bien le domaine, puis signe mon certificat. Mon navigateur ne me connaît pas, mais il connaît
l'autorité : c'est une **chaîne de confiance**.

Ici je l'ai signé moi-même. C'est l'équivalent de fabriquer sa propre carte d'identité.

**Le point important :** le **chiffrement est exactement le même**. Même protocole, mêmes
algorithmes. Ce qui manque, c'est uniquement la garantie d'identité — d'où l'avertissement du
navigateur, qui ne dit pas « ce n'est pas chiffré » mais « je ne peux pas vérifier à qui je
parle ».

**Et je n'ai pas le choix :** `tfournie.42.fr` n'existe pas sur Internet, il ne vit que dans mon
`/etc/hosts`. Aucune autorité ne signera un domaine qui n'appartient à personne.

### « Comment garantis-tu TLS 1.2 / 1.3 uniquement ? »

Une directive dans `nginx.conf` :

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Toute version antérieure (TLS 1.0, 1.1, SSLv3) est refusée au handshake avec une alerte
`protocol version`. Je peux le démontrer — voir le test 5 plus bas.

### « C'est quoi FastCGI ? »

Le protocole qui relie NGINX et php-fpm. NGINX ne sait pas exécuter du PHP : quand une URL finit
par `.php`, il transmet la requête à php-fpm via FastCGI (`fastcgi_pass wordpress:9000`), php-fpm
exécute le script et renvoie le HTML généré, que NGINX transmet au navigateur.

`fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;` est la ligne qui indique à
php-fpm **quel fichier** exécuter.

---

## 8. Questions sur TON code (les plus dures)

Ce sont celles où on te demande de justifier un choix précis. Elles font la différence.

### « Pourquoi `nc -z` et pas `mysqladmin ping` pour attendre la base ? »

Parce que **`mysqladmin` n'existe pas dans l'image wordpress**. Il vient du paquet
`mariadb-client`, installé dans l'image mariadb — mais les deux images sont totalement séparées,
elles ne partagent aucun binaire.

Si je l'utilisais, la commande renverrait *command not found*, la boucle `until` le lirait comme
« base pas prête », et le conteneur bouclerait **à l'infini** sans message d'erreur exploitable.

`nc` est fourni par busybox, déjà présent dans Alpine : zéro paquet à installer.

### « Un test de port suffit-il vraiment ? La base pourrait répondre sans être prête. »

Excellente objection, et la réponse tient à mon `init.sh` MariaDB : j'initialise avec
`mysqld --bootstrap`, qui travaille **hors réseau** et n'ouvre aucun port. Le serveur ne se met à
écouter qu'au `exec mysqld` final, une fois l'initialisation terminée.

Donc « port 3306 ouvert » signifie bien « base réellement prête ». Aucun faux positif possible.

### « Pourquoi une limite au nombre de tentatives ? »

```sh
if [ "$i" -ge 30 ]; then
    echo "MariaDB ne répond pas après 60s, abandon." >&2
    exit 1
fi
```

Pour que le conteneur **échoue avec un message clair** au lieu de boucler indéfiniment. Un
conteneur qui plante se débugge en lisant les logs ; un conteneur qui boucle en silence coûte des
heures.

C'est aussi ce qui prouve que ma boucle n'est **pas** un hack de maintien en vie : elle a une fin.

### « Pourquoi `if [ ! -d /var/lib/mysql/mysql ]` dans ton init MariaDB ? »

Pour n'initialiser la base **qu'au premier lancement**. Le dossier `/var/lib/mysql/mysql`
contient les tables système : s'il existe, c'est que la base a déjà été créée lors d'un démarrage
précédent, et je saute tout le bloc.

Sans ce garde-fou, chaque redémarrage tenterait de recréer la base et écraserait les données.

### « Pourquoi `'user'@'%'` et pas `'user'@'localhost'` ? »

Parce que WordPress est dans un **autre conteneur**, donc une autre IP. Pour MariaDB, la connexion
n'arrive pas de `localhost` mais de `172.18.0.x`. Le `%` autorise n'importe quel hôte — ce qui est
acceptable ici car la base n'est joignable **que depuis le réseau privé**, jamais de l'extérieur.

À noter : le compte `root` reste, lui, limité à `localhost`.

### « Pourquoi `memory_limit = 512M` ? »

Parce que `wp core download` extrait l'archive WordPress **en mémoire**, et les 128 Mo par défaut
de PHP n'y suffisent pas :

```
PHP Fatal error: Allowed memory size of 134217728 bytes exhausted
```

Le conteneur crashait, `restart: always` le relançait, il recrashait — boucle infinie. Je passe
par un fichier dans `/etc/php83/conf.d/`, qui surcharge le `php.ini` sans le modifier.

### « Pourquoi `-nodes` dans ta commande openssl ? »

*no DES* : la clé privée n'est **pas chiffrée par une passphrase**. Sinon NGINX demanderait le mot
de passe au démarrage, et personne ne serait là pour le taper dans un conteneur.

Même logique pour `-subj` : sans lui, openssl poserait ses questions en interactif et le
`docker build` resterait bloqué à attendre une réponse.

### « Pourquoi `skip-name-resolve` dans `my.cnf` ? »

Ça désactive la résolution DNS inverse des clients qui se connectent. Sans ça, MariaDB tente pour
chaque connexion de retrouver le nom d'hôte de l'IP — ce qui ralentit et peut bloquer si le DNS
ne répond pas. Mes droits sont définis par IP (`@'%'`), je n'ai aucun besoin des noms.

---

## 9. Les tests à dérouler devant le correcteur

À faire dans l'ordre. Chaque test répond à une case de la grille.

### Test 1 — Tout monte d'une commande

```bash
make
docker compose -f srcs/docker-compose.yml ps
```
**Attendu :** 3 conteneurs `Up`, et `0.0.0.0:443->443/tcp` **uniquement** sur nginx.
**Prouve :** point d'entrée unique, les 3 services tournent.

### Test 2 — Le site répond en HTTPS, et pas en HTTP

```bash
curl -kI https://tfournie.42.fr        # -> 200 ou 302
curl -I  http://tfournie.42.fr         # -> Connection refused
```
**Prouve :** 443 uniquement, pas de `listen 80`.

Puis ouvre `https://tfournie.42.fr` dans le navigateur : avertissement de certificat (normal,
auto-signé) → « Paramètres avancés » → « Continuer ». Le site WordPress s'affiche.

### Test 3 — Aucun hack de maintien en vie

```bash
docker exec nginx     ps -o pid,args | head -3
docker exec wordpress ps -o pid,args | head -3
docker exec mariadb   ps -o pid,args | head -3
```
**Attendu :** en PID 1, `nginx: master process`, `php-fpm: master process`, `mysqld`.
**Jamais** `tail -f`, `sleep infinity`, `bash`.
**Prouve :** les vrais services tournent en foreground.

### Test 4 — Les conteneurs se parlent par leur nom

```bash
docker exec wordpress getent hosts mariadb
docker exec nginx     getent hosts wordpress
```
**Attendu :** une IP en `172.18.0.x` pour chaque.
**Prouve :** le DNS du réseau docker fonctionne, pas de `--link`, pas d'IP en dur.

### Test 5 — TLS 1.2 / 1.3 uniquement

```bash
for v in TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; do
  out=$(printf 'HEAD / HTTP/1.0\r\nHost: tfournie.42.fr\r\n\r\n' | \
        openssl s_client -connect tfournie.42.fr:443 -min_protocol $v -max_protocol $v \
        -cipher 'DEFAULT@SECLEVEL=0' -quiet 2>&1)
  echo "$out" | grep -q 'HTTP/1' && echo "$v -> ACCEPTE" || echo "$v -> REFUSE"
done
```
**Attendu :** `TLSv1 -> REFUSE`, `TLSv1.1 -> REFUSE`, `TLSv1.2 -> ACCEPTE`, `TLSv1.3 -> ACCEPTE`.

> ⚠️ N'utilise **pas** la ligne `Protocol :` d'`openssl s_client` comme preuve : elle affiche le
> protocole **tenté**, même quand le handshake a échoué. Il faut exiger une vraie réponse HTTP.

### Test 6 — Deux utilisateurs, dont un admin sans « admin »

```bash
docker exec wordpress wp user list --allow-root --path=/var/www/html \
  --fields=ID,user_login,roles
```
**Attendu :** `boss / administrator` et `little / author`.
**Prouve :** contrainte des 2 users, et le nom d'admin ne contient pas « admin ».

### Test 7 — La persistance (le plus souvent raté)

```bash
docker exec wordpress wp post create --post_title="persist-test" \
  --post_status=publish --allow-root --path=/var/www/html
make down && make up
sleep 15
docker exec wordpress wp post list --allow-root --path=/var/www/html | grep persist-test
```
**Attendu :** l'article est toujours là.
**Prouve :** les volumes pointent bien vers `/home/tfournie/data` et la base survit.

### Test 8 — Redémarrage automatique

```bash
docker kill wordpress
sleep 10
docker ps --filter name=wordpress --format '{{.Names}} {{.Status}}'
```
**Attendu :** `Up` de nouveau, grâce à `restart: always`.

### Test 9 — Rien de sensible dans git

```bash
git ls-files | grep -E 'secrets/|\.env$'      # -> aucun résultat
git log -p | grep -iE 'password|mdp' | head   # -> rien de compromettant
```

### Test 10 — Les données sont au bon endroit

```bash
ls /home/tfournie/data/mariadb /home/tfournie/data/wordpress
```
**Attendu :** les fichiers de la base d'un côté, ceux de WordPress de l'autre.

---

## 10. Les pièges qui font échouer

| Piège | Comment l'éviter |
|---|---|
| `latest` quelque part | `grep -rn latest srcs/` → doit être vide |
| Mot de passe committé | `git ls-files \| grep secrets` → vide |
| `tail -f`, `sleep infinity`, `while true` | `grep -rnE 'tail -f\|sleep infinity\|while true' srcs/` → vide |
| `network: host` ou `links:` | `grep -nE 'network: host\|links:' srcs/docker-compose.yml` → vide |
| Nom d'admin contenant « admin » | le mien est `boss` ✅ |
| Un service en `latest` pullé au lieu d'être buildé | les 3 ont `build:` dans le compose |
| Données perdues après `make down` | test 7 |
| Conteneur orphelin d'un test manuel | `docker ps -a` avant de commencer — un conteneur **arrêté réserve son nom** |

**Vérification groupée, à lancer avant l'éval :**

```bash
echo "--- latest ---";        grep -rn "latest" srcs/ || echo OK
echo "--- hacks ---";         grep -rnE 'tail -f|sleep infinity|while true' srcs/ || echo OK
echo "--- network host ---";  grep -nE 'network: host|links:' srcs/docker-compose.yml || echo OK
echo "--- secrets git ---";   git ls-files | grep -E 'secrets/|\.env$' || echo OK
echo "--- conteneurs ---";    docker ps -a --format '{{.Names}} {{.Status}}'
```

---

## 11. Antisèche de dernière minute

**Les 5 phrases à savoir dire par cœur :**

1. « Un conteneur partage le noyau de l'hôte, une VM embarque son propre OS complet. »
2. « Le conteneur vit tant que son PID 1 tourne — d'où le foreground, d'où `exec`. »
3. « NGINX sert le statique et délègue le PHP à php-fpm via FastCGI. »
4. « Les conteneurs se joignent par leur nom de service, grâce au DNS du réseau docker. »
5. « Les mots de passe sont dans des fichiers montés en `/run/secrets/`, jamais dans l'image ni dans git. »

**Les chemins à connaître :**

| Quoi | Où |
|---|---|
| Données MariaDB | `/var/lib/mysql` → `/home/tfournie/data/mariadb` |
| Fichiers WordPress | `/var/www/html` → `/home/tfournie/data/wordpress` |
| Certificat TLS | `/etc/nginx/ssl/tfournie.{crt,key}` |
| Secrets dans le conteneur | `/run/secrets/<nom>` |
| Config php-fpm | `/etc/php83/php-fpm.d/www.conf` |

**Les ports :**

| Service | Port | Exposé à l'hôte ? |
|---|---|---|
| NGINX | 443 | ✅ le seul |
| php-fpm | 9000 | ❌ réseau interne |
| MariaDB | 3306 | ❌ réseau interne |

**Si un correcteur demande un mot de passe :** `cat secrets/wp_admin_password.txt`

**Si quelque chose plante en direct :** `docker compose -f srcs/docker-compose.yml logs <service>`
— et lis les logs à voix haute. Savoir débugger devant le correcteur vaut mieux que paniquer.
