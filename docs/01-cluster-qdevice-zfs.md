# Documentation Technique Complète
# Cluster Proxmox VE — Conteneur LXC, Cluster HA, ZFS Replication & QDevice

**Projet** : Infrastructure Ministère de la Fonction Publique  
**Environnement** : Simulation (VMware Workstation Pro sur Windows 11)  
**Auteur** : Stagiaire DSI  
**Date** : Mai 2026  
**Version Proxmox** : VE 9.1.1  

---

## Table des matières

1. [Architecture cible](#1-architecture-cible)
2. [Prérequis et état initial](#2-prérequis-et-état-initial)
3. [Création du conteneur LXC Nginx sur pve1](#3-création-du-conteneur-lxc-nginx-sur-pve1)
4. [Pourquoi ne pas cloner pve1](#4-pourquoi-ne-pas-cloner-pve1)
5. [Création de la VM pve2 dans VMware](#5-création-de-la-vm-pve2-dans-vmware)
6. [Installation de Proxmox VE sur pve2](#6-installation-de-proxmox-ve-sur-pve2)
7. [Création du cluster Proxmox sur pve1](#7-création-du-cluster-proxmox-sur-pve1)
8. [Jonction de pve2 au cluster](#8-jonction-de-pve2-au-cluster)
9. [Tentative de migration — Problème stockage partagé](#9-tentative-de-migration--problème-stockage-partagé)
10. [Choix du stockage partagé — Analyse et décision](#10-choix-du-stockage-partagé--analyse-et-décision)
11. [Architecture finale retenue](#11-architecture-finale-retenue)
12. [Configuration du QDevice](#12-configuration-du-qdevice)
13. [Vérification du cluster et du QDevice](#13-vérification-du-cluster-et-du-qdevice)
14. [Configuration de la ZFS Replication](#14-configuration-de-la-zfs-replication)
15. [Problème — Pool ZFS inexistant sur pve2](#15-problème--pool-zfs-inexistant-sur-pve2)
16. [Résolution — Création du pool ZFS sur pve2](#16-résolution--création-du-pool-zfs-sur-pve2)
17. [Relance et validation de la réplication](#17-relance-et-validation-de-la-réplication)
18. [Migration live d'un conteneur](#18-migration-live-dun-conteneur)
19. [Configuration de la Haute Disponibilité HA](#19-configuration-de-la-haute-disponibilité-ha)
20. [Problème — Services HA gelés freeze](#20-problème--services-ha-gelés-freeze)
21. [Test de panne — Simulation crash de pve1](#21-test-de-panne--simulation-crash-de-pve1)
22. [Résultat du test HA](#22-résultat-du-test-ha)
23. [Tableau récapitulatif des problèmes rencontrés](#23-tableau-récapitulatif-des-problèmes-rencontrés)
24. [Architecture finale validée](#24-architecture-finale-validée)

---

## 1. Architecture cible

```
pve1 (192.168.75.149)  ←── ZFS Replication ──→  pve2 (192.168.75.158)
         │                                                │
         └─────────────── QDevice ────────────────────────┘
                      (192.168.75.160)
```

| Composant | Rôle |
|-----------|------|
| pve1 | Nœud principal, héberge les VMs/CTs |
| pve2 | Nœud secondaire, cible de réplication et basculement HA |
| QDevice | Arbitre de quorum, évite le split-brain sans 3ème nœud Proxmox |
| ZFS Replication | Synchronisation des disques toutes les 15 minutes |
| HA Manager | Basculement automatique des VMs/CTs en cas de panne |

---

## 2. Prérequis et état initial

Avant de commencer, les éléments suivants sont déjà en place :

- pve1 installé dans VMware Workstation Pro sur Windows 11
- IP de pve1 : `192.168.75.149`
- VM 300 (Windows10VM) hébergée sur pve1
- Template Debian 12 disponible sur pve1 :

```
local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst  118MB
```

---

## 3. Création du conteneur LXC Nginx sur pve1

### Objectif
Créer un conteneur LXC léger sous Debian 12 hébergeant un serveur Nginx, accessible depuis l'hôte Windows 11.

### Pourquoi LXC plutôt qu'une VM ?
Les conteneurs LXC sont bien plus légers que des VMs — ils partagent le noyau de l'hôte et démarrent en quelques secondes. Idéal pour héberger des services web simples comme Nginx.

### Vérification du template disponible

```bash
pveam list local
```

Résultat :
```
NAME                                          SIZE
local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst  118.00MB
```

> ✅ Le template est déjà présent — pas besoin de télécharger.

### Création du conteneur (VMID 400)

```bash
pct create 400 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname nginx-server \
  --cores 1 \
  --memory 512 \
  --swap 512 \
  --storage local-zfs \
  --rootfs local-zfs:4 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --start 1
```

| Paramètre | Valeur | Explication |
|-----------|--------|-------------|
| `400` | VMID | Identifiant du conteneur |
| `--hostname` | nginx-server | Nom du conteneur |
| `--cores` | 1 | 1 vCPU |
| `--memory` | 512 | 512 MB RAM |
| `--storage` | local-zfs | Storage ZFS de pve1 |
| `--rootfs` | local-zfs:4 | Disque racine de 4 GB |
| `--net0` | ip=dhcp | IP automatique via DHCP |
| `--unprivileged` | 1 | Conteneur non privilégié (sécurité) |
| `--start` | 1 | Démarrage automatique à la création |

### Installation de Nginx dans le conteneur

```bash
pct exec 400 -- bash -c "apt update && apt install -y nginx && systemctl enable nginx && systemctl start nginx"
```

### Récupération de l'IP du conteneur

```bash
pct exec 400 -- hostname -I
```

### Vérification
Depuis le navigateur Windows 11 : `http://[IP-conteneur]`

> ✅ Nginx répond avec sa page d'accueil par défaut. Conteneur opérationnel.

---

## 5. Création de la VM pve2 dans VMware

### Configuration identique à pve1

Dans VMware Workstation : **File → New Virtual Machine → Custom (advanced)**

| Paramètre | Valeur |
|-----------|--------|
| Guest OS | Linux → Other Linux 6.x kernel 64-bit |
| Nom | PVE-02 |
| RAM | 7000 MB |
| CPU | 2 vCPU |
| Disque 1 | 20 GB SCSI (système) |
| Disque 2 | 50 GB SCSI (storage ZFS) |
| Réseau 1 | NAT |
| Réseau 2 | LAN Segment |
| Réseau 3 | LAN Segment |

### Paramètres supplémentaires

**Virtualisation imbriquée** (obligatoire pour Proxmox dans VMware) :  
Settings → Processors → cocher **Virtualize Intel VT-x/EPT ou AMD-V/RVI**

**ISO Proxmox** :  
Settings → CD/DVD → Use ISO image file → sélectionner la même ISO que pve1

---

## 6. Installation de Proxmox VE sur pve2

### Procédure
Même installation que pve1 :

1. Démarrer la VM sur l'ISO Proxmox
2. Sélectionner **Install Proxmox VE (Graphical)**
3. Accepter la licence
4. Sélectionner le disque cible : `sda` (20 GB)
5. Configurer la localisation (France, Europe/Paris)
6. Définir le mot de passe root
7. Configurer le réseau :
   - IP : obtenue automatiquement par DHCP (sera `192.168.75.158`)
   - Hostname : `pve2.local`
8. Finaliser l'installation et redémarrer

### Vérification de la connectivité

Depuis pve2, vérifier que pve1 est joignable :

```bash
ping -c 3 192.168.75.149
```

> ✅ Le ping passe — les deux nœuds se voient sur le réseau.

---

## 7. Création du cluster Proxmox sur pve1


**Attention** : Proxmox limite le nom du cluster à 15 caractères maximum.


```bash
pvecm create clusterMINFOPRA
```

### Vérification

```bash
pvecm status
```

Résultat :
```
Name:           clusterMINFOPRA
Config Version: 1
Nodes:          1
Quorate:        Yes
Expected votes: 1
```

> ✅ Cluster créé avec pve1 comme premier nœud.

---

## 8. Jonction de pve2 au cluster

### Commande sur pve2

```bash
pvecm add 192.168.75.149
```

- Accepter l'empreinte SSH avec `yes`
- Entrer le mot de passe root de pve1

### Vérification sur pve1

```bash
pvecm status
```

Résultat :
```
Name:           clusterMINFOPRA
Config Version: 2
Nodes:          2
Quorate:        Yes
Expected votes: 2
Highest expected: 2
```

> ✅ pve2 a rejoint le cluster. Les deux nœuds apparaissent dans le panneau gauche de l'interface web sous **Datacenter (clusterMINFOP...)**.


---

## 10. Choix du stockage partagé — Analyse et décision

Les deux nœuds ont chacun leur propre `local-zfs` **séparé et local**. Sans stockage partagé entre pve1 et pve2, la migration de VMs et la haute disponibilité sont impossibles.

### Comparaison des solutions

| Solution | Performance | Complexité | 2 nœuds | SPOF | Recommandation |
|----------|-------------|------------|---------|------|----------------|
| NFS | Moyenne | Faible | ⚠️ SPOF si pve1 est serveur | ❌ Oui | Lab uniquement |
| Ceph | Excellente | Élevée | ❌ Minimum 3 nœuds | ✅ Non | Production 3+ nœuds |
| iSCSI | Très bonne | Moyenne | ⚠️ Serveur externe requis | ❌ Oui | Avec baie SAN dédiée |
| GlusterFS | Bonne | Moyenne | ⚠️ Split-brain possible | ⚠️ Partiel | Avec arbitre |
| **ZFS Replication** | **Bonne** | **Faible** | **✅ Natif Proxmox** | **✅ Non** | **✅ Notre choix** |

### Problème fondamental avec 2 nœuds

Avec seulement 2 nœuds, le quorum Proxmox est instable :
- Si pve1 tombe → pve2 seul ne sait pas si pve1 est vraiment mort ou si c'est une partition réseau
- Ce phénomène s'appelle **split-brain** : chaque nœud pense être le seul survivant

### Solution retenue : ZFS Replication + QDevice

```
pve1 (local-zfs) ←── ZFS Replication ──→ pve2 (local-zfs)
        │                                          │
        └──────────── QDevice (arbitre) ───────────┘
                     (VM Debian légère)
```

**ZFS Replication** : chaque nœud garde sa propre copie des données, synchronisées toutes les 05 minutes. Pas de SPOF car les données sont sur les deux nœuds.

**QDevice** : un 3ème équipement très léger (simple VM Debian) qui sert uniquement d'arbitre de vote. En cas de panne d'un nœud, le QDevice fournit le vote manquant pour maintenir le quorum.

---

## 11. Architecture finale retenue

```
┌─────────────────────────────────────────────────────────┐
│              Datacenter clusterMINFOPRA                 │
│                                                         │
│  pve1 (192.168.75.149)    pve2 (192.168.75.158)        │
│  ├── VM 300 (Windows10)   ├── [réplique VM 300]        │
│  └── CT 400 (nginx)       └── [réplique CT 400]        │
│           │                        │                    │
│           └──── ZFS Replication ───┘  (toutes 05 min)  │
│                      │                                  │
│              QDevice (192.168.75.160)                   │
│              (arbitre de quorum)                        │
│                                                         │
│  HA : basculement automatique < 2 min en cas de panne  │
└─────────────────────────────────────────────────────────┘
```

| Scénario de panne | Votes disponibles | Quorum ? | Résultat |
|-------------------|-------------------|----------|---------|
| pve1 tombe | pve2 (1) + QDevice (1) = 2 | ✅ Oui (≥2/3) | pve2 prend le relais |
| pve2 tombe | pve1 (1) + QDevice (1) = 2 | ✅ Oui (≥2/3) | pve1 continue |
| QDevice tombe | pve1 (1) + pve2 (1) = 2 | ✅ Oui (≥2/3) | Cluster continue |
| pve1 + QDevice tombent | pve2 (1) seul = 1 | ❌ Non (1/3) | pve2 se met en sécurité |

---

## 12. Configuration du QDevice

### Prérequis
Créer une VM Debian 12 légère dans VMware :

| Paramètre | Valeur |
|-----------|--------|
| Nom | Qdevice |
| RAM | 512 MB |
| Disque | 8 GB |
| CPU | 1 vCPU |
| Réseau | NAT |
| IP obtenue | 192.168.75.160 |

### Étape 1 — Configurer les dépôts Debian sur le QDevice

Par défaut, l'installation minimale Debian utilise le cdrom comme source APT. Il faut le remplacer par les dépôts réseau :

```bash
echo "deb http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list
echo "deb http://deb.debian.org/debian bookworm-updates main" >> /etc/apt/sources.list
echo "deb http://security.debian.org/debian-security bookworm-security main" >> /etc/apt/sources.list
apt update
```

### Étape 2 — Installer corosync-qnetd sur le QDevice

```bash
apt install -y corosync-qnetd
```

### Étape 3 — Activer et démarrer le service

```bash
systemctl enable corosync-qnetd
systemctl start corosync-qnetd
systemctl status corosync-qnetd
```

Résultat attendu : `active (running)` ✅

### Étape 4 — Installer SSH sur le QDevice

```bash
apt install -y openssh-server
systemctl enable ssh
systemctl start ssh
```

### Étape 5 — Autoriser la connexion SSH root

```bash
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

### Étape 6 — Installer corosync-qdevice sur pve1 ET pve2

Sur **pve1** :
```bash
apt install -y corosync-qdevice
```

Sur **pve2** :
```bash
apt install -y corosync-qdevice
```

### Étape 7 — Connecter le cluster au QDevice (depuis pve1 uniquement)

```bash
pvecm qdevice setup 192.168.75.160
```

Entrer le mot de passe root du QDevice quand demandé.

Résultat obtenu :
```
node 'pve1': PKCS12 IMPORT SUCCESSFUL
node 'pve2': Importing cluster certificate and key
node 'pve2': PKCS12 IMPORT SUCCESSFUL
INFO: add QDevice to cluster configuration
INFO: start and enable corosync qdevice daemon on node 'pve1'...
INFO: start and enable corosync qdevice daemon on node 'pve2'...
Reloading corosync.conf...
Done
```

> ✅ QDevice configuré sur les deux nœuds automatiquement.

---

## 13. Vérification du cluster et du QDevice

### Commande sur pve1

```bash
pvecm status
```

### Résultat obtenu

```
Cluster information
------------------
Name:           clusterMINFOPRA
Config Version: 3
Transport:      knet
Secure auth:    on

Quorum information
------------------
Nodes:          2
Quorate:        Yes

Votequorum information
----------------------
Expected votes: 3
Total votes:    3
Quorum:         2
Flags:          Quorate Qdevice

Membership information
----------------------
Nodeid     Votes  Qdevice  Name
0x00000001   1    A,V,NMW  192.168.75.149 (local)  ← pve1
0x00000002   1    A,V,NMW  192.168.75.158          ← pve2
0x00000000   1             Qdevice                 ← arbitre
```

### Interprétation

| Indicateur | Valeur | Signification |
|-----------|--------|---------------|
| Nodes | 2 | pve1 + pve2 présents |
| Expected votes | 3 | pve1 + pve2 + QDevice |
| Flags: Qdevice | présent | QDevice bien reconnu |
| Quorate | Yes | Cluster opérationnel sans SPOF |

> ✅ Architecture sans SPOF confirmée. On peut passer à la réplication ZFS.

---

## 14. Configuration de la ZFS Replication

### Objectif
Répliquer automatiquement les disques des VMs/CTs de pve1 vers pve2 toutes les 05 minutes, afin que pve2 dispose toujours d'une copie récente des données.

### Configurer la réplication via l'interface web

**Pour la VM 300 (Windows10VM) :**

1. Cliquer sur **VM 300** dans le panneau gauche
2. Aller dans **Replication → Add**
3. Renseigner :

| Champ | Valeur |
|-------|--------|
| Target Node | pve2 |
| Schedule | `*/05` |
| Rate limit | vide |

4. Cliquer **Create**

**Pour le CT 400 (nginx-server) :**

Répéter la même procédure avec les mêmes paramètres.

### Vérifier les jobs créés

```bash
pvesr list
```

Résultat attendu :
```
JobID    Target      Schedule   Rate   Enabled
300-0    local/pve2  */05       -      yes
400-0    local/pve2  */05       -      yes
```

---

## 15. Problème — Pool ZFS inexistant sur pve2

### Symptôme
Après création des jobs de réplication, une erreur rouge apparaît dans l'interface Proxmox.

Le log de réplication affiche :
```
zfs error: cannot open 'local-zfs': no such pool
could not activate storage 'local-zfs'
zfs error: cannot import 'local-zfs': no such pool available
```

### Diagnostic

Depuis pve1, vérifier l'état ZFS de pve2 via SSH :

```bash
ssh root@192.168.75.158 zpool list
```

Résultat :
```
no pools available
```

```bash
ssh root@192.168.75.158 pvesm status
```

Résultat :
```
Name        Type     Status    Total(KiB)
local       dir      active    8730792
local-lvm   lvmthin  active    6873088
local-zfs   zfspool  inactive  0          ← pool ZFS absent !
```

### Cause
Lors de l'installation de Proxmox sur pve2, le pool ZFS `local-zfs` a été **référencé dans la configuration** mais **n'a pas été créé physiquement** sur le disque. Le 2ème disque de 50 GB (`/dev/sdb`) est resté vierge.

---

## 16. Résolution — Création du pool ZFS sur pve2

### Étape 1 — Se connecter sur pve2

```bash
ssh root@192.168.75.158
```

### Étape 2 — Identifier le disque disponible

```bash
lsblk
```

Résultat obtenu :
```
NAME        SIZE  TYPE
sda         20G   disk   ← disque système Proxmox (utilisé)
├─sda1      1007K part
├─sda2      512M  part
└─sda3      19.5G part
sdb         50G   disk   ← disque vierge disponible ✅
sr0         1.7G  rom
```

### Étape 3 — Créer le pool ZFS sur sdb

```bash
zpool create -f local-zfs /dev/sdb
```

### Étape 4 — Vérifier la création

```bash
zpool list
```

Résultat :
```
NAME        SIZE   ALLOC  FREE    HEALTH
local-zfs   49.5G  112K   49.5G   ONLINE   ✅
```

### Étape 5 — Vérifier que Proxmox reconnaît le pool

```bash
pvesm status
```

Résultat :
```
Name        Type     Status   Total(KiB)  Used(KiB)  Available(KiB)
local-zfs   zfspool  active   50298880    112        50298767        ✅
```

### Étape 6 — Quitter pve2

```bash
exit
```

---

## 17. Relance et validation de la réplication

### Problème intermédiaire — Verrou bloqué

Après correction du pool ZFS, une tentative manuelle de relance a échoué :

```
can't lock file '/var/lock/pvesr.lck' - got timeout
cfs-lock 'file-replication_cfg' error: got lock request timeout (500)
```

**Cause** : Un processus `pvesr` précédent était resté bloqué, laissant un verrou actif.

**Résolution :**

```bash
# Tuer les processus pvesr bloqués
killall -9 pvesr

# Supprimer les verrous
rm -f /var/lock/pvesr.lck
rm -f /var/lock/pve-manager/pvesr

# Redémarrer le service de cluster
systemctl restart pve-cluster

# Attendre 10 secondes, puis relancer
pvesr run
```

### Validation via l'interface web

Cliquer sur **VM 300 → Replication → Schedule now**

Résultat attendu dans l'interface :

| Guest | Job | Target | Status | Last Sync | Schedule |
|-------|-----|--------|--------|-----------|----------|
| 300 | 0 | pve2 | ✅ OK | horodatage | */05 |
| 400 | 0 | pve2 | ✅ OK | horodatage | */05 |

> ✅ La réplication ZFS est opérationnelle. pve2 reçoit une copie des données toutes les 15 minutes.

---

## 18. Migration live d'un conteneur

### Objectif
Tester le déplacement du CT 400 en cours d'exécution de pve1 vers pve2 sans interruption de service.

### Procédure — Via l'interface web

1. Cliquer sur **CT 400 (nginx-server)**
2. Cliquer sur **Migrate** en haut
3. Sélectionner **Target node : pve2**
4. Cliquer **Migrate**

### Résultat obtenu

```
starting migration of CT 400 to node 'pve2' (192.168.75.158)
found local volume 'local-zfs:subvol-400-disk-0'
incremental sync 'local-zfs:subvol-400-disk-0' (ZFS)
successfully imported 'local-zfs:subvol-400-disk-0'
start container on target node
migration finished successfully (duration 00:00:29)
TASK OK
```

**Durée** : 29 secondes grâce à la réplication ZFS préalable (seul le delta est transféré).

> ✅ Le CT 400 apparaît sous pve2 dans le panneau gauche.

### Retour du CT 400 sur pve1 (préparation HA)

```bash
pct migrate 400 pve1 --restart
```

---

## 19. Configuration de la Haute Disponibilité HA

### Objectif
Configurer le basculement automatique des VMs/CTs sur pve2 en cas de panne de pve1.

### Étape 1 — Accéder au gestionnaire HA

Dans l'interface web : **Datacenter → HA → Resources → Add**

### Étape 2 — Ajouter la VM 300

| Champ | Valeur |
|-------|--------|
| VM/CT | 300 |
| Max Restart | 3 |
| Max Relocate | 3 |
| State | started |

Cliquer **Add**.

### Étape 3 — Ajouter le CT 400

Répéter la même procédure avec les mêmes paramètres pour le CT 400.

### Étape 4 — Vérifier la configuration HA

```bash
ha-manager config
```

Résultat attendu :
```
ct:400
    max_relocate 3
    max_restart 3
    state started

vm:300
    max_relocate 3
    max_restart 3
    state started
```

```bash
ha-manager status
```

Résultat attendu :
```
quorum OK
master pve1 (active, ...)
lrm pve1 (active, ...)
lrm pve2 (active, ...)
service ct:400 (pve1, started)
service vm:300 (pve1, started)
```

---

## 20. Problème — Services HA gelés freeze

### Symptôme

```bash
ha-manager status
```

Affiche :
```
lrm pve1 (old timestamp - dead?)
service ct:400 (pve1, freeze)
service vm:300 (pve1, freeze)
```

### Cause
Le service `pve-ha-lrm` avait été arrêté manuellement sur pve1 lors d'un test préliminaire. Sans le LRM actif, le gestionnaire HA considère le nœud comme mort et **gèle** les services pour éviter un double démarrage accidentel.

### Résolution

```bash
# Redémarrer les services HA sur pve1
systemctl start pve-ha-lrm
systemctl start pve-ha-crm

# Vérifier le statut
ha-manager status
```

Résultat après correction :
```
quorum OK
master pve1 (active)
lrm pve1 (active)              ✅
lrm pve2 (active)              ✅
service ct:400 (pve1, started) ✅
service vm:300 (pve1, started) ✅
```

> ✅ Les services sont passés de **freeze** à **started**.

---

## 21. Test de panne — Simulation crash de pve1

### Objectif
Vérifier que la HA fonctionne réellement en simulant une panne brutale de pve1.

### Prérequis
Ouvrir l'interface de pve2 dans un onglet séparé **avant** d'éteindre pve1 :
```
https://192.168.75.158:8006
```

### Procédure
Dans VMware Workstation : **Power Off** brutal sur la VM pve1.

### Ce qui se passe automatiquement

1. pve2 détecte que pve1 ne répond plus au heartbeat
2. Le QDevice maintient le quorum (2 votes sur 3 : pve2 + QDevice)
3. Le gestionnaire HA de pve2 prend le relais
4. pve2 démarre automatiquement CT 400 et VM 300

---

## 22. Résultat du test HA

### Observations dans l'interface pve2

```
pve2
 ├── 400 (nginx-server)   ← basculé automatiquement ✅
 └── 300 (Windows10VM)    ← basculé automatiquement ✅
```

### Tâches observées dans l'onglet Tasks de pve2

```
CT 400 - Start   pve2   OK   ✅
VM 300 - Start   pve2   OK   ✅
```

### Délai de basculement observé

**Moins de 2 minutes** entre la panne de pve1 et le démarrage des services sur pve2.

> ✅ La Haute Disponibilité fonctionne parfaitement. En cas de panne de pve1, les services reprennent automatiquement sur pve2 sans intervention manuelle.

---

## 23. Tableau récapitulatif des problèmes rencontrés

| # | Étape | Problème | Cause | Solution |
|---|-------|---------|-------|----------|
| 1 | Création cluster | `clustername: value may only be 15 characters long` | Nom du cluster trop long | Utiliser `clusterMINFOPRA` (15 caractères max) |
| 2 | QDevice | `ssh: connect to port 22: Connection refused` | SSH non installé sur le QDevice | `apt install -y openssh-server` |
| 3 | QDevice | `Permission denied` lors de ssh-copy-id | Root login SSH désactivé par défaut sur Debian | `sed -i 's/#PermitRootLogin.../PermitRootLogin yes/'` dans sshd_config |
| 4 | Réplication ZFS | `cannot open 'local-zfs': no such pool` | Pool ZFS non créé physiquement sur pve2 | `zpool create -f local-zfs /dev/sdb` sur pve2 |
| 5 | Réplication ZFS | `can't lock file '/var/lock/pvesr.lck'` | Processus pvesr bloqué laissant un verrou actif | `killall -9 pvesr` + `rm -f /var/lock/pvesr.lck` + `systemctl restart pve-cluster` |
| 6 | Réplication ZFS | `cfs-lock 'file-replication_cfg' error: timeout` | Même cause que #5 | Même résolution que #5 |
| 7 | HA | Services en état `freeze` | `pve-ha-lrm` arrêté manuellement | `systemctl start pve-ha-lrm && systemctl start pve-ha-crm` |
| 8 | HA | `pve2: detected time drift!` | Décalage d'horloge entre pve1 et pve2 | `systemctl restart chrony` sur pve2 |

---

## 24. Architecture finale validée

```
┌─────────────────────────────────────────────────────────┐
│              Datacenter clusterMINFOPRA                 │
│                                                         │
│  pve1 (192.168.75.149)    pve2 (192.168.75.158)        │
│  ├── VM 300 (Windows10)   ├── [réplique VM 300]        │
│  └── CT 400 (nginx)       └── [réplique CT 400]        │
│           │                        │                    │
│           └──── ZFS Replication ───┘  (toutes 15 min)  │
│                      │                                  │
│              QDevice (192.168.75.160)                   │
│              (arbitre de quorum)                        │
│                                                         │
│  HA : basculement automatique < 2 min en cas de panne  │
└─────────────────────────────────────────────────────────┘
```

### Récapitulatif des composants

| Composant | IP | Rôle | Status |
|-----------|-----|------|--------|
| pve1 | 192.168.75.149 | Nœud principal Proxmox VE 9.1.1 | ✅ Opérationnel |
| pve2 | 192.168.75.158 | Nœud secondaire Proxmox VE 9.1.1 | ✅ Opérationnel |
| QDevice | 192.168.75.160 | Arbitre de quorum (Debian 12) | ✅ Opérationnel |
| VM 300 | — | Windows 10 (HA activée) | ✅ Répliquée + HA |
| CT 400 | — | Nginx sur Debian 12 (HA activée) | ✅ Répliquée + HA |

### Fonctionnalités validées

| Fonctionnalité | Test effectué | Résultat |
|----------------|---------------|---------|
| Cluster 2 nœuds | pvecm status | ✅ 2 nœuds + QDevice |
| Quorum sans SPOF | Analyse des votes | ✅ 3 votes, seuil à 2 |
| ZFS Replication | Schedule now | ✅ Sync toutes les 15 min |
| Migration live CT | pct migrate 400 pve2 | ✅ 29 secondes |
| Haute Disponibilité | Power Off brutal pve1 | ✅ Basculement < 2 min |

---

## Commandes de référence rapide

```bash
# Statut du cluster
pvecm status

# Lister les nœuds
pvecm nodes

# Statut de la réplication
pvesr list

# Forcer une synchronisation
pvesr run

# Statut de la HA
ha-manager status

# Configuration HA
ha-manager config

# Migrer un CT
pct migrate <CTID> <noeud-cible> --restart

# Migrer une VM (à froid)
qm migrate <VMID> <noeud-cible>

# Vérifier les pools ZFS
zpool list
zpool status

# Vérifier les storages Proxmox
pvesm status
```

---

*Document produit dans le cadre d'un projet de stage — validé en environnement de simulation avant déploiement en production.*  
*Ministère de la Fonction Publique — Direction des Systèmes d'Information*
