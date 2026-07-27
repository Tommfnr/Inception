# Setup VM — Inception (note perso)

> Checklist pour préparer la VM Debian + Docker avant de coder.
> Ce fichier est une note personnelle, **pas** un livrable du sujet
> (les livrables sont `README.md`, `USER_DOC.md`, `DEV_DOC.md`).

**Objectif de la première session :** faire tourner `docker run hello-world` dans la VM.

---

## Pendant l'installation de Debian (si en cours)

- **Partitionnement** : « Assisté – utiliser tout le disque », une seule partition suffit.
- **Utilisateur** : créer `tfournie` (cohérent avec les chemins du sujet).
- **Écran « sélection des logiciels »** : cocher **serveur SSH** + **utilitaires usuels du système**.

---

## 1. Premier boot — outils de base

```bash
su -                                    # devenir root
apt update && apt upgrade -y
apt install -y sudo git make curl vim ca-certificates
usermod -aG sudo tfournie               # autoriser sudo
```
Puis **se déconnecter / reconnecter** pour activer sudo.

## 1bis. Se connecter en SSH depuis l'hôte (optionnel mais confortable)

Permet de bosser depuis son vrai terminal (copier/coller, onglets) au lieu
de la fenêtre VirtualBox.

**a. Vérifier que le serveur SSH tourne dans la VM :**
```bash
sudo systemctl status ssh
# si absent : sudo apt install -y openssh-server && sudo systemctl enable --now ssh
```

**b. VirtualBox en NAT — redirection de port** (une seule fois) :
`Config VM -> Réseau -> Avancé -> Redirection de ports`, ajouter :

| Nom | Proto | IP hôte   | Port hôte | Port invité |
|-----|-------|-----------|-----------|-------------|
| ssh | TCP   | 127.0.0.1 | 2222      | 22          |

**c. Depuis l'hôte, se connecter :**
```bash
ssh tfournie@127.0.0.1 -p 2222
ssh-copy-id -p 2222 tfournie@127.0.0.1   # (optionnel) sans retaper le mot de passe
```

> Si réseau « Accès par pont » (bridged) au lieu de NAT : pas de redirection,
> récupérer l'IP avec `ip a` puis `ssh tfournie@<IP_de_la_VM>`.

## 2. Installer Docker + docker compose

```bash
curl -fsSL https://get.docker.com | sh   # méthode officielle
sudo usermod -aG docker tfournie         # docker sans sudo
```
⚠️ **Se déconnecter / reconnecter** (ou `reboot`) pour appliquer le groupe `docker`.

## 3. Vérifier (l'étape qui débloque tout)

```bash
docker run hello-world      # -> "Hello from Docker!"
docker compose version      # -> une version
```
Tant que ces deux commandes ne passent pas, ne pas aller plus loin.

## 4. Domaine tfournie.42.fr -> IP locale

```bash
echo "127.0.0.1 tfournie.42.fr" | sudo tee -a /etc/hosts
ping tfournie.42.fr         # doit répondre depuis 127.0.0.1
```

## 5. Récupérer le projet

```bash
cd ~
git clone git@github.com:Tommfnr/Inception.git
# (ajouter la clé SSH GitHub dans la VM, ou cloner en HTTPS)
```

## 6. Comment tester le site (choisir A ou B)

Pour l'éval : ouvrir `https://tfournie.42.fr` dans un navigateur.

- **A — Navigateur dans la VM** (le plus simple pour débuter)
  ```bash
  sudo apt install -y xfce4 firefox-esr
  ```
- **B — Navigateur depuis l'hôte**
  - Redirection de port VirtualBox : `443 hôte -> 443 VM`
  - Ajouter `127.0.0.1 tfournie.42.fr` dans le `/etc/hosts` **de l'hôte**

En attendant, test CLI possible : `curl -k https://tfournie.42.fr`

## 7. Snapshot

Une fois Docker OK : VirtualBox -> **Machine -> Prendre un instantané**.
Permet de revenir à une base propre en cas de casse.

---

## Récap ultra-court

```
1. su -  ->  sudo, git, make, curl, vim
2. install Docker + docker compose
3. docker run hello-world      <-- objectif du jour
4. /etc/hosts  ->  tfournie.42.fr
5. git clone
6. choisir A ou B pour tester dans un navigateur
7. snapshot
```

---

## Rappels sujet à garder en tête (pour la suite)

- 3 services : **NGINX** (443, TLS1.2/1.3 only) -> **WordPress+php-fpm** -> **MariaDB**
- Images construites soi-même (`FROM` = avant-dernière stable Alpine/Debian)
- Interdits : `latest`, `network: host`, `--link`, `tail -f`, `sleep infinity`, `while true`
- Services en **foreground** (PID 1), pas de hack pour garder le conteneur vivant
- 2 volumes nommés dans `/home/tfournie/data`
- `.env` = config non-secrète ; `secrets/` = mots de passe
- Admin WordPress : nom **sans** admin/administrator
- Conteneurs avec `restart:`
