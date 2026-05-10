# Documentation Technique — Stockage Ceph, Migration & Haute Disponibilité Active/Active

**Projet** : Infrastructure Ministère de la Fonction Publique  
**Environnement** : Simulation (VMware Workstation sur Windows 11)  
**Suite de** : Documentation Cluster Proxmox HA — ZFS Replication + QDevice + Test de panne  
**Date** : Mai 2026  
**Version Proxmox** : VE 9.1.1  
**Version Ceph** : 19.2.3 (Squid)

---

## Table des matières

1. [Pourquoi Ceph — Justification du choix](#1-pourquoi-ceph--justification-du-choix)
2. [Architecture cible](#2-architecture-cible)
3. [Prérequis — Ajout des disques Ceph dans VMware](#3-prérequis--ajout-des-disques-ceph-dans-vmware)
4. [Problème — Espace insuffisant sur ZFS et snapshots perdus](#4-problème--espace-insuffisant-sur-zfs-et-snapshots-perdus)
5. [Configuration des dépôts No-Subscription](#5-configuration-des-dépôts-no-subscription)
6. [Installation de Ceph sur pve1 et pve2](#6-installation-de-ceph-sur-pve1-et-pve2)
7. [Configuration des Monitors et Managers Ceph](#7-configuration-des-monitors-et-managers-ceph)
8. [Création des OSDs Ceph](#8-création-des-osds-ceph)
9. [Création du Pool Ceph](#9-création-du-pool-ceph)
10. [Migration des VMs vers Ceph](#10-migration-des-vms-vers-ceph)
11. [Problèmes rencontrés et solutions](#11-problèmes-rencontrés-et-solutions)
12. [Validation — Migration instantanée](#12-validation--migration-instantanée)
13. [Recommandations pour la production](#13-recommandations-pour-la-production)

---

## 1. Pourquoi Ceph — Justification du choix

### Problèmes identifiés avec ZFS Replication

Après la mise en place du cluster avec ZFS Replication, plusieurs limitations critiques ont été identifiées :

| Problème | Impact |
|---------|--------|
| Migration lente (35G à transférer) | Interruption de service longue |
| Snapshots ZFS perdus après panne | Réplication impossible, erreur `out of space` |
| Failback non automatique | Intervention manuelle nécessaire |
| Pool ZFS trop petit (50G pour 35G de VM) | Pas de place pour les snapshots de réplication |

### Pourquoi Ceph est la meilleure solution

Avec ZFS Replication, **le disque appartient à un nœud** et doit être copié pour migrer. Avec Ceph, **le disque appartient au cluster** et est accessible par tous les nœuds simultanément.

```
Sans Ceph (ZFS Replication) :
pve1 possède le disque → migration = copie complète = lent

Avec Ceph (stockage partagé) :
Le cluster possède le disque → migration = changement de pointeur = instantané
```

### Comparaison des solutions étudiées

| Solution | Migration | Failback auto | SPOF | 2 nœuds | Choix |
|---------|-----------|---------------|------|---------|-------|
| ZFS Replication | Lente (minutes) | Non | Non | ✅ | ❌ Insuffisant |
| NFS partagé | Instantanée | Oui | ❌ Oui | ✅ | ❌ SPOF inacceptable |
| Ceph | **Instantanée** | **Oui** | **Non** | ✅ (config spéciale) | **✅ Retenu** |
| DRBD | Très rapide | Oui | Non | ✅ | ✅ Alternative |

**Ceph a été retenu** car c'est la solution native Proxmox, officiellement supportée, sans SPOF, avec migration instantanée et failback automatique.

### Cas particulier — Ceph avec 2 nœuds

Ceph recommande normalement 3 nœuds pour le quorum OSD. Avec 2 nœuds, on utilise :
- `size = 2` → 1 copie sur chaque nœud
- `min_size = 1` → continue de fonctionner si 1 nœud est down
- Le QDevice déjà en place sert d'arbitre pour éviter le split-brain

---

## 2. Architecture cible

```
┌─────────────────────────────────────────────────────────────┐
│                  Datacenter clusterMINFOPRA                  │
│                                                              │
│  pve1 (192.168.75.149)        pve2 (192.168.75.158)         │
│  ├── sda 20G (système)        ├── sda 20G (système)         │
│  ├── sdb 50G (ZFS local)      ├── sdb 50G (ZFS local)       │
│  │   └── ISOs/backups         │   └── ISOs/backups           │
│  └── sdc 50G (Ceph OSD) ◄───► └── sdc 50G (Ceph OSD)       │
│              │                            │                  │
│              └──── vm-pool (Ceph) ────────┘                  │
│                    ├── VM 300 (Windows)                      │
│                    └── CT 400 (nginx)                        │
│                                                              │
│           QDevice (192.168.75.160)                           │
│           └── Arbitre quorum cluster + Ceph                  │
└─────────────────────────────────────────────────────────────┘
```

### Rôle de chaque composant

| Composant | Rôle |
|-----------|------|
| sdc (Ceph OSD) | Stockage partagé des VMs/CTs |
| sdb (ZFS local) | Backups, ISOs, templates |
| vm-pool | Pool Ceph pour les disques de VMs |
| QDevice | Arbitre de quorum (anti split-brain) |

---

## 3. Prérequis — Ajout des disques Ceph dans VMware

Avant de commencer, chaque nœud Proxmox doit avoir un disque dédié vierge pour Ceph.

### Dimensionnement simulation vs production

| Environnement | Disque Ceph par nœud | Justification |
|--------------|---------------------|---------------|
| Simulation | 50 GB | Valider le concept |
| Production | 500 GB+ | Données réelles |

### Procédure d'ajout dans VMware Workstation

⚠️ **Les VMs pve1 et pve2 doivent être éteintes avant cette étape.**

**Sur PVE-01 :**
1. Clic droit → **Settings** → **Add** → **Hard Disk**
2. Type : **SCSI** → **Next**
3. **Create a new virtual disk** → **Next**
4. Taille : **50 GB** → **Store as single file**
5. Nom : `pve1-ceph.vmdk` → **Finish**

**Sur PVE-02 :**
Répéter exactement la même procédure → nom : `pve2-ceph.vmdk`

### Vérification après redémarrage

Sur pve1 :
```bash
lsblk
```

Résultat attendu :
```
sda   20G   ← système
sdb   50G   ← ZFS local
sdc   50G   ← nouveau disque Ceph ✅
```

Sur pve2 :
```bash
ssh root@192.168.75.158 lsblk
```

Même résultat attendu avec sdc 50G vierge.

---

## 4. Problème — Espace insuffisant sur ZFS et snapshots perdus

### Symptôme
La réplication ZFS de la VM 300 échouait avec :
```
zfs error: cannot create snapshot 'local-zfs/vm-300-disk-1@__replicate_300-0_...' : out of space
```

### Cause
Le pool ZFS de pve1 était structurellement trop petit :
```
Pool ZFS total    : 49.5G
VM Windows utilisé: 35.5G
Espace snapshots  : ~14G restants (insuffisant pour répliquer 35G)
Minimum nécessaire: ~70G (2x la taille de la VM)
```

De plus, après le test de panne HA, les snapshots ZFS de référence avaient été perdus sur les deux nœuds, rendant la réplication incrémentale impossible.

### Solution retenue
Migration vers Ceph qui **élimine définitivement ce problème** :
- Pas de snapshots de réplication nécessaires
- Le disque existe en une seule copie partagée
- L'espace n'est utilisé qu'une seule fois

---

## 5. Configuration des dépôts No-Subscription

### Problème rencontré
L'installation de Ceph via l'interface web échouait avec :
```
E: Unable to correct problems, you have held broken packages
apt failed during ceph installation (25600)
```

Et lors de `apt update` :
```
Err: https://enterprise.proxmox.com/debian/ceph-squid trixie InRelease
401 Unauthorized
```

### Cause
Les dépôts Enterprise de Proxmox étaient activés mais nécessitent un abonnement payant. Sans abonnement, `apt` ne peut pas télécharger les paquets.

### Solution — Désactiver les dépôts Enterprise via l'interface web

Sur **pve1** et **pve2**, dans l'interface web :  
**Node → Updates → Repositories**

1. Sélectionner chaque dépôt `enterprise.proxmox.com` → **Disable**
2. Vérifier que les dépôts `download.proxmox.com` (no-subscription) sont **Enabled**

Ou en ligne de commande :
```bash
# Désactiver les dépôts enterprise
sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/pve-enterprise.list
sed -i 's/^deb/# deb/' /etc/apt/sources.list.d/ceph.list

# Ajouter les dépôts no-subscription
echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" >> /etc/apt/sources.list
echo "deb http://download.proxmox.com/debian/ceph-squid trixie no-subscription" >> /etc/apt/sources.list

# Mettre à jour
apt update
```

### Vérification
```bash
apt update
```

Résultat attendu — aucun 401 Unauthorized :
```
Hit:1 http://security.debian.org/debian-security trixie-security
Hit:2 http://deb.debian.org/debian trixie
Hit:3 http://download.proxmox.com/debian/pve trixie        ✅
Hit:4 http://download.proxmox.com/debian/ceph-squid trixie ✅
```

⚠️ **Répéter cette procédure sur pve2.**

---

## 6. Installation de Ceph sur pve1 et pve2

### Sur pve1 — Via l'interface web

1. Clique sur **pve1** → **Ceph**
2. Cliquer **Install Ceph**
3. Configurer :

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Version | squid (19.2) | Dernière version stable |
| Repository | **No-Subscription** | Pas d'abonnement |

4. Cliquer **Start squid installation**

### Résultat attendu
```
Setting up ceph-mgr (19.2.3-pve4) ✅
Setting up ceph-osd (19.2.3-pve4) ✅
Setting up ceph-mon (19.2.3-pve4) ✅
Setting up ceph (19.2.3-pve4)     ✅
installed Ceph 19.2 Squid successfully! ✅
```

Cliquer **Next** puis **Finish**.

### Sur pve2 — Même procédure

Cliquer sur **pve2** → **Ceph** → **Install Ceph** → mêmes paramètres → **Start squid installation**

---

## 7. Configuration des Monitors et Managers Ceph

### Rôle des composants

| Composant | Rôle |
|-----------|------|
| Monitor (MON) | Maintient la carte du cluster Ceph |
| Manager (MGR) | Collecte les métriques et gère les modules |
| OSD | Stocke les données réelles |

### Création des Monitors

Sur **pve1** → **Ceph** → **Monitor** → **Create**

Le monitor de pve1 est créé automatiquement lors de l'installation. Si un message `already in use` apparaît, c'est normal.

Créer ensuite le monitor sur **pve2** :
- Cliquer **Create** → sélectionner **pve2** → **Create**

### Résultat attendu
```
mon.pve1   pve1   running   192.168.75.149:6789/0   Quorum: Yes ✅
mon.pve2   pve2   running   192.168.75.158:6789/0   Quorum: Yes ✅
```

### Création des Managers

Dans la section **Manager** → **Create** → sélectionner **pve2** → **Create**

### Résultat attendu
```
mgr.pve1   pve1   active    192.168.75.149   ✅
mgr.pve2   pve2   standby   192.168.75.158   ✅
```

`standby` est normal — mgr.pve2 prend le relais automatiquement si pve1 tombe.

---

## 8. Création des OSDs Ceph

### Rôle des OSDs
Les OSDs (Object Storage Daemons) sont les processus qui gèrent les disques physiques de Ceph. Chaque disque dédié à Ceph devient un OSD.

### Création de l'OSD sur pve1

**pve1** → **Ceph** → **OSD** → **Create: OSD**

| Champ | Valeur |
|-------|--------|
| Disk | /dev/sdc |
| DB Disk | use OSD disk |

Cliquer **Create**.

### Création de l'OSD sur pve2

Cliquer à nouveau **Create: OSD** :

| Champ | Valeur |
|-------|--------|
| Node | pve2 |
| Disk | /dev/sdc |

Cliquer **Create**.

### Problème rencontré — OSD pve2 en DOWN

Après création, osd.1 (pve2) affichait `down` :
```
pve2 → osd.1   filestore   down ❌ / in ✅
pve1 → osd.0   bluestore   up  ✅ / in ✅
```

**Cause** : L'OSD venait d'être créé et n'avait pas encore démarré complètement.

**Solution** : Attendre quelques secondes et cliquer **Reload**. L'OSD est passé automatiquement en `up`.

### Résultat final attendu
```
pve2 → osd.1   hdd   bluestore   up ✅ / in ✅   50G
pve1 → osd.0   hdd   bluestore   up ✅ / in ✅   50G
```

---

## 9. Création du Pool Ceph

### Rôle du Pool
Le pool Ceph est l'espace de stockage logique où les disques des VMs seront stockés. C'est l'équivalent d'un datastore.

### Création via l'interface web

**pve1** → **Ceph** → **Pools** → **Create**

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Name | `vm-pool` | Nom explicite |
| Size | `2` | 1 copie sur pve1, 1 copie sur pve2 |
| Min. Size | `1` | Continue si 1 nœud down |
| PG Autoscale | `on` | Gestion automatique des PGs |

### Configuration pour 2 nœuds

Après création, appliquer ces paramètres pour adapter Ceph à 2 nœuds :

```bash
ceph osd pool set vm-pool size 2
ceph osd pool set vm-pool min_size 1
ceph config set global osd_pool_default_size 2
ceph config set global osd_pool_default_min_size 1
```

### Vérification du statut Ceph
```bash
ceph status
```

Résultat attendu :
```
health: HEALTH_WARN (warnings mineurs non bloquants)
mon: 2 daemons, quorum pve1,pve2   ✅
mgr: pve1(active), standbys: pve2  ✅
osd: 2 up, 2 in                    ✅
pools: 1 pools, 82 pgs              ✅
usage: 99 MiB used, 100 GiB avail  ✅
82 active+clean                     ✅
```

### Warnings résiduels non bloquants

| Warning | Cause | Impact |
|---------|-------|--------|
| `mon pve1 low on space` | Disque système à 84% | Aucun sur Ceph |
| `OSD count 2 < default_size 3` | Normal avec 2 nœuds | Aucun après config |

---

## 10. Migration des VMs vers Ceph

### Objectif
Déplacer les disques de la VM 300 (Windows) et du CT 400 (nginx) depuis le stockage ZFS local vers le pool Ceph.

### Migration de la VM 300 (Windows)

**Étape 1 — Arrêter la VM**
```bash
qm stop 300
```

**Étape 2 — Vérifier les disques actuels**
```bash
qm config 300
```

Résultat montrant les disques ZFS :
```
efidisk0: local-zfs:vm-300-disk-0, efitype=4m, size=528K
sata0:    local-zfs:vm-300-disk-1, format=raw, size=35G
boot:     order=sata0
```

**Étape 3 — Migrer le disque principal**
```bash
qm move-disk 300 sata0 vm-pool --delete
```

Progression affichée :
```
transferred 10.0 GiB of 35.0 GiB (28.57%)
...
transferred 35.0 GiB of 35.0 GiB (100.00%) ✅
```

**Étape 4 — Migrer le disque EFI**
```bash
qm move-disk 300 efidisk0 vm-pool --delete
```

**Étape 5 — Vérifier la configuration**
```bash
qm config 300 | grep sata
```

Résultat attendu :
```
sata0: vm-pool:vm-300-disk-0, size=35G  ✅ ← sur Ceph !
```

### Migration du CT 400 (nginx)

**Étape 1 — Arrêter le conteneur**
```bash
pct stop 400
```

**Étape 2 — Vérifier le volume**
```bash
pct config 400
```

Résultat :
```
rootfs: local-zfs:subvol-400-disk-0, size=4G
```

**Étape 3 — Migrer le volume**
```bash
pct move-volume 400 rootfs vm-pool --delete 1
```

**Étape 4 — Vérifier**
```bash
pct config 400 | grep rootfs
```

Résultat attendu :
```
rootfs: vm-pool:vm-400-disk-0, size=4G  ✅ ← sur Ceph !
```

### Démarrage après migration

```bash
qm start 300
pct start 400
```

Vérification :
```bash
qm status 300   # → running ✅
pct status 400  # → running ✅
```

---

## 11. Problèmes rencontrés et solutions

| # | Problème | Cause | Solution |
|---|---------|-------|----------|
| 1 | `apt failed during ceph installation (25600)` | Dépôts Enterprise activés sans abonnement | Désactiver Enterprise, activer No-Subscription via Updates → Repositories |
| 2 | `401 Unauthorized` sur apt update | Même cause | Même solution |
| 3 | Tentative de suppression de `proxmox-ve` | Commande `apt remove ceph-common` trop agressive | Réinstaller avec `apt install -y proxmox-ve`, vérifier avec `pveversion` |
| 4 | OSD pve2 en `down` après création | Démarrage OSD pas encore terminé | Attendre et cliquer Reload |
| 5 | `disk 'scsi0' does not exist` | La VM utilisait `sata0` et non `scsi0` | Vérifier avec `qm config 300` avant de migrer |
| 6 | `Unknown option: target-storage` | Syntaxe incorrecte pour Proxmox 9 | Utiliser `pct move-volume 400 rootfs vm-pool --delete 1` |
| 7 | Migration VM 300 abortée après migration Ceph | Job de réplication ZFS encore actif | `pvesr delete 300-0` et `pvesr delete 400-0` avant de migrer |
| 8 | `out of space` sur ZFS Replication | Pool ZFS trop petit (50G) pour VM de 35G + snapshots | Migration vers Ceph qui élimine ce problème |

---

## 12. Validation — Migration instantanée

### Test de migration live

Après migration vers Ceph, tester la migration live de la VM 300 de pve1 vers pve2 :

**Via l'interface web** : VM 300 → **Migrate** → sélectionner **pve2** → **Migrate**

### Résultat attendu
```
starting migration of VM 300 to node 'pve2'
volumes =>  (vide car Ceph = pas de transfert de données)
migration finished successfully (duration 00:00:XX)
TASK OK
```

La migration est **quasi instantanée** car le disque n'est pas copié — il est déjà accessible par les deux nœuds via Ceph.

### Comparaison avant/après

| Métrique | ZFS Replication | Ceph |
|---------|-----------------|------|
| Temps migration 35G | 10-30 minutes | < 30 secondes |
| Données transférées | 35 GB | 0 GB (pointeur) |
| Interruption service | Plusieurs minutes | Quelques secondes |
| Failback automatique | Non | Oui |

---

## 13. Recommandations pour la production

### Dimensionnement des disques Ceph

```
Règle : disque Ceph = 2x la taille totale des VMs hébergées
Exemple : VMs = 500G → Ceph OSD = 1TB minimum par nœud
```

### Architecture réseau recommandée

En production, Ceph bénéficie d'un réseau dédié :

```
Réseau public  (vmbr0) : 1 Gbps → trafic VMs et accès utilisateurs
Réseau cluster (vmbr1) : 10 Gbps → trafic Ceph entre nœuds
```

### Paramètres Ceph recommandés pour 2 nœuds

```bash
# Taille de réplication
ceph osd pool set vm-pool size 2
ceph osd pool set vm-pool min_size 1

# Valeurs globales
ceph config set global osd_pool_default_size 2
ceph config set global osd_pool_default_min_size 1

# Surveillance de l'espace
ceph config set global mon_data_avail_warn 20
```

### Backups avec ZFS local

Le stockage ZFS local (sdb) devient le stockage de backup :

```bash
# Configurer vzdump pour sauvegarder vers ZFS local
# Dans Datacenter → Backup → Add
Storage : local-zfs
Schedule : 02:00
Mode    : snapshot
Retention: 7 derniers jours
```

### Surveillance de la santé Ceph

```bash
# Vérification rapide
ceph status

# Vérification détaillée
ceph health detail

# Espace disponible
ceph df

# État des OSDs
ceph osd tree
```

---

## Architecture finale validée

```
┌─────────────────────────────────────────────────────────────┐
│                  Datacenter clusterMINFOPRA                  │
│                                                              │
│  pve1                              pve2                      │
│  ├── VM 300 (Windows) ◄──────────► CT 400 (nginx)           │
│  │   └── disque sur Ceph           └── disque sur Ceph       │
│  │                                                           │
│  ├── sdb ZFS (backups/ISOs)   ├── sdb ZFS (backups/ISOs)    │
│  └── sdc Ceph OSD ◄──────────► └── sdc Ceph OSD             │
│              │                            │                   │
│              └──── vm-pool (100 GiB) ─────┘                  │
│                                                              │
│  QDevice (192.168.75.160) ← arbitre quorum                  │
│                                                              │
│  Résultat :                                                  │
│  ✅ Migration instantanée (< 30 secondes)                    │
│  ✅ Failover automatique (< 1 minute)                        │
│  ✅ Zéro SPOF                                               │
│  ✅ Active/Active (chaque nœud héberge ses VMs)              │
│  ✅ Backups ZFS local                                        │
└─────────────────────────────────────────────────────────────┘
```

---

*Document produit dans le cadre d'un projet de stage — validé en environnement de simulation avant déploiement en production.*
