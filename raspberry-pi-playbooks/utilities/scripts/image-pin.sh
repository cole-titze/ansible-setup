#!/bin/bash
# Show, roll back, or hold the image pins in cluster-maintenance/image-pins
# (see cluster/kubernetes/cluster-maintenance). Needs kubectl, curl and jq.
#
#   image-pin.sh status
#   image-pin.sh rollback <name>          back to <name>.previous and hold it there
#   image-pin.sh set <name> <tag|digest>  e.g. a commit tag like 0f1c2bb; holds it
#   image-pin.sh release <name>           drop the hold; the 4:00 run moves it to :latest again
set -euo pipefail

pins() { kubectl get configmap -n cluster-maintenance image-pins -o json | jq -c '.data // {}'; }
get() { pins | jq -r --arg k "$1" '.[$k] // empty'; }
patch() { kubectl patch configmap -n cluster-maintenance image-pins --type merge -p "$1" >/dev/null; }

# Same apply step the nightly updater runs, so pinned workloads switch now
apply() {
  kubectl get configmap -n cluster-maintenance nightly-updater-script -o jsonpath='{.data.update\.sh}' | APPLY_ONLY=1 sh
}

# Pins a name to <ref> and holds it, keeping the old value as <name>.previous
pin() {
  local key=$1 new=$2 cur=$3 why=$4
  patch "$(jq -nc --arg k "$key" --arg v "$new" --arg p "$cur" --arg h "$why" \
    '{data: {($k): $v, ($k + ".previous"): $p, ($k + ".hold"): $h}}')"
  echo "$key: $cur -> $new (held)"
  apply
}

cmd=${1:-status}
key=${2:-}
[ "$cmd" = status ] || [ -n "$key" ] || { sed -n '5,8p' "$0"; exit 1; }
if [ -n "$key" ]; then
  cur=$(get "$key")
  [ -n "$cur" ] || { echo "no pin named $key"; exit 1; }
  repo=${cur%@*}
fi

case $cmd in
  status)
    pins | jq -r 'to_entries[] | "\(.key)\t\(.value)"' | column -t -s $'\t' ;;
  rollback)
    prev=$(get "$key.previous")
    [ -n "$prev" ] || { echo "$key has no previous pin"; exit 1; }
    pin "$key" "$prev" "$cur" "rolled back $(date +%F)" ;;
  set)
    ref=${3:?tag or sha256 digest}
    if [[ $ref != sha256:* ]]; then
      path=${repo#ghcr.io/}
      tok=$(curl -fsS "https://ghcr.io/token?scope=repository:$path:pull" | jq -r .token)
      ref=$(curl -fsSI -H "Authorization: Bearer $tok" \
        -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json" \
        "https://ghcr.io/v2/$path/manifests/$ref" | tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" { print $2 }')
      [[ $ref == sha256:* ]] || { echo "tag $3 not found in $repo"; exit 1; }
    fi
    pin "$key" "$repo@$ref" "$cur" "set to $3 $(date +%F)" ;;
  release)
    patch "$(jq -nc --arg k "$key.hold" '{data: {($k): null}}')"
    echo "$key: hold removed; the 4:00 run moves it to the promoted build" ;;
  *)
    sed -n '5,8p' "$0"; exit 1 ;;
esac
