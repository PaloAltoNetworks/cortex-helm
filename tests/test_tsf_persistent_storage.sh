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

# P1: PVC on, triggers off: volume, per-node mount, env and OpenShift permission; no trigger env.
out=$(render "$CHART" "${ON[@]}" --set serviceAccount.openshift.scc.create=true)
for want in 'claimName: "cortex-tsf"' \
            'subPathExpr: "tsf-test/$(XDR_NODE_NAME)"' \
            'mountPath: /var/lib/cortex-tsf' \
            'fieldPath: spec.nodeName' \
            '- persistentVolumeClaim'; do
    has "$out" "$want" && ok "P1 renders: $want" || bad "P1 is missing: $want"
done
env_is "$out" XDR_TSF_STORAGE_DIR /var/lib/cortex-tsf && ok "P1 XDR_TSF_STORAGE_DIR" || bad "P1 XDR_TSF_STORAGE_DIR"
has "$out" "_TRIGGER_" && bad "P1 renders trigger env" || ok "P1 no trigger env"
has "$out" "LOG_SNAPSHOT" && bad "P1 renders old snapshot env" || ok "P1 no old snapshot env"

# P2: memory trigger only, with defaults.
out=$(render "$CHART" "${ON[@]}" "${MEM[@]}")
env_is "$out" XDR_TSF_MEMORY_TRIGGER_PERCENT 90 && env_is "$out" XDR_TSF_MEMORY_TRIGGER_SECONDS 300 \
    && ok "P2 memory trigger defaults 90/300" || bad "P2 memory trigger defaults"
has "$out" "XDR_TSF_CPU_TRIGGER" && bad "P2 renders CPU trigger" || ok "P2 no CPU trigger"

# P3: CPU trigger only, custom values.
out=$(render "$CHART" "${ON[@]}" "${CPU[@]}" --set $P.cpuTsfTrigger.percent=80 --set $P.cpuTsfTrigger.seconds=120)
env_is "$out" XDR_TSF_CPU_TRIGGER_PERCENT 80 && env_is "$out" XDR_TSF_CPU_TRIGGER_SECONDS 120 \
    && ok "P3 CPU trigger 80/120" || bad "P3 CPU trigger 80/120"
has "$out" "XDR_TSF_MEMORY_TRIGGER" && bad "P3 renders memory trigger" || ok "P3 no memory trigger"

# P4: both triggers; percent 100 is accepted.
out=$(render "$CHART" "${ON[@]}" "${MEM[@]}" "${CPU[@]}" --set $P.memoryTsfTrigger.percent=100)
env_is "$out" XDR_TSF_MEMORY_TRIGGER_PERCENT 100 && env_is "$out" XDR_TSF_CPU_TRIGGER_PERCENT 90 \
    && ok "P4 both triggers rendered" || bad "P4 both triggers rendered"

# Trailing slash in path is trimmed.
render "$CHART" "${ON[@]}" --set $P.path=a/b/ | grep -qF 'subPathExpr: "a/b/$(XDR_NODE_NAME)"' \
    && ok "trailing slash in path is trimmed" || bad "trailing slash in path is not trimmed"

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
