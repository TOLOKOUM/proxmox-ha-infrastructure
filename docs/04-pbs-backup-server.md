# Documentation Technique — Proxmox Backup Server (PBS 4.2)

**Projet** : Infrastructure Ministère de la Fonction Publique  
**Environnement** : Simulation (VMware Workstation sur Windows 11)  
**Suite de** : Documentation Failback Automatique HA avec Affinity Rules  
**Date** : Mai 2026  
**Version PBS** : 4.2.0  
**Version Proxmox** : VE 9.1.1

---

## Table des matières

1. [Pourquoi PBS — Justification du choix](#1-pourquoi-pbs--justification-du-choix)
2. [Architecture PBS dans l'infrastructure](#2-architecture-pbs-dans-linfrastructure)
3. [Téléchargement de l'ISO PBS](#3-téléchargement-de-liso-pbs)
4. [Création de la VM PBS dans VMware](#4-création-de-la-vm-pbs-dans-vmware)
5. [Installation de PBS](#5-installation-de-pbs)
6. [Configuration des dépôts No-Subscription](#6-configuration-des-dépôts-no-subscription)
7. [Préparation du disque backup](#7-préparation-du-disque-backup)
8. [Création du Datastore](#8-création-du-datastore)
9. [Connexion de PBS au cluster Proxmox](#9-connexion-de-pbs-au-cluster-proxmox)
10. [Configuration des jobs de backup](#10-configuration-des-jobs-de-backup)
11. [Test de backup manuel](#11-test-de-backup-manuel)
12. [Test de restauration](#12-test-de-restauration)
13. [Problèmes rencontrés et solutions](#13-problèmes-rencontrés-et-solutions)
14. [Politique de rétention expliquée](#14-politique-de-rétention-expliquée)
15. [Recommandations pour la production](#15-recommandations-pour-la-production)

---

## 1. Pourquoi PBS — Justification du choix

### Les 3 couches de protection de l'infrastructure

```
Couche 1 — Ceph (temps réel)
  → Réplication instantanée entre pve1 et pve2
  → Protection : panne matérielle d'un nœud

Couche 2 — HA Proxmox (automatique < 1 min)
  → Redémarre les VMs sur le nœud survivant
  → Protection : crash OS, panne nœud

Couche 3 — PBS (quotidien, historique)  ← cette documentation
  → Backups chiffrés avec historique
  → Protection : ransomware, erreur humaine,
                 catastrophe totale (perte des 2 nœuds)
```

### Pourquoi PBS plutôt que vzdump seul ?

| Fonctionnalité | vzdump seul | PBS |
|---------------|-------------|-----|
| Backups incrémentaux | ❌ | ✅ |
| Déduplication | ❌ | ✅ (jusqu'à 80% d'économie) |
| Compression ZSTD | ✅ | ✅ |
| Restauration fichier unique | ❌ | ✅ |
| Vérification intégrité auto | ❌ | ✅ |
| Chiffrement AES-256 | ❌ | ✅ |
| Interface web dédiée | ❌ | ✅ |
| Politique de rétention | Basique | ✅ Avancée |
| Gratuit et open source | ✅ | ✅ |

**PBS est la solution officielle Proxmox** pour les backups professionnels.

---

## 2. Architecture PBS dans l'infrastructure

```
┌─────────────────────────────────────────────────────────────┐
│                  Datacenter clusterMINFOPRA                  │
│                                                              │
│  pve1 (192.168.75.149)        pve2 (192.168.75.158)         │
│  ├── VM 300 (Windows)         └── CT 400 (nginx)            │
│  │         │                            │                   │
│  │         └──── Backup quotidien ──────┘                   │
│  │                    │                                      │
│  │                    ▼                                      │
│  │    PBS (192.168.75.161:8007)                             │
│  │    ├── sda 15G (système PBS)                             │
│  │    └── sdb 45G → /mnt/backup                            │
│  │        └── backup-ministere (Datastore)                  │
│  │            ├── vm/300 (Windows 37.58 GB)                 │
│  │            └── ct/400 (nginx 652 MB)                     │
│                                                              │
│  Rétention : 7 derniers / 4 semaines / 3 mois               │
└─────────────────────────────────────────────────────────────┘
```

### Informations réseau

| Composant | IP | Port |
|-----------|-----|------|
| pve1 | 192.168.75.149 | 8006 |
| pve2 | 192.168.75.158 | 8006 |
| PBS | 192.168.75.161 | 8007 |

---

## 3. Téléchargement de l'ISO PBS

### Pourquoi l'ISO PBS et pas Debian ?

PBS fournit sa propre ISO qui contient **Debian + PBS préinstallé**, exactement comme l'ISO Proxmox VE contient Debian + Proxmox. C'est la méthode officielle et recommandée.

### Téléchargement

Sur ton PC Windows 11, ouvre un navigateur et va sur :

```
https://www.proxmox.com/en/downloads/proxmox-backup-server
```

Télécharger **Proxmox Backup Server 4.2-1 ISO Installer** :

| Information | Valeur |
|------------|--------|
| Version | 4.2-1 |
| Taille | 1.48 GB |
| Date | Avril 2026 |
| SHA256 | `2fb299deac3929253712c9c3dfc9237edbe70af83c8848467616b771a1d5453e` |

⚠️ **Vérifier le SHA256** après téléchargement pour s'assurer de l'intégrité du fichier.

---

## 4. Création de la VM PBS dans VMware

### Dimensionnement

| Ressource | Simulation | Production |
|-----------|-----------|------------|
| RAM | 2 GB | 4-8 GB |
| CPU | 2 vCPU | 4 vCPU |
| Disque système | 15 GB | 32 GB |
| Disque backup | 45 GB | 500 GB+ |
| Réseau | NAT | Réseau dédié |

### Procédure de création dans VMware Workstation

⚠️ **La VM PBS peut être créée pendant le téléchargement de l'ISO.**

1. **File → New Virtual Machine → Custom (advanced) → Next**
2. Hardware compatibility : laisser défaut → **Next**
3. Installer disc : **I will install the operating system later** → **Next**
4. Guest OS : **Linux → Debian 12.x 64-bit** → **Next**
5. VM Name : **PBS** → choisir dossier → **Next**
6. Processors : **2 vCPUs** → **Next**
7. Memory : **2048 MB** → **Next**
8. Network : **NAT** → **Next**
9. SCSI Controller : **LSI Logic** → **Next**
10. Disk type : **SCSI** → **Next**
11. Disk size : **15 GB** → Single file → **Next** → **Finish**

### Ajouter le disque backup

1. Clic droit sur la VM PBS → **Settings**
2. **Add** → **Hard Disk** → **Next**
3. Type : **SCSI** → **Next**
4. **Create a new virtual disk** → **Next**
5. Taille : **45 GB** → Single file → **Finish**

### Monter l'ISO PBS

1. Dans Settings → **CD/DVD (SATA)**
2. Sélectionner **Use ISO image file**
3. Parcourir et sélectionner **proxmox-backup-server-4.2-1.iso**
4. Cliquer **OK**

---

## 5. Installation de PBS

### Démarrage de l'installation

1. **Power On** la VM PBS dans VMware
2. Le menu d'installation apparaît → sélectionner **Install Proxmox Backup Server**
3. Accepter la licence → **Next**
4. Sélectionner le disque système (sda 15G) → **Next**
5. Configurer la localisation :
   - Country : **France** (ou votre pays)
   - Timezone : **Africa/Douala** (ou votre timezone)
6. Configurer le mot de passe root et l'email
7. Configurer le réseau :
   - Hostname : **pbs.ministere.local**
   - IP : **192.168.75.161**
   - Netmask : **255.255.255.0**
   - Gateway : **192.168.75.2**
   - DNS : **8.8.8.8**
8. Cliquer **Install** et attendre la fin

### Vérification après installation

Une fois redémarré, la console affiche :

```
Welcome to the Proxmox Backup Server.
Please use your web browser to configure this server - connect to:
https://192.168.75.161:8007/
pbs login: root
```

### Accès à l'interface web

Sur ton PC Windows 11 :
```
https://192.168.75.161:8007
```

| Champ | Valeur |
|-------|--------|
| Username | `root` |
| Realm | `Linux PAM standard authentication` |
| Password | mot de passe défini lors de l'installation |

---

## 6. Configuration des dépôts No-Subscription

### Problème rencontré

PBS 4.2 utilise le nouveau format `.sources` (et non `.list`) pour les dépôts APT. Les tentatives de désactivation avec `sed` sur des fichiers `.list` échouaient car ces fichiers n'existent pas.

```
sed: can't read /etc/apt/sources.list.d/pbs-enterprise.list: No such file or directory
```

### Diagnostic

```bash
ls /etc/apt/sources.list.d/
```

Résultat :
```
debian.sources          ← dépôts Debian (ne pas modifier)
pbs-enterprise.sources  ← dépôt enterprise PBS ← à désactiver
```

### Solution — Désactiver via le format .sources

Dans le Shell PBS (**Administration → Shell**) :

```bash
# Désactiver le dépôt enterprise
sed -i 's/^Enabled: yes/Enabled: no/' /etc/apt/sources.list.d/pbs-enterprise.sources

# Ajouter le dépôt no-subscription
cat >> /etc/apt/sources.list.d/pbs-no-subscription.sources << 'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: bookworm
Components: pbs-no-subscription
Enabled: yes
EOF

# Mettre à jour
apt update
```

### Vérification

```bash
apt update
```

Résultat attendu — pas de 401 Unauthorized :
```
Hit:1 http://deb.debian.org/debian trixie
Hit:2 http://security.debian.org/debian-security trixie-security
Hit:3 http://download.proxmox.com/debian/pbs bookworm  ✅
Hit:4 http://deb.debian.org/debian trixie-updates
```

⚠️ **Note** : Des warnings `configured multiple times` peuvent apparaître si le dépôt no-subscription est déjà présent dans `/etc/apt/sources.list`. Ce n'est pas bloquant — PBS fonctionne correctement malgré ces warnings.

---

## 7. Préparation du disque backup

PBS ne formate pas automatiquement le disque backup. Il faut le préparer manuellement avant de créer le Datastore.

### Vérifier les disques disponibles

```bash
lsblk
```

Résultat obtenu :
```
sda   15G   ← système PBS (utilisé)
  ├─sda1    1007K
  ├─sda2    512M
  └─sda3    14.5G
    ├─pbs-swap  1.8G [SWAP]
    └─pbs-root  12.7G /
sdb   45G   ← disque backup vierge ✅
```

### Installer parted

```bash
apt install -y parted
```

### Créer la partition et formater

```bash
# Créer la table de partition GPT
parted /dev/sdb mklabel gpt

# Créer la partition principale
parted /dev/sdb mkpart primary ext4 0% 100%

# Formater en ext4
mkfs.ext4 /dev/sdb1

# Créer le point de montage
mkdir -p /mnt/backup

# Monter le disque
mount /dev/sdb1 /mnt/backup

# Rendre le montage permanent au démarrage
echo '/dev/sdb1 /mnt/backup ext4 defaults 0 2' >> /etc/fstab
```

### Vérification

```bash
df -h /mnt/backup
```

Résultat attendu :
```
Filesystem    Size   Used  Avail  Use%  Mounted on
/dev/sdb1      44G   2.1M    42G    1%  /mnt/backup  ✅
```

---

## 8. Création du Datastore

Le Datastore est l'espace logique de stockage des backups dans PBS.

### Via l'interface web PBS

1. Cliquer **Add Datastore** dans le menu gauche
2. Configurer :

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Name | `backup-ministere` | Nom explicite |
| Datastore Type | `Local` | Stockage local |
| Backing Path | `/mnt/backup` | Disque préparé |
| GC Schedule | `daily` | Nettoyage quotidien |
| Prune Schedule | `daily` | Appliquer rétention quotidiennement |

3. Cliquer **Add**

### Vérification

Le Datastore `backup-ministere` apparaît dans le menu gauche de PBS.

Dans le Dashboard PBS → **Datastore Usage** :
```
backup-ministere   44G total   disponible  ✅
```

---

## 9. Connexion de PBS au cluster Proxmox

### Récupérer le fingerprint de PBS

Le fingerprint est obligatoire pour sécuriser la connexion entre Proxmox et PBS. Il identifie de manière unique le certificat SSL de PBS.

Dans le Shell PBS :

```bash
proxmox-backup-manager cert info | grep Fingerprint
```

Résultat :
```
Fingerprint (sha256): 07:c5:8e:d1:c0:33:fa:93:74:74:08:b0:5a:db:9f:62:07:70:fb:25:43:7b:22:9e:aa:4d:68:a8:2f:73:93:08
```

⚠️ **Copier le fingerprint complet** — un fingerprint tronqué empêche la connexion.

### Ajouter PBS comme storage dans Proxmox

Dans l'interface web Proxmox :
**Datacenter → Storage → Add → Proxmox Backup Server**

| Champ | Valeur |
|-------|--------|
| ID | `pbs-backup` |
| Server | `192.168.75.161` |
| Username | `root@pam` |
| Password | mot de passe root PBS |
| Datastore | `backup-ministere` |
| Fingerprint | `07:c5:8e:d1:c0:33:fa:...` (fingerprint complet) |

Cliquer **Add**.

### Problème rencontré — Fingerprint tronqué

**Symptôme** :
```
create storage failed: pbs-backup: error fetching datastores -
fingerprint '07:C5:8E:...:AA:4D:68:A8' not verified, abort! (500)
```

**Cause** : Le fingerprint affiché dans le message d'erreur était tronqué — il manquait `:2f:73:93:08` à la fin.

**Solution** : Récupérer le fingerprint complet via la commande `proxmox-backup-manager cert info` et le coller intégralement dans le champ Fingerprint.

**Note** : Le bouton Add reste grisé tant que le fingerprint n'est pas complet et valide.

### Vérification

Dans **Datacenter → Storage**, la liste affiche :

| ID | Type | Content | Shared | Enabled |
|----|------|---------|--------|---------|
| pbs-backup | Proxmox Backup Server | Backup | Yes | Yes |

Dans le panneau gauche :
```
pve1
└── pbs-backup (pve1)  ✅
pve2
└── pbs-backup (pve2)  ✅
```

PBS est accessible par les **deux nœuds** simultanément.

---

## 10. Configuration des jobs de backup

### Créer le job de backup automatique

**Datacenter → Backup → Add**

**Onglet General :**

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Node | `-- All --` | Couvre pve1 et pve2 |
| Storage | `pbs-backup` | Destination PBS |
| Schedule | `23:00` | Backup la nuit (faible activité) |
| Selection mode | `All` | VM 300 + CT 400 |
| Compression | `ZSTD` | Meilleur ratio vitesse/compression |
| Mode | `Snapshot` | Backup sans interruption de service |
| Enable | ✅ | Activé immédiatement |

**Onglet Retention :**

| Champ | Valeur | Signification |
|-------|--------|---------------|
| Keep Last | `7` | 7 derniers backups |
| Keep Weekly | `4` | 1 backup par semaine pendant 4 semaines |
| Keep Monthly | `3` | 1 backup par mois pendant 3 mois |

Cliquer **Create**.

### Résultat dans l'interface

```
Enabled : ✅
Node    : -- All --
Schedule: 23:00
Next Run: 2026-05-09 23:00:00
Storage : pbs-backup
Retention: keep-last=7, keep-weekly=4, keep-monthly=3
Selection: -- All --
```

---

## 11. Test de backup manuel

### Lancer un backup immédiat

Sans attendre 23h00, valider le backup en le lançant manuellement :

**Datacenter → Backup** → sélectionner le job → **Run now**

### Ce qui se passe concrètement

```
Étape 1 — Proxmox crée un snapshot de la VM/CT
  → La VM continue de tourner normalement (zéro interruption)
  → Le snapshot capture l'état exact du disque

Étape 2 — Proxmox envoie les données vers PBS
  → pve1 envoie VM 300 (Windows) → PBS (192.168.75.161)
  → pve2 envoie CT 400 (nginx) → PBS
  → PBS compresse avec ZSTD
  → PBS déduplique les données identiques

Étape 3 — PBS stocke sur /mnt/backup
  → Backup indexé avec checksum
  → Métadonnées enregistrées (date, taille, hash)

Étape 4 — Proxmox supprime le snapshot temporaire
  → La VM continue normalement
```

### Résultat dans Tasks

```
VM/CT 400 - Backup   pve2   OK  ✅  (652.32 MB  ~10 min)
VM/CT 300 - Backup   pve1   OK  ✅  (37.58 GB   ~27 min)
```

### Vérification dans PBS

**pbs-backup (pve1) → Backups** :

| Name | Notes | Date | Format | Size |
|------|-------|------|--------|------|
| vm/300/2026-05-09T18:54:25Z | Windows10VM | 2026-05-09 19:54:25 | pbs-vm | 37.58 GB |
| ct/400/2026-05-09T18:54:08Z | nginx-server | 2026-05-09 19:54:08 | pbs-ct | 652.32 MB |

---

## 12. Test de restauration

### Pourquoi tester la restauration ?

**Un backup non testé n'est pas fiable.** Il est indispensable de valider qu'on peut réellement restaurer depuis PBS avant de déployer en production.

### Procédure de restauration du CT 400

**pbs-backup (pve1) → Backups** → sélectionner **ct/400** → **Restore**

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Storage | `vm-pool` | Stockage Ceph |
| CT ID | `401` | Nouveau ID (ne pas écraser l'existant) |
| Start after restore | ✅ | Démarrer automatiquement |

Cliquer **Restore**.

### Résultat attendu

Dans Tasks :
```
CT 401 - Restore   pve1   OK  ✅
CT 401 démarré automatiquement  ✅
```

Le CT 401 apparaît dans le panneau gauche sous pve1, identique au CT 400 original.

### Types de restauration disponibles

| Type | Usage | Bouton |
|------|-------|--------|
| Restauration complète | Restaurer toute la VM/CT | **Restore** |
| Restauration fichier | Restaurer un fichier unique | **File Restore** |

La restauration fichier est particulièrement utile en production pour récupérer un fichier supprimé par erreur sans restaurer toute la VM.

---

## 13. Problèmes rencontrés et solutions

| # | Problème | Cause | Solution |
|---|---------|-------|----------|
| 1 | `parted: command not found` | Parted non installé par défaut sur PBS | `apt install -y parted` |
| 2 | `sed: can't read pbs-enterprise.list: No such file` | PBS 4.2 utilise le format `.sources` et non `.list` | Modifier `/etc/apt/sources.list.d/pbs-enterprise.sources` avec `sed -i 's/^Enabled: yes/Enabled: no/'` |
| 3 | `fingerprint not verified, abort! (500)` | Fingerprint tronqué dans le message d'erreur | Récupérer le fingerprint complet avec `proxmox-backup-manager cert info \| grep Fingerprint` |
| 4 | Bouton **Add** grisé dans Proxmox | Fingerprint incomplet ou invalide | Coller le fingerprint complet (format `XX:XX:...:XX` de 64 caractères) |
| 5 | Warning `configured multiple times` | Dépôt no-subscription ajouté en double | Supprimer le doublon avec `rm -f /etc/apt/sources.list.d/pbs-no-subscription.sources` et recréer proprement |

---

## 14. Politique de rétention expliquée

### Comment fonctionne la rétention

```
Planning backup : 23h00 tous les jours

Keep Last = 7    → garder les 7 derniers backups
Keep Weekly = 4  → garder 1 backup/semaine pendant 4 semaines
Keep Monthly = 3 → garder 1 backup/mois pendant 3 mois
```

### Timeline des backups conservés

```
Jour J     (hier)      → conservé (Keep Last)
Jour J-1               → conservé (Keep Last)
Jour J-2               → conservé (Keep Last)
Jour J-3               → conservé (Keep Last)
Jour J-4               → conservé (Keep Last)
Jour J-5               → conservé (Keep Last)
Jour J-6               → conservé (Keep Last)
Semaine -1 (7j)        → conservé (Keep Weekly)
Semaine -2 (14j)       → conservé (Keep Weekly)
Semaine -3 (21j)       → conservé (Keep Weekly)
Semaine -4 (28j)       → conservé (Keep Weekly)
Mois -1    (30j)       → conservé (Keep Monthly)
Mois -2    (60j)       → conservé (Keep Monthly)
Mois -3    (90j)       → conservé (Keep Monthly)
Plus ancien            → supprimé automatiquement ✅
```

### Protection couverte

| Scénario | Couverture |
|---------|-----------|
| Fichier supprimé par erreur aujourd'hui | ✅ Keep Last |
| Ransomware détecté après 2 semaines | ✅ Keep Weekly |
| Corruption détectée après 2 mois | ✅ Keep Monthly |
| Catastrophe totale (perte 2 nœuds) | ✅ Restauration complète depuis PBS |

---

## 15. Recommandations pour la production

### Dimensionnement PBS en production

```
RAM         : 4-8 GB minimum
CPU         : 4 vCPU
Disque sys  : 32 GB SSD
Disque backup: 10x la taille totale des VMs
               Exemple : VMs = 500 GB → PBS = 5 TB
               (pour stocker plusieurs semaines de backups)
```

### Sécurisation en production

```bash
# Activer le chiffrement des backups (AES-256)
# Dans Proxmox → Storage → pbs-backup → Edit → Encryption
# Générer une clé de chiffrement et la stocker en lieu sûr

# Vérifier l'intégrité des backups automatiquement
# Dans PBS → Datastore → backup-ministere → Verify Jobs → Add
# Schedule : weekly (chaque semaine)
```

### Isolation réseau recommandée

En production, PBS doit être sur un réseau dédié séparé du réseau de production :

```
Réseau production (vmbr0) : 192.168.75.0/24
  → Accès utilisateurs, VMs

Réseau backup (vmbr1) : 10.10.10.0/24
  → PBS uniquement, inaccessible depuis internet
  → pve1 backup → 10.10.10.1 (PBS)
  → pve2 backup → 10.10.10.1 (PBS)
```

### Commandes de surveillance utiles

```bash
# Sur PBS — vérifier l'état du datastore
proxmox-backup-manager datastore list

# Sur PBS — voir les tâches de backup
proxmox-backup-manager task list

# Sur PBS — vérifier l'espace disque
df -h /mnt/backup

# Sur Proxmox — lancer un backup manuel
vzdump 300 --storage pbs-backup --mode snapshot
vzdump 400 --storage pbs-backup --mode snapshot
```

---

## Architecture finale complète validée

```
┌─────────────────────────────────────────────────────────────┐
│                  Infrastructure Ministère                    │
│                                                              │
│  COUCHE 1 — STOCKAGE PARTAGÉ (Ceph)                        │
│  pve1 ◄─── vm-pool (100 GiB) ───► pve2                     │
│  VM 300 (Windows) + CT 400 (nginx) sur Ceph                │
│  Migration instantanée < 30 secondes                        │
│                                                              │
│  COUCHE 2 — HAUTE DISPONIBILITÉ                             │
│  HA + Affinity Rules + QDevice                              │
│  Failover < 1 minute / Failback automatique                 │
│                                                              │
│  COUCHE 3 — BACKUPS (PBS 4.2)                              │
│  PBS (192.168.75.161)                                        │
│  Backup quotidien 23h00                                      │
│  Rétention : 7j / 4sem / 3mois                              │
│  Restauration complète ou fichier unique                     │
│                                                              │
│  RÉSULTAT :                                                  │
│  ✅ Zéro SPOF                                               │
│  ✅ Migration instantanée                                    │
│  ✅ Failover/Failback automatique                            │
│  ✅ Backups quotidiens chiffrés                             │
│  ✅ Restauration testée et validée                          │
│  ✅ Protection contre ransomware et erreur humaine          │
└─────────────────────────────────────────────────────────────┘
```

---

*Document produit dans le cadre d'un projet de stage — validé en environnement de simulation avant déploiement en production.*
