#!/bin/bash
# Adapt google/bbr v3 net/ipv4/tcp_bbr.c to the 7.2 kernel API.
# Differences found against 7.2 include/net/tcp.h:
#   - struct tcp_congestion_ops.tso_segs is gone; 7.2 has min_tso_segs (u32 (*)(struct sock *))
#     bbr_tso_segs_goal() has exactly that signature, so it is wired in directly.
#   - struct tcp_congestion_ops.skb_marked_lost was removed.
#   - TCP_CONG_WANTS_CE_EVENTS was removed (7.2 uses TCP_CONG_NEEDS_ECN/ACCECN family).
set -eu
KDIR=${1:?usage: patch.sh KERNEL_TREE}
F="$KDIR/net/ipv4/tcp_bbr.c"
[ -f "$F" ] || { echo "patch: no $F" >&2; exit 1; }

# 1. tso_segs -> min_tso_segs, backed by bbr_tso_segs_goal
sed -i 's#\.tso_segs[[:space:]]*=[[:space:]]*bbr_tso_segs,#.min_tso_segs\t= bbr_tso_segs_goal,#' "$F"
grep -qE '\.min_tso_segs[[:space:]]*=[[:space:]]*bbr_tso_segs_goal,' "$F" || { echo 'patch: min_tso_segs not applied' >&2; exit 1; }

# 2. drop the skb_marked_lost callback (member no longer exists)
sed -i '/\.skb_marked_lost[[:space:]]*=[[:space:]]*bbr_skb_marked_lost,/d' "$F"
! grep -q '\.skb_marked_lost' "$F" || { echo 'patch: skb_marked_lost still present' >&2; exit 1; }

# 3. TCP_CONG_WANTS_CE_EVENTS is gone in 7.2
sed -i 's#TCP_CONG_NON_RESTRICTED | TCP_CONG_WANTS_CE_EVENTS#TCP_CONG_NON_RESTRICTED#' "$F"
! grep -q 'TCP_CONG_WANTS_CE_EVENTS' "$F" || { echo 'patch: CE events flag still present' >&2; exit 1; }

# 4. 7.2's struct tcp_bbr_info dropped bbr_mode/bbr_phase/bbr_version/
#    bbr_inflight_lo/bbr_inflight_hi/bbr_extra_acked, so bbr_get_info() no longer
#    compiles. It only fills the INET_DIAG_BBRINFO sockopt for `ss -i`; the
#    congestion control itself does not use it, so the callback is dropped.
awk '/^static size_t bbr_get_info\(/{skip=1} skip&&/^}/{skip=0; next} !skip' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
sed -i '/\.get_info[[:space:]]*=[[:space:]]*bbr_get_info,/d' "$F"
! grep -q 'bbr_get_info' "$F" || { echo 'patch: bbr_get_info still present' >&2; exit 1; }

echo "patch: adapted $F to the 7.2 tcp_congestion_ops API"
sed -n '/static struct tcp_congestion_ops tcp_bbr_cong_ops/,/^};/p' "$F"
