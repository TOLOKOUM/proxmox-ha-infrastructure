# Documentation Technique — Failback Automatique HA avec Affinity Rules

**Projet** : Infrastructure Ministère de la Fonction Publique  
**Environnement** : Simulation (VMware Workstation sur Windows 11)  
**Suite de** : Documentation Ceph, Migration stockage partagé & Haute Disponibilité  
**Date** : Mai 2026  
**Version Proxmox** : VE 9.1.1

---

## Table des matières

1. [Objectif et contexte](#1-objectif-et-contexte)
2. [Concepts clés](#2-concepts-clés)
3. [État initial avant configuration](#3-état-initial-avant-configuration)
4. [Problème — Ancienne syntaxe incompatible Proxmox 9](#4-problème--ancienne-syntaxe-incompatible-proxmox-9)
5. [Configuration du Failback via Affinity Rules](#5-configuration-du-failback-via-affinity-rules)
6. [Vérification de la configuration](#6-vérification-de-la-configuration)
7. [Comportement attendu en production](#7-comportement-attendu-en-production)
8. [Tableau récapitulatif](#8-tableau-récapitulatif)

---

## 1. Objectif et contexte

### Problème résolu
Sans failback configuré, lorsque pve1 tombe en panne et que la HA bascule les VMs sur pve2, **les VMs restent sur pve2 même après le retour de pve1**. L'administrateur doit migrer manuellement chaque VM vers son nœud d'origine.

### Objectif
Configurer le **retour automatique** des VMs/CTs sur leur nœud préféré dès que ce nœud revient en ligne, sans aucune intervention manuelle.

### Architecture Active/Active visée

```
État normal :
pve1                    pve2
└── VM 300 (Windows)    └── CT 400 (nginx)
     ↑ nœud préféré          ↑ nœud préféré

Si pve1 tombe :
pve2
├── CT 400 (nginx)      ← reste sur pve2
└── VM 300 (Windows)    ← bascule automatiquement sur pve2

Quand pve1 revient :
pve1                    pve2
└── VM 300 (Windows)    └── CT 400 (nginx)
     ↑ retour auto           ↑ reste sur pve2
```

---

## 2. Concepts clés

### Failback
Le failback est le mécanisme qui ramène automatiquement une VM/CT sur son nœud préféré après que ce nœud soit revenu en ligne après une panne.

### HA Node Affinity Rules (Proxmox 9)
Dans Proxmox 9, les anciens **groupes HA** ont été remplacés par les **Affinity Rules**. Ces règles définissent :
- Quel nœud est **préféré** pour chaque VM/CT
- Si la règle est **stricte** (la VM ne peut tourner que sur ce nœud) ou **souple** (la VM peut basculer sur un autre nœud si nécessaire)

### Paramètre Strict

| Strict | Comportement |
|--------|-------------|
| `true` | La VM tourne **uniquement** sur le nœud préféré. Si ce nœud est down → VM arrêtée. |
| `false` | La VM **préfère** le nœud défini mais peut basculer sur un autre nœud si nécessaire. **Recommandé en production.** |

### Paramètre Failback

| Failback | Comportement |
|---------|-------------|
| `true` | La VM retourne **automatiquement** sur son nœud préféré dès qu'il revient. |
| `false` | La VM reste sur le nœud de secours même après le retour du nœud préféré. |

---

## 3. État initial avant configuration

Vérifier l'état de la HA avant toute modification :

```bash
ha-manager status
```

Résultat obtenu :
```
quorum OK
master pve2 (active)
lrm pve1 (active)
lrm pve2 (idle)
service ct:400 (pve1, started)
service vm:300 (pve1, started)
```

Vérifier la configuration des ressources HA :

```bash
ha-manager config
```

Résultat :
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

**Observation** : Le Failback était déjà à `true` par défaut dans l'interface web (colonne Failback = true), mais aucun nœud préféré n'était défini. Sans nœud préféré, Proxmox ne sait pas où ramener la VM après une panne.

---

## 4. Problème — Ancienne syntaxe incompatible Proxmox 9

### Tentative avec l'ancienne syntaxe

En Proxmox 8 et versions antérieures, la configuration des nœuds préférés se faisait via les groupes HA :

```bash
# Commandes qui NE FONCTIONNENT PAS sur Proxmox 9
ha-manager groupadd grp-pve1 --nodes pve1:2,pve2:1 --restricted 0 --nofailback 0
ha-manager set vm:300 --group grp-pve1
```

### Erreur obtenue

```
cannot create group: ha groups have been migrated to rules
invalid parameter 'group': ha groups have been migrated to rules
```

### Cause
**Proxmox 9 a supprimé les groupes HA** et les a remplacés par les **Affinity Rules**, une interface plus flexible et plus puissante. La migration est automatique pour les clusters existants mais les nouvelles configurations doivent utiliser la nouvelle syntaxe.

### Solution
Utiliser l'interface web **Datacenter → HA → Affinity Rules** pour configurer les nœuds préférés.

---

## 5. Configuration du Failback via Affinity Rules

### Accéder aux Affinity Rules

Dans l'interface web Proxmox :
**Datacenter → HA → Affinity Rules**

On distingue deux sections :
- **HA Node Affinity Rules** → définit les nœuds préférés pour chaque VM/CT
- **HA Resource Affinity Rules** → définit les affinités entre VMs/CTs

### Règle 1 — VM 300 préfère pve1

1. Dans **HA Node Affinity Rules** → cliquer **Add**
2. Configurer :

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Enable | ✅ coché | Règle active immédiatement |
| Strict | ☐ décoché | Permet basculement sur pve2 si pve1 down |
| HA Resources | `300` | VM Windows ciblée |
| Node | ✅ **pve1** uniquement | Nœud préféré |

3. Cliquer **Add**

### Règle 2 — CT 400 préfère pve2

1. Dans **HA Node Affinity Rules** → cliquer **Add**
2. Configurer :

| Champ | Valeur | Justification |
|-------|--------|---------------|
| Enable | ✅ coché | Règle active immédiatement |
| Strict | ☐ décoché | Permet basculement sur pve1 si pve2 down |
| HA Resources | `400` | CT nginx ciblé |
| Node | ✅ **pve2** uniquement | Nœud préféré |

3. Cliquer **Add**

---

## 6. Vérification de la configuration

### Dans l'interface web

Après création des deux règles, la section **HA Node Affinity Rules** doit afficher :

| Enabled | State | Strict | HA Resources | Nodes |
|---------|-------|--------|-------------|-------|
| ✅ | ✅ | false | vm:300 | pve1 |
| ✅ | ✅ | false | ct:400 | pve2 |

### Vérification en CLI

```bash
ha-manager status
```

Résultat attendu :
```
quorum OK
master pve2 (active)
lrm pve1 (active)
lrm pve2 (active)
service ct:400 (pve2, started)   ← sur son nœud préféré
service vm:300 (pve1, started)   ← sur son nœud préféré
```

### Vérification du Failback dans Resources

**Datacenter → HA → Resources** :

| ID | State | Node | Failback |
|----|-------|------|---------|
| ct:400 | started | pve2 | **true** ✅ |
| vm:300 | started | pve1 | **true** ✅ |

---

## 7. Comportement attendu en production

### Scénario 1 — Panne de pve1

```
T+0s   : pve1 tombe brutalement
T+30s  : QDevice confirme la panne de pve1
T+45s  : HA démarre VM 300 sur pve2
T+60s  : VM 300 accessible sur pve2
         → pve2 héberge maintenant CT 400 + VM 300
```

### Scénario 2 — Retour de pve1 (Failback)

```
T+0s   : pve1 redémarre et rejoint le cluster
T+30s  : HA détecte que pve1 est de retour
T+60s  : HA migre automatiquement VM 300 vers pve1
         (migration instantanée grâce à Ceph)
T+90s  : Retour à l'état normal :
         pve1 → VM 300
         pve2 → CT 400
         → Zéro intervention manuelle
```

### Scénario 3 — Panne de pve2

```
T+0s   : pve2 tombe brutalement
T+30s  : QDevice confirme la panne de pve2
T+45s  : HA démarre CT 400 sur pve1
T+60s  : CT 400 accessible sur pve1
         → pve1 héberge maintenant VM 300 + CT 400
```

### Scénario 4 — Retour de pve2 (Failback)

```
T+0s   : pve2 redémarre et rejoint le cluster
T+60s  : HA migre automatiquement CT 400 vers pve2
         → Retour à l'état normal automatiquement
```

---

## 8. Tableau récapitulatif

### Configuration finale

| Ressource | Nœud préféré | Nœud secours | Strict | Failback | Migration |
|-----------|-------------|-------------|--------|---------|-----------|
| VM 300 (Windows) | pve1 | pve2 | false | true | Automatique |
| CT 400 (nginx) | pve2 | pve1 | false | true | Automatique |

### Récapitulatif des mécanismes de protection

```
Couche 1 — Ceph (temps réel)
  └── Disques partagés entre pve1 et pve2
  └── Zéro perte de données en cas de panne
  └── Migration instantanée (< 30 secondes)

Couche 2 — HA Proxmox (automatique)
  └── Redémarre les VMs sur le nœud survivant
  └── Délai de basculement < 1 minute
  └── Failback automatique au retour du nœud

Couche 3 — QDevice (arbitre)
  └── Évite le split-brain
  └── Maintient le quorum avec 2 nœuds

Couche 4 — Affinity Rules (orchestration)
  └── Définit les nœuds préférés
  └── Garantit le retour automatique (failback)
  └── Architecture Active/Active respectée
```

### Points importants pour la production

- **Ne jamais mettre Strict = true** avec seulement 2 nœuds — la VM serait arrêtée si le nœud préféré tombe
- **Le failback nécessite Ceph** — sans stockage partagé, le retour automatique serait lent car il faudrait transférer le disque
- **Le QDevice est indispensable** — sans lui, le failback pourrait créer un split-brain avec 2 nœuds
- **Tester régulièrement** — simuler des pannes en environnement de test pour valider le comportement

---

*Document produit dans le cadre d'un projet de stage — validé en environnement de simulation avant déploiement en production.*
