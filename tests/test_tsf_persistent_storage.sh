#!/usr/bin/env bash
# Render tests for tsfPersistentStorage. Needs helm and git.
# Usage: tests/test_tsf_persistent_storage.sh [base-ref]   (default base-ref: origin/master)
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHART="$ROOT/charts/cortex-agent"
BASE_REF=${1:-origin/master}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=tsfPersistentStorage
ON=(--set $P.enabled=true --set $P.pvcName=cortex-tsf --set $P.path=tsf-test)
MEM=(--set $P.memoryTsfTrigger.enabled=true)
CPU=(--set $P.cpuTsfTrigger.enabled=true)
fails=0

ok()   { echo "PASS $*"; }
bad()  { echo "FAIL $*"; fails=$((fails + 1)); }
render() { helm template t "$@" 2>&1; }
has()    { grep -qF -- "$2" <<<"$1"; }
env_is() { grep -A1 -- "name: $2\$" <<<"$1" | grep -qF -- "value: \"$3\""; }

# P0 / R1: with the flag off, the output matches the base chart byte for byte,
# except the helm.sh/chart label, which carries the chart version.
git -C "$ROOT" archive "$BASE_REF" charts/cortex-agent | tar -x -C "$TMP"
render_nover() { render "$@" | grep -v '^ *helm.sh/chart: '; }
for extra in "" "--set serviceAccount.openshift.scc.create=true"; do
    # shellcheck disable=SC2086
    if cmp -s <(render_nover "$TMP/charts/cortex-agent" $extra) <(render_nover "$CHART" $extra); then
        ok "P0 flag off is identical to $BASE_REF ${extra:-(defaults)}"
    else
        bad "P0 flag off differs from $BASE_REF ${extra:-(defaults)}"
    fi
done

# S1: helm template has no cluster, so the PVC lookup is empty and the feature is skipped:
# a WARNING comment, the agent still renders, and no TSF env, mount, volume or SCC entry.
# The mounted path (PVC Bound and RWX) is covered by charts/cortex-agent/tests (helm unittest).
out=$(render "$CHART" "${ON[@]}" "${MEM[@]}" "${CPU[@]}" --set serviceAccount.openshift.scc.create=true)
has "$out" '# WARNING: TSF persistent storage skipped: PVC "cortex-tsf" in namespace "cortex-xdr"' \
    && ok "S1 skipped WARNING rendered" || bad "S1 skipped WARNING missing"
has "$out" "kind: DaemonSet" && ok "S1 agent DaemonSet rendered" || bad "S1 agent DaemonSet missing"
for unwanted in 'tsf-storage' 'XDR_TSF_' 'XDR_NODE_NAME' '- persistentVolumeClaim'; do
    has "$out" "$unwanted" && bad "S1 renders: $unwanted" || ok "S1 does not render: $unwanted"
done

# S2: the PVC name in the WARNING is escaped.
render "$CHART" "${ON[@]}" --set "$P.pvcName=a\"b" | grep -qF 'PVC "a\"b"' \
    && ok "S2 PVC name is escaped in the WARNING" || bad "S2 PVC name is not escaped in the WARNING"

# Invalid configurations fail with a clear message.
expect_fail() {
    local msg=$1 out; shift
    # Capture first: helm exits non-zero here, and with pipefail a pipe into grep would report that.
    out=$(render "$CHART" "$@")
    if has "$out" "$msg"; then ok "rejected: $* -> $msg"; else bad "not rejected: $*"; fi
}
expect_fail "requires tsfPersistentStorage.pvcName" --set $P.enabled=true
expect_fail "requires tsfPersistentStorage.path"    --set $P.enabled=true --set $P.pvcName=x
expect_fail "must be relative"                      "${ON[@]}" --set $P.path=/abs
expect_fail "must not contain '..'"                 "${ON[@]}" --set $P.path=a/../b
expect_fail "may contain only"                      "${ON[@]}" --set "$P.path=a\$b"
expect_fail "memoryTsfTrigger.enabled=true requires tsfPersistentStorage.enabled=true" "${MEM[@]}"
expect_fail "cpuTsfTrigger.enabled=true requires tsfPersistentStorage.enabled=true"    "${CPU[@]}"
for v in 0 101 -5 abc 50.5; do
    expect_fail "memoryTsfTrigger.percent must be an integer from 1 to 100" "${ON[@]}" "${MEM[@]}" --set $P.memoryTsfTrigger.percent=$v
done
for v in 0 -1 abc; do
    expect_fail "cpuTsfTrigger.seconds must be a positive integer" "${ON[@]}" "${CPU[@]}" --set $P.cpuTsfTrigger.seconds=$v
done

# A disabled trigger with bad values is ignored.
render "$CHART" "${ON[@]}" --set $P.cpuTsfTrigger.percent=0 >/dev/null \
    && ok "disabled trigger values are not validated" || bad "disabled trigger values are validated"

# Valid paths that look unusual are accepted.
render "$CHART" "${ON[@]}" --set $P.path=cortex/prod-1.a_b >/dev/null \
    && ok "path cortex/prod-1.a_b is accepted" || bad "path cortex/prod-1.a_b is rejected"

echo
if [ "$fails" -eq 0 ]; then echo "OVERALL: PASS"; else echo "OVERALL: FAIL ($fails)"; fi
[ "$fails" -eq 0 ]
