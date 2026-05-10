# 🖥️ Infrastructure Haute Disponibilité Proxmox VE — Ministère de la Fonction Publique

> **Projet de stage** — Migration VMware → Proxmox, Cluster HA Active/Active avec Ceph, Backups PBS  
> Environnement : Simulation validée avant déploiement en production  
> Auteur : Stagiaire Informatique | Mai 2026

---

## 📋 Table des matières

- [Vue d'ensemble](#-vue-densemble)
- [Architecture finale](#-architecture-finale)
- [Composants](#-composants)
- [Prérequis](#-prérequis)
- [Structure du projet](#-structure-du-projet)
- [Documentation](#-documentation)
- [Résultats des tests](#-résultats-des-tests)
- [Versions utilisées](#-versions-utilisées)
- [Auteur](#-auteur)

---

## 🎯 Vue d'ensemble

Ce projet documente la mise en place d'une infrastructure de virtualisation **hautement disponible** et **sans point de défaillance unique (SPOF)** pour le Ministère de la Fonction Publique.

### Ce qui a été réalisé

| Étape | Description | Statut |
|-------|-------------|--------|
| 1 | Migration VM Windows de VMware → Proxmox | ✅ Validé |
| 2 | Cluster Proxmox 2 nœuds + QDevice | ✅ Validé |
| 3 | Stockage partagé Ceph | ✅ Validé |
| 4 | Haute Disponibilité + Failback automatique | ✅ Validé |
| 5 | Proxmox Backup Server (PBS) | ✅ Validé |
| 6 | Tests Failover/Failback complets | ✅ Validé |

---

## 🏗️ Architecture finale
![Architecture HA Proxmox](./architecture-finale.png)

### Flux de protection

```
Niveau 1 — Ceph        → Réplication temps réel entre pve1 et pve2
Niveau 2 — HA Proxmox  → Failover/Failback automatique < 2 minutes
Niveau 3 — QDevice     → Maintien quorum, anti split-brain
Niveau 4 — PBS         → Backups chiffrés, rétention 3 mois
```

---

## 🔧 Composants

| Composant | Version | Rôle | IP |
|-----------|---------|------|-----|
| Proxmox VE | 9.1.1 | Hyperviseur | 149 / 158 |
| Ceph | 19.2.3 (Squid) | Stockage partagé | Cluster |
| QDevice | corosync-qnetd | Arbitre quorum | 192.168.75.160 |
| PBS | 4.2.0 | Backup Server | 192.168.75.161 |
| VM Windows | Windows 10 | VM migrée depuis VMware | Sur Ceph |
| CT nginx | Debian 12 | Serveur web | Sur Ceph |

---

## 📦 Prérequis

### Matériel (simulation VMware Workstation)

| VM | RAM | CPU | Disques | Réseau |
|----|-----|-----|---------|--------|
| pve1 | 7 GB | 2 vCPU | sda 20G + sdb 50G + sdc 50G | NAT |
| pve2 | 7 GB | 2 vCPU | sda 20G + sdb 50G + sdc 50G | NAT |
| QDevice | 512 MB | 1 vCPU | 8G | NAT |
| PBS | 2 GB | 2 vCPU | sda 15G + sdb 45G | NAT |

### Logiciels requis

- VMware Workstation Pro
- Proxmox VE 9.x ISO
- Proxmox Backup Server 4.x ISO
- WinSCP (pour transfert de fichiers)
- Navigateur web (accès interfaces Proxmox et PBS)

### ISOs nécessaires

| ISO | URL de téléchargement |
|-----|----------------------|
| Proxmox VE | https://www.proxmox.com/en/downloads/proxmox-virtual-environment |
| Proxmox Backup Server | https://www.proxmox.com/en/downloads/proxmox-backup-server |

---

## 📁 Structure du projet

```
proxmox-ha-infrastructure/
│
├── README.md                          ← ce fichier
├── LICENSE                            ← licence MIT
├── .gitignore                         ← exclut vmdk, iso, etc.
│
├── docs/
│   ├── 01-migration-vmware-proxmox.md     ← Migration VMware → Proxmox
│   ├── 02-cluster-qdevice-zfs.md          ← Cluster + QDevice + ZFS Replication
│   ├── 03-ceph-stockage-partage.md        ← Installation et config Ceph
│   ├── 04-failback-affinity-rules.md      ← Failback automatique Proxmox 9
│   ├── 05-pbs-backup-server.md            ← Installation et config PBS
│   ├── 06-tests-failover-failback.md      ← Tests complets validés
│   └── troubleshooting.md                 ← Tous les problèmes et solutions
│
└── scripts/
    ├── post-import-config.sh              ← Config post-import VM VMware
    ├── setup-ceph.sh                      ← Automatisation config Ceph
    ├── setup-pbs-disk.sh                  ← Préparation disque PBS
    └── check-cluster-health.sh            ← Vérification santé cluster
```

---

## 📚 Documentation

La documentation complète est dans le dossier `docs/` :

| Fichier | Contenu |
|---------|---------|
| `01-migration-vmware-proxmox.md` | Export OVF, transfert WinSCP, import qm importovf, config UEFI |
| `02-cluster-qdevice-zfs.md` | Création cluster, QDevice, ZFS Replication, HA, tests |
| `03-ceph-stockage-partage.md` | Installation Ceph, MON, MGR, OSD, Pool, migration VMs |
| `04-failback-affinity-rules.md` | Affinity Rules Proxmox 9, failback automatique |
| `05-pbs-backup-server.md` | Installation PBS, Datastore, connexion Proxmox, jobs backup |
| `06-tests-failover-failback.md` | 4 tests complets avec procédures et résultats |
| `troubleshooting.md` | Guide de dépannage exhaustif |

---

## ✅ Résultats des tests

### Tests Failover/Failback

| Test | Scénario | Résultat | Automatique | Perte données |
|------|---------|----------|-------------|---------------|
| 1 | Failover pve1 → VM 300 sur pve2 | ✅ OK | ✅ Oui | ✅ Aucune |
| 2 | Failback pve1 → VM 300 sur pve1 | ✅ OK | ✅ Oui | ✅ Aucune |
| 3 | Failover pve2 → CT 400 sur pve1 | ✅ OK | ✅ Oui | ✅ Aucune |
| 4 | Failback pve2 → CT 400 sur pve2 | ✅ OK | ✅ Oui | ✅ Aucune |

### Tests Backup/Restauration PBS

| Test | Résultat |
|------|----------|
| Backup VM 300 (37.58 GB) | ✅ OK |
| Backup CT 400 (652 MB) | ✅ OK |
| Restauration CT 401 depuis PBS | ✅ OK |

### Performances mesurées

| Métrique | Valeur observée |
|---------|----------------|
| Temps failover | < 2 minutes |
| Temps failback (Ceph) | < 30 secondes |
| Migration live Ceph | < 30 secondes |
| Perte de données | 0 |

---

## 🔖 Versions utilisées

| Logiciel | Version |
|---------|---------|
| Proxmox VE | 9.1.1 |
| Ceph | 19.2.3-pve4 (Squid) |
| PBS | 4.2.0 |
| Debian | 12 (Bookworm) |
| Kernel | 6.17.2-1-pve |
| WinSCP | dernière version |
| VMware Workstation | Pro (dernière version) |

---

## 👤 Auteur

**Stagiaire Informatique**  
Ministère de la Fonction Publique — Cameroun  
Mai 2026

---

## 📄 Licence

Ce projet est sous licence MIT — voir le fichier [LICENSE](LICENSE) pour les détails.

---

> ⚠️ **Note importante** : Ce projet a été entièrement validé en environnement de simulation avant tout déploiement en production. Toutes les procédures sont reproductibles et documentées étape par étape.
