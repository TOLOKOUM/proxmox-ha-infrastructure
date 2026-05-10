# Documentation Technique — Tests Failover & Failback avec Ceph

**Projet** : Infrastructure Ministère de la Fonction Publique  
**Environnement** : Simulation (VMware Workstation sur Windows 11)  
**Suite de** : Documentation PBS — Installation et Configuration  
**Date** : Mai 2026  
**Version Proxmox** : VE 9.1.1 | **Version Ceph** : 19.2.3 (Squid)

---

## Table des matières

1. [Objectif des tests](#1-objectif-des-tests)
2. [Architecture testée](#2-architecture-testée)
3. [Prérequis avant les tests](#3-prérequis-avant-les-tests)
4. [TEST 1 — Failover pve1](#4-test-1--failover-pve1)
5. [TEST 2 — Failback pve1](#5-test-2--failback-pve1)
6. [TEST 3 — Failover pve2](#6-test-3--failover-pve2)
7. [TEST 4 — Failback pve2](#7-test-4--failback-pve2)
8. [Tableau récapitulatif des résultats](#8-tableau-récapitulatif-des-résultats)
9. [Pourquoi Ceph rend le failback instantané](#9-pourquoi-ceph-rend-le-failback-instantané)
10. [Validation finale de l'architecture](#10-validation-finale-de-larchitecture)

---

## 1. Objectif des tests

### Pourquoi tester ?

Une infrastructure de haute disponibilité non testée n'est pas fiable. Ces tests valident que :

- Le **failover** (basculement en cas de panne) fonctionne automatiquement
- Le **failback** (retour sur le nœud d'origine) fonctionne automatiquement
- **Ceph** permet une migration instantanée sans perte de données
- Le **QDevice** maintient le quorum pendant les pannes
- Les **Affinity Rules** ramènent les VMs sur leur nœud préféré

### Scénarios testés

```
TEST 1 — Failover pve1  : VM 300 bascule de pve1 vers pve2
TEST 2 — Failback pve1  : VM 300 retourne de pve2 vers pve1
TEST 3 — Failover pve2  : CT 400 bascule de pve2 vers pve1
TEST 4 — Failback pve2  : CT 400 retourne de pve1 vers pve2
```

---

## 2. Architecture testée

```
État normal (avant tests) :

pve1 (192.168.75.149)          pve2 (192.168.75.158)
└── VM 300 (Windows10VM)       └── CT 400 (nginx-server)
     ↑ nœud préféré                 ↑ nœud préféré
     
Stockage : Ceph vm-pool (partagé entre pve1 et pve2)
Arbitre  : QDevice (192.168.75.160)
Backup   : PBS (192.168.75.161)

Affinity Rules :
  vm:300 → préfère pve1 (Strict: false, Failback: true)
  ct:400 → préfère pve2 (Strict: false, Failback: true)
```

---

## 3. Prérequis avant les tests

### Vérification de l'état initial

Avant chaque série de tests, vérifier que l'infrastructure est saine.

**Vérifier le cluster :**
```bash
pvecm status
```

Résultat attendu :
```
Name:     clusterMINFOPRA
Nodes:    2
Quorate:  Yes
Flags:    Quorate Qdevice
```

**Vérifier la HA :**
```bash
ha-manager status
```

Résultat attendu :
```
quorum OK
master pve2 (active)
lrm pve1 (active)
lrm pve2 (active)
service ct:400 (pve2, started)   ← CT 400 sur pve2
service vm:300 (pve1, started)   ← VM 300 sur pve1
```

**Vérifier Ceph :**
```bash
ceph status
```

Résultat attendu :
```
health: HEALTH_OK (ou HEALTH_WARN mineur)
mon: 2 daemons, quorum pve1,pve2
osd: 2 up, 2 in
```

### Préparation des fenêtres de surveillance

Avant de lancer chaque test, ouvrir **deux onglets** dans le navigateur :
- Onglet 1 : `https://192.168.75.149:8006` (pve1)
- Onglet 2 : `https://192.168.75.158:8006` (pve2)

Cela permet de surveiller en temps réel les deux nœuds simultanément.

---

## 4. TEST 1 — Failover pve1

### Objectif
Simuler une panne brutale de pve1 et vérifier que la VM 300 (Windows) bascule automatiquement sur pve2.

### Méthode de simulation
La commande `echo b > /proc/sysrq-trigger` provoque un **crash kernel immédiat** sans arrêt propre — exactement ce qui se passe lors d'une vraie panne matérielle (coupure électrique, crash hardware).

### Procédure

**Étape 1 — Ouvrir l'interface pve2 dans un onglet séparé**
```
https://192.168.75.158:8006
```

**Étape 2 — Dans le Shell de pve1, déclencher la panne**
```bash
echo b > /proc/sysrq-trigger
```

⚠️ La connexion à pve1 est coupée immédiatement après cette commande.

**Étape 3 — Surveiller sur pve2**

Observer l'onglet **Tasks** de pve2 — les événements suivants doivent apparaître dans l'ordre :

```
T+0s   : pve1 ne répond plus
T+30s  : QDevice confirme la panne de pve1
          → Le quorum est maintenu grâce au QDevice
T+45s  : HA Manager de pve2 prend le relais
T+60s  : VM 300 - Start   pve2   (en cours...)
T+90s  : VM 300 - Start   pve2   OK ✅
```

### Résultat obtenu

```
✅ VM 300 (Windows10VM) démarre automatiquement sur pve2
✅ Zéro perte de données (Ceph = disque déjà présent sur pve2)
✅ QDevice maintient le quorum sans pve1
✅ Temps de basculement : < 2 minutes
```

**Dans le panneau gauche de pve2 après le failover :**
```
pve2
├── CT 400 (nginx-server)   ← déjà là
└── VM 300 (Windows10VM)    ← vient d'arriver ✅
```

### Pourquoi ça fonctionne avec Ceph

Sans Ceph, pve2 aurait dû copier 35 GB depuis pve1 (impossible si pve1 est down).  
Avec Ceph, le disque de VM 300 **existe déjà sur pve2** — pve2 démarre simplement la VM en pointant vers le disque Ceph existant.

---

## 5. TEST 2 — Failback pve1

### Objectif
Vérifier que VM 300 retourne **automatiquement** sur pve1 dès que pve1 revient en ligne, sans intervention manuelle.

### Procédure

**Étape 1 — Redémarrer pve1 dans VMware**

Dans VMware Workstation : clic droit sur **PVE-01** → **Power On**

**Étape 2 — Surveiller sur pve2**

Observer l'onglet **Tasks** de pve2 :

```
T+0s   : pve1 démarre
T+30s  : pve1 rejoint le cluster
          pvecm status → Nodes: 2, Quorate: Yes
T+60s  : HA détecte le retour de pve1
T+90s  : Ceph se resynchronise automatiquement
T+120s : VM 300 - Migrate (pve2 → pve1)  en cours...
T+150s : VM 300 - Migrate   OK ✅
          (migration instantanée grâce à Ceph)
```

**Étape 3 — Vérifier le retour à l'état normal**

```bash
ha-manager status
```

Résultat attendu :
```
service ct:400 (pve2, started)   ← CT 400 reste sur pve2 ✅
service vm:300 (pve1, started)   ← VM 300 de retour sur pve1 ✅
```

### Résultat obtenu

```
✅ VM 300 retourne automatiquement sur pve1 (nœud préféré)
✅ Migration instantanée grâce à Ceph (< 30 secondes)
✅ Zéro intervention manuelle
✅ CT 400 reste sur pve2 (non impacté)
✅ Architecture Active/Active rétablie automatiquement
```

---

## 6. TEST 3 — Failover pve2

### Objectif
Simuler une panne brutale de pve2 et vérifier que le CT 400 (nginx) bascule automatiquement sur pve1.

### Procédure

**Étape 1 — Ouvrir l'interface pve1 dans un onglet séparé**
```
https://192.168.75.149:8006
```

**Étape 2 — Dans le Shell de pve2, déclencher la panne**
```bash
echo b > /proc/sysrq-trigger
```

**Étape 3 — Surveiller sur pve1**

Observer l'onglet **Tasks** de pve1 :

```
T+0s   : pve2 ne répond plus
T+30s  : QDevice confirme la panne de pve2
T+45s  : HA Manager de pve1 prend le relais
T+60s  : CT 400 - Start   pve1   (en cours...)
T+90s  : CT 400 - Start   pve1   OK ✅
```

### Résultat obtenu

```
✅ CT 400 (nginx-server) démarre automatiquement sur pve1
✅ Zéro perte de données (Ceph)
✅ QDevice maintient le quorum sans pve2
✅ Service nginx accessible sans interruption notable

Dans le panneau gauche de pve1 après le failover :
pve1
├── VM 300 (Windows10VM)    ← déjà là
└── CT 400 (nginx-server)   ← vient d'arriver ✅
```

---

## 7. TEST 4 — Failback pve2

### Objectif
Vérifier que CT 400 retourne **automatiquement** sur pve2 dès que pve2 revient en ligne.

### Procédure

**Étape 1 — Redémarrer pve2 dans VMware**

Dans VMware Workstation : clic droit sur **PVE-02** → **Power On**

**Étape 2 — Surveiller sur pve1**

Observer l'onglet **Tasks** de pve1 :

```
T+0s   : pve2 démarre
T+30s  : pve2 rejoint le cluster
T+60s  : HA détecte le retour de pve2
T+90s  : Ceph se resynchronise automatiquement
T+120s : CT 400 - Migrate (pve1 → pve2)  en cours...
T+150s : CT 400 - Migrate   OK ✅
```

**Étape 3 — Vérifier le retour à l'état normal**

```bash
ha-manager status
```

Résultat attendu :
```
quorum OK
lrm pve1 (active)
lrm pve2 (active)
service ct:400 (pve2, started)   ← CT 400 de retour sur pve2 ✅
service vm:300 (pve1, started)   ← VM 300 reste sur pve1 ✅
```

### Résultat obtenu

```
✅ CT 400 retourne automatiquement sur pve2 (nœud préféré)
✅ Migration instantanée grâce à Ceph
✅ Zéro intervention manuelle
✅ VM 300 reste sur pve1 (non impacté)
✅ Architecture Active/Active rétablie automatiquement
```

---

## 8. Tableau récapitulatif des résultats

| Test | Scénario | Déclencheur | Résultat | Automatique | Perte données |
|------|---------|-------------|----------|-------------|---------------|
| 1 | Failover pve1 | `echo b > /proc/sysrq-trigger` | VM 300 → pve2 | ✅ Oui | ✅ Aucune |
| 2 | Failback pve1 | Power On PVE-01 | VM 300 → pve1 | ✅ Oui | ✅ Aucune |
| 3 | Failover pve2 | `echo b > /proc/sysrq-trigger` | CT 400 → pve1 | ✅ Oui | ✅ Aucune |
| 4 | Failback pve2 | Power On PVE-02 | CT 400 → pve2 | ✅ Oui | ✅ Aucune |

### Temps observés

| Événement | Temps observé | Objectif production |
|-----------|--------------|---------------------|
| Détection panne | ~30 secondes | < 60 secondes |
| Démarrage VM sur nœud secours | ~60 secondes | < 2 minutes |
| Migration failback (Ceph) | < 30 secondes | < 1 minute |
| Retour état normal complet | ~2-3 minutes | < 5 minutes |

---

## 9. Pourquoi Ceph rend le failback instantané

### Sans Ceph (ZFS Replication)

```
pve1 tombe → pve2 démarre VM 300 depuis sa copie locale
pve1 revient → 
  1. Proxmox doit vérifier si les données sont synchronisées
  2. Si snapshots perdus → transfert complet de 35 GB nécessaire
  3. Failback = 10 à 30 minutes de transfert réseau
  → Interruption longue, risque de perte de données
```

### Avec Ceph

```
pve1 tombe → pve2 démarre VM 300 en pointant vers vm-pool
              (le disque est déjà accessible, pas de copie)
pve1 revient →
  1. Ceph se resynchronise en arrière-plan automatiquement
  2. HA migre VM 300 vers pve1 (simple changement de pointeur)
  3. Failback = < 30 secondes
  → Aucune interruption, zéro perte de données
```

### Analogie

```
Sans Ceph = Clé USB partagée
  → Doit être physiquement copiée d'un PC à l'autre
  → Lent et risqué

Avec Ceph = Google Drive
  → Le fichier est dans le cloud du cluster
  → pve1 et pve2 y accèdent directement
  → Pas de copie = instantané
```

---

## 10. Validation finale de l'architecture

### Tous les composants validés

```
┌─────────────────────────────────────────────────────────────┐
│              Infrastructure Ministère — COMPLÈTE             │
│                                                              │
│  Composant              Statut    Testé    Résultat         │
│  ──────────────────────────────────────────────────────     │
│  Cluster Proxmox        ✅ OK     ✅ Oui   Opérationnel     │
│  QDevice (arbitre)      ✅ OK     ✅ Oui   Quorum maintenu  │
│  Ceph (stockage)        ✅ OK     ✅ Oui   Migration < 30s  │
│  HA Failover pve1       ✅ OK     ✅ Oui   < 2 minutes      │
│  HA Failback pve1       ✅ OK     ✅ Oui   Automatique      │
│  HA Failover pve2       ✅ OK     ✅ Oui   < 2 minutes      │
│  HA Failback pve2       ✅ OK     ✅ Oui   Automatique      │
│  Affinity Rules         ✅ OK     ✅ Oui   Nœuds respectés  │
│  PBS Backup             ✅ OK     ✅ Oui   Quotidien 23h00  │
│  PBS Restauration       ✅ OK     ✅ Oui   CT 401 restauré  │
└─────────────────────────────────────────────────────────────┘
```

### Niveaux de protection validés

```
NIVEAU 1 — Ceph (temps réel, permanent)
  ✅ Données toujours présentes sur pve1 ET pve2
  ✅ Zéro perte de données en cas de panne

NIVEAU 2 — HA Proxmox (automatique, < 2 min)
  ✅ Failover automatique testé sur pve1 et pve2
  ✅ Failback automatique testé sur pve1 et pve2
  ✅ Architecture Active/Active respectée

NIVEAU 3 — QDevice (arbitre permanent)
  ✅ Quorum maintenu avec un seul nœud
  ✅ Split-brain évité lors des pannes

NIVEAU 4 — PBS (quotidien, historique 3 mois)
  ✅ Backup testé et validé
  ✅ Restauration testée et validée
  ✅ Protection contre ransomware et erreur humaine
```

### Commandes de surveillance en production

```bash
# Vérifier l'état global du cluster
pvecm status && ha-manager status && ceph status

# Surveiller les événements HA en temps réel
journalctl -fu pve-ha-crm

# Vérifier les backups PBS
proxmox-backup-manager task list --limit 10

# Tester la connectivité PBS
pvesm status | grep pbs
```

---

*Document produit dans le cadre d'un projet de stage — validé en environnement de simulation avant déploiement en production.*
