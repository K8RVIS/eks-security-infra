#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
teams=(team-a team-b team-c team-d)

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"

  if ! rg -U -q "$pattern" "$file_path"; then
    fail "$message"
  fi
}

assert_not_contains() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"

  if rg -U -q "$pattern" "$file_path"; then
    fail "$message"
  fi
}

for team in "${teams[@]}"; do
  rendered_manifest="$(mktemp)"
  trap 'rm -f "$rendered_manifest"' EXIT

  kubectl kustomize "$repo_root/manifests/overlays/$team" >"$rendered_manifest"

  assert_contains "$rendered_manifest" "kind: Deployment" "Expected the web and api deployments to render for $team."
  assert_contains "$rendered_manifest" "kind: Ingress" "Expected the web ingress to render for $team."
  assert_contains "$rendered_manifest" "kind: StatefulSet" "Expected the db workload to render as a StatefulSet for $team."
  assert_contains "$rendered_manifest" "name: web" "Expected the web workload resources to render for $team."
  assert_contains "$rendered_manifest" "name: api" "Expected the api workload resources to render for $team."
  assert_contains "$rendered_manifest" "name: db" "Expected the db workload resources to render for $team."
  assert_contains "$rendered_manifest" "volumeClaimTemplates:" "Expected the db workload to request persistent storage for $team."
  assert_contains "$rendered_manifest" "serviceAccountName: default" "Expected the api deployment to keep using the default ServiceAccount for $team."
  assert_contains "$rendered_manifest" "automountServiceAccountToken: true" "Expected the api deployment to mount the ServiceAccount token for $team."
  assert_contains "$rendered_manifest" "name: EXTERNAL_POSTGRES_PASSWORD\n[[:space:]]+value: training-external-password" "Expected the api deployment to expose a plaintext external database password for $team."
  assert_not_contains "$rendered_manifest" "^[[:space:]]*tls:" "Ingress TLS must stay disabled in the vulnerable baseline for $team."

  rm -f "$rendered_manifest"
  trap - EXIT
done

printf 'training baseline manifests verified for %s teams\n' "${#teams[@]}"
