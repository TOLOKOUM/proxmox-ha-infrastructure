# 📧 Guide d'Installation Zimbra — Version 8 et Version 10

> **Auteur** : David Tolokoum  
> **Projet** : Master 2 Ingénierie Informatique — ENSPY  
> **Contexte** : Infrastructure de messagerie pour le Ministère de la Fonction Publique  
> **Domaine de test** : `ministere.test`

---

## 📋 Table des Matières

1. [Prérequis Communs](#1-prérequis-communs)
2. [Installation Zimbra 8.8.12 sur Ubuntu 16.04](#2-installation-zimbra-8812-sur-ubuntu-1604)
3. [Installation Zimbra 10 sur Ubuntu 22.04](#3-installation-zimbra-10-sur-ubuntu-2204)
4. [Dépannage Commun](#4-dépannage-commun)

---

## 1. Prérequis Communs

### Configuration matérielle minimale

| Ressource | Minimum | Recommandé |
|-----------|---------|------------|
| RAM | 8 Go | 16 Go |
| CPU | 2 cœurs | 4 cœurs |
| Disque | 20 Go libres | 50 Go |
| Réseau | IP statique | IP statique |

### Informations réseau à préparer

Avant de commencer, notez ces informations qui seront utilisées tout au long de l'installation :

- **Adresse IP de la VM** (ex: `192.168.75.156`)
- **Hostname complet (FQDN)** (ex: `ubuntu.ministere.test`)
- **Domaine mail** (ex: `ministere.test`)
- **Mot de passe administrateur** Zimbra

---

## 2. Installation Zimbra 8.8.12 sur Ubuntu 16.04

### 2.1 Préparation du système

#### Mettre à jour Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

#### Configurer le hostname (FQDN)

```bash
sudo hostnamectl set-hostname ubuntu.ministere.test
```

Éditez le fichier `/etc/hostname` :

```bash
sudo nano /etc/hostname
```

Contenu attendu :
```
ubuntu.ministere.test
```

#### Configurer le fichier /etc/hosts

```bash
sudo nano /etc/hosts
```

Ajoutez cette ligne (remplacez l'IP par la vôtre) :
```
192.168.75.156   ubuntu.ministere.test   ubuntu
```

Vérifiez que le hostname est correct :
```bash
hostname -f
# Doit retourner : ubuntu.ministere.test
```

#### Vérifier qu'aucun service n'occupe le port 25

```bash
sudo ss -tlnp | grep :25
# Le résultat doit être vide
```

---

### 2.2 Téléchargement de l'archive Zimbra 8

```bash
cd /tmp
wget https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_4179.UBUNTU16_64.20211118033954.tgz
```

> ⚠️ **Si vous transférez le fichier depuis Windows via WinSCP**, des caractères invisibles peuvent corrompre le nom du fichier. Dans ce cas, renommez-le immédiatement :

```bash
mv *.tgz zimbra.tgz
```

> 💡 **Si même `mv *.tgz` échoue**, utilisez la méthode par inode :
> ```bash
> ls -i          # Notez le numéro (ex: 123456)
> find . -inum 123456 -exec mv {} zimbra.tgz \;
> ```

#### Extraire l'archive

```bash
tar xzvf zimbra.tgz
```

---

### 2.3 Lancement de l'installation

```bash
cd zcs-8.8.15_GA_4179.UBUNTU16_64*
sudo ./install.sh
```

#### Réponses aux questions interactives

| Question | Réponse |
|----------|---------|
| Do you agree with the terms of the software license agreement? | `Y` |
| Use Zimbra's package repository? | `Y` |
| Install zimbra-ldap? | `Y` |
| Install zimbra-logger? | `Y` |
| Install zimbra-mta? | `Y` |
| Install zimbra-dnscache? | `Y` |
| Install zimbra-snmp? | `Y` |
| Install zimbra-store? | `Y` |
| Install zimbra-apache? | `Y` |
| Install zimbra-spell? | `Y` |
| Install zimbra-memcached? | `Y` |
| Install zimbra-proxy? | `Y` |
| The system will be modified. Continue? | `Y` |

---

### 2.4 Configuration du domaine

L'installateur va chercher des enregistrements DNS pour votre domaine. En environnement de test, ces enregistrements n'existent pas — c'est normal.

```
DNS ERROR resolving ubuntu.ministere.test
Change hostname [Yes]  →  No

DNS ERROR - none of the MX records resolve to this host
Change domain name? [Yes]  →  Yes

Create domain: [ubuntu.ministere.test]  →  ministere.test
```

> 💡 En tapant `ministere.test`, vos adresses email seront de la forme `user@ministere.test`.

Si l'installateur insiste une deuxième fois :
```
Re-Enter domain name? [Yes]  →  No
```

---

### 2.5 Configuration du mot de passe administrateur

Après la configuration du domaine, un menu numéroté apparaît. La ligne **zimbra-store** contient des `*******` indiquant que le mot de passe admin n'est pas défini.

```
Tapez : 4   (entrer dans zimbra-store)
Tapez : 7   (Admin Password)
Saisissez votre mot de passe et appuyez sur Entrée
Tapez : r   (retour au menu principal)
Tapez : a   (appliquer la configuration)
```

Répondez aux dernières questions :
```
Save config to a file? [Yes]          →  Entrée (Yes par défaut)
The system will be modified. Continue? →  Yes
```

> ⏳ L'installation peut prendre 5 à 15 minutes. Ne pas interrompre le processus.

---

### 2.6 Vérification de l'installation

```bash
sudo su - zimbra
zmcontrol status
```

Tous les services doivent afficher **Running** :
```
ldap                Running
mailbox             Running
memcached           Running
mta                 Running
proxy               Running
stats               Running
```

#### Accès aux interfaces

| Interface | URL |
|-----------|-----|
| Console Admin | `https://192.168.75.156:7071` |
| Webmail | `https://192.168.75.156` |

**Identifiants admin :**
- Login : `admin@ministere.test`
- Mot de passe : celui défini à l'étape 2.5

> ⚠️ Votre navigateur affichera une alerte de certificat auto-signé. Cliquez sur **Paramètres avancés** puis **Continuer vers le site**.

---

## 3. Installation Zimbra 10 sur Ubuntu 22.04

### 3.1 Préparation du système

#### Mettre à jour Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

#### Configurer le hostname

> ⚠️ **Important pour la migration** : Si vous prévoyez de migrer depuis Zimbra 8, utilisez exactement le même hostname et domaine.

```bash
sudo hostnamectl set-hostname ubuntu.ministere.test
```

#### Configurer /etc/hosts

```bash
sudo nano /etc/hosts
```

Ajoutez :
```
192.168.x.x   ubuntu.ministere.test   ubuntu
```

Vérifiez :
```bash
hostname -f
# Doit retourner : ubuntu.ministere.test
```

#### Désactiver systemd-resolved (conflit DNS avec Zimbra)

```bash
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

#### Retirer l'attribut immutable sur resolv.conf

> ⚠️ Cette étape est critique sur Ubuntu 22.04. Sans elle, l'installation de Zimbra échouera sur le paquet `resolvconf`.

```bash
sudo chattr -i /etc/resolv.conf
```

#### Désactiver AppArmor (si installé)

```bash
sudo systemctl stop apparmor
sudo systemctl disable apparmor
```

> 💡 Si AppArmor n'est pas installé, ces commandes retourneront une erreur — c'est normal, continuez.

#### Vérifier que le port 25 est libre

```bash
sudo ss -tlnp | grep :25
# Le résultat doit être vide
```

---

### 3.2 Configuration du pare-feu

```bash
sudo ufw allow 25/tcp   && \
sudo ufw allow 80/tcp   && \
sudo ufw allow 110/tcp  && \
sudo ufw allow 143/tcp  && \
sudo ufw allow 443/tcp  && \
sudo ufw allow 465/tcp  && \
sudo ufw allow 587/tcp  && \
sudo ufw allow 993/tcp  && \
sudo ufw allow 995/tcp  && \
sudo ufw allow 7071/tcp && \
sudo ufw enable         && \
sudo ufw reload
```

Vérifiez :
```bash
sudo ufw status
# Status doit être : active
# Tous les ports doivent apparaître en ALLOW
```

---

### 3.3 Téléchargement de Zimbra 10 FOSS

> ℹ️ Zimbra 10 n'a pas de version Open Source officielle. Nous utilisons le build communautaire **Maldua** (reconnu et validé sur les forums Zimbra officiels).

```bash
cd /tmp
wget "https://github.com/maldua/zimbra-foss/releases/download/zimbra-foss-build-ubuntu-22.04/10.1.16.p1/zcs-10.1.16_GA_4200001.UBUNTU22_64.20260310121616.tgz"
```

> ⏳ Le fichier fait environ **225 Mo**. Attendez que la progression atteigne 100%.

Vérifiez que le fichier est complet (doit afficher environ 236 Mo) :
```bash
ls -lh zcs-10.1.16*.tgz
```

#### Extraire l'archive

```bash
tar xzvf zcs-10.1.16_GA_4200001.UBUNTU22_64.20260310121616.tgz
cd zcs-10.1.16_GA_4200001.UBUNTU22_64.20260310121616
```

---

### 3.4 Lancement de l'installation

```bash
sudo ./install.sh
```

#### Réponses aux questions interactives

| Question | Réponse |
|----------|---------|
| Do you agree with the terms of the software license agreement? | `Y` |
| Use Zimbra's package repository? | `Y` |
| Install zimbra-ldap? | `Y` |
| Install zimbra-logger? | `Y` |
| Install zimbra-mta? | `Y` |
| Install zimbra-dnscache? | **`N`** ⚠️ |
| Install zimbra-snmp? | `Y` |
| Install zimbra-store? | `Y` |
| Install zimbra-apache? | `Y` |
| Install zimbra-spell? | `Y` |
| Install zimbra-memcached? | `Y` |
| Install zimbra-proxy? | `Y` |
| The system will be modified. Continue? | `Y` |

> ⚠️ **zimbra-dnscache doit impérativement être refusé (`N`)** sur Ubuntu 22.04 car il entre en conflit avec le DNS système et bloque l'installation.

#### Si un répertoire /opt/zimbra existe déjà

Si l'installateur détecte un répertoire Zimbra résiduel :
```
Would you like to delete /opt/zimbra before installing? [N]  →  Y
```

---

### 3.5 Configuration du domaine

Même procédure que Zimbra 8 :

```
DNS ERROR resolving ubuntu.ministere.test
Change hostname [Yes]  →  No

Change domain name? [Yes]  →  No
```

> 💡 On conserve `ministere.test` pour maintenir la compatibilité avec les données de Zimbra 8.

---

### 3.6 Configuration du mot de passe administrateur

Le menu numéroté apparaît avec `******* Admin Password UNSET` :

```
Tapez : 6   (entrer dans zimbra-store)
Tapez : 4   (Admin Password)
Saisissez votre mot de passe et appuyez sur Entrée
Tapez : r   (retour au menu principal)
Tapez : a   (appliquer la configuration)
```

Répondez aux dernières questions :
```
Save config to a file? [Yes]           →  Entrée (Yes par défaut)
The system will be modified. Continue?  →  Yes
```

> ⏳ L'installation prend 5 à 15 minutes. Ne pas interrompre.

---

### 3.7 Vérification de l'installation

```bash
sudo su - zimbra
zmcontrol status
```

Tous les services doivent afficher **Running**.

#### Accès aux interfaces

| Interface | URL |
|-----------|-----|
| Console Admin | `https://IP_VM:7071` |
| Webmail | `https://IP_VM` |

**Identifiants admin :**
- Login : `admin@ministere.test`
- Mot de passe : celui défini à l'étape 3.6

---

## 4. Dépannage Commun

### Problème : Archive .tgz impossible à extraire (caractères invisibles)

**Symptôme** : `tar: No such file or directory`

**Solution** :
```bash
mv *.tgz zimbra.tgz
tar xzvf zimbra.tgz
```

Si `mv *.tgz` échoue aussi :
```bash
ls -i                   # Notez le numéro inode (ex: 123456)
find . -inum 123456 -exec mv {} zimbra.tgz \;
```

---

### Problème : Erreur resolvconf lors de l'installation (Ubuntu 22.04)

**Symptôme** : `Package resolvconf is not configured yet`

**Solution** :
```bash
sudo chattr -i /etc/resolv.conf
sudo dpkg --configure resolvconf
sudo dpkg --configure -a
sudo apt -f install -y
```

Puis relancez l'installateur :
```bash
sudo ./install.sh
```

---

### Problème : Échec de connexion à la console admin

**Symptôme** : `Authentication failed`

**Cause** : L'identifiant doit être l'adresse email complète, pas le nom d'utilisateur système.

**Solution** : Utilisez `admin@ministere.test` (et non `admin` ou `tolokoum`).

---

### Problème : Services Zimbra qui ne démarrent pas

**Symptôme** : Certains services affichent `Stopped` après `zmcontrol status`

**Causes possibles** :
- RAM insuffisante (moins de 8 Go)
- Port 25 occupé par un autre service

**Solution** :
```bash
# Vérifier la RAM disponible
free -h

# Vérifier les ports
sudo ss -tlnp | grep :25

# Redémarrer tous les services Zimbra
sudo su - zimbra
zmcontrol stop
zmcontrol start
zmcontrol status
```

---

### Problème : Erreur "Notification failed" en fin d'installation

**Symptôme** : `ERROR: Notification failed`

**Cause** : Zimbra tente d'envoyer un rapport à ses serveurs via Internet.

**Solution** : Ignorez cette erreur. Elle n'affecte pas le fonctionnement du serveur.

---

### Commandes utiles après installation

```bash
# Passer en utilisateur zimbra
sudo su - zimbra

# Vérifier l'état des services
zmcontrol status

# Redémarrer tous les services
zmcontrol restart

# Lister tous les comptes
zmprov -l gaa ministere.test

# Créer un compte utilisateur
zmprov ca user1@ministere.test MotDePasse123

# Voir les logs en temps réel
tail -f /opt/zimbra/log/mailbox.log
```

---

## 📝 Notes importantes

| Point | Détail |
|-------|--------|
| **Même domaine** | Conserver `ministere.test` sur les deux serveurs facilite la migration |
| **RAM** | En dessous de 8 Go, les services LDAP et mailboxd risquent de ne pas démarrer |
| **Certificat SSL** | Zimbra génère un certificat auto-signé. Le navigateur affichera une alerte de sécurité — c'est normal en environnement de test |
| **Port 7071** | Réservé exclusivement à la console d'administration |
| **zimbra-dnscache** | Ne **jamais** installer sur Ubuntu 22.04 — conflit DNS garanti |

---

> Ce guide a été rédigé dans le cadre d'un projet de Master 2 en Ingénierie Informatique à l'ENSPY (École Nationale Supérieure Polytechnique de Yaoundé), portant sur la migration de serveurs de messagerie et la sécurité post-quantique des protocoles de communication.
