#!/bin/bash
# =============================================================================
# check-cluster-health.sh
# Vérification complète de la santé du cluster Proxmox + Ceph + HA + PBS
# Usage : ./check-cluster-health.sh
# Auteur : Stagiaire Informatique — Ministère de la Fonction Publique
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC}  $1"; }

echo "=============================================="
echo "  Vérification santé cluster clusterMINFOPRA"
echo "  $(date)"
echo "=============================================="
echo ""

# --- 1. Cluster Proxmox ---
info "1/5 — Vérification cluster Proxmox..."
NODES=$(pvecm status 2>/dev/null | grep "^Nodes:" | awk '{print $2}')
QUORATE=$(pvecm status 2>/dev/null | grep "^Quorate:" | awk '{print $2}')

[ "$NODES" = "2" ]      && ok "Cluster : 2 nœuds détectés" || err "Cluster : $NODES nœud(s) — attendu 2"
[ "$QUORATE" = "Yes" ]  && ok "Quorum  : Yes"               || err "Quorum  : $QUORATE"

# --- 2. Ceph ---
echo ""
info "2/5 — Vérification Ceph..."
CEPH_HEALTH=$(ceph health 2>/dev/null | awk '{print $1}')
OSD_UP=$(ceph osd stat 2>/dev/null | grep -oP '\d+ up' | awk '{print $1}')

[ "$CEPH_HEALTH" = "HEALTH_OK" ]   && ok "Ceph health : HEALTH_OK" || warn "Ceph health : $CEPH_HEALTH"
[ "$OSD_UP" = "2" ]                && ok "OSDs : 2 up"             || err "OSDs up : $OSD_UP — attendu 2"

# --- 3. HA Manager ---
echo ""
info "3/5 — Vérification HA..."
HA_QUORUM=$(ha-manager status 2>/dev/null | grep "^quorum" | awk '{print $2}')
VM300=$(ha-manager status 2>/dev/null | grep "vm:300" | awk '{print $2}' | tr -d '(,')
CT400=$(ha-manager status 2>/dev/null | grep "ct:400" | awk '{print $2}' | tr -d '(,')

[ "$HA_QUORUM" = "OK" ]     && ok "HA Quorum : OK"                  || err "HA Quorum : $HA_QUORUM"
[ "$VM300" = "pve1" ]       && ok "VM 300 : sur pve1 (préféré)"     || warn "VM 300 : sur $VM300"
[ "$CT400" = "pve2" ]       && ok "CT 400 : sur pve2 (préféré)"     || warn "CT 400 : sur $CT400"

# --- 4. Stockage ---
echo ""
info "4/5 — Vérification stockage..."
VM_POOL=$(pvesm status 2>/dev/null | grep "^vm-pool" | awk '{print $3}')
[ "$VM_POOL" = "active" ] && ok "vm-pool (Ceph) : active" || err "vm-pool (Ceph) : $VM_POOL"

PBS_STORAGE=$(pvesm status 2>/dev/null | grep "^pbs-backup" | awk '{print $3}')
[ "$PBS_STORAGE" = "active" ] && ok "pbs-backup (PBS) : active" || warn "pbs-backup (PBS) : $PBS_STORAGE"

# --- 5. VMs ---
echo ""
info "5/5 — Vérification VMs/CTs..."
VM300_STATUS=$(qm status 300 2>/dev/null | awk '{print $2}')
CT400_STATUS=$(pct status 400 2>/dev/null | awk '{print $2}')

[ "$VM300_STATUS" = "running" ] && ok "VM 300 (Windows) : running" || err "VM 300 : $VM300_STATUS"
[ "$CT400_STATUS" = "running" ] && ok "CT 400 (nginx)   : running" || err "CT 400 : $CT400_STATUS"

echo ""
echo "=============================================="
echo "  Vérification terminée"
echo "=============================================="

---

#!/bin/bash
# =============================================================================
# setup-pbs-disk.sh
# Préparation du disque backup pour PBS
# Usage : ./setup-pbs-disk.sh /dev/sdb /mnt/backup
# Auteur : Stagiaire Informatique — Ministère de la Fonction Publique
# =============================================================================

DISK=${1:-/dev/sdb}
MOUNT=${2:-/mnt/backup}

echo "=== Préparation disque PBS ==="
echo "Disque  : $DISK"
echo "Montage : $MOUNT"
echo ""

# Vérification
[ ! -b "$DISK" ] && echo "Erreur : $DISK n'existe pas" && exit 1

# Installation parted si nécessaire
which parted &>/dev/null || apt install -y parted

# Partitionnement
echo "[1/5] Création table de partition GPT..."
parted "$DISK" mklabel gpt
parted "$DISK" mkpart primary ext4 0% 100%

# Formatage
echo "[2/5] Formatage en ext4..."
mkfs.ext4 "${DISK}1"

# Montage
echo "[3/5] Création point de montage..."
mkdir -p "$MOUNT"

echo "[4/5] Montage du disque..."
mount "${DISK}1" "$MOUNT"

# Persistance
echo "[5/5] Ajout dans /etc/fstab..."
grep -q "${DISK}1" /etc/fstab || \
  echo "${DISK}1 $MOUNT ext4 defaults 0 2" >> /etc/fstab

# Vérification
echo ""
echo "=== Résultat ==="
df -h "$MOUNT"
echo ""
echo "✅ Disque prêt pour le Datastore PBS : $MOUNT"
