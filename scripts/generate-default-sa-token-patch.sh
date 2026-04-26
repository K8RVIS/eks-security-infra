#!/usr/bin/env bash
set -euo pipefail

OVERLAY="${1:-manifests/overlays/team-a}"
SERVICE_ACCOUNT_FILE_NAME="${2:-default-serviceaccount.yaml}"
PATCH_FILE_NAME="${3:-default-sa-token-patch.yaml}"

KUSTOMIZATION_PATH="$OVERLAY/kustomization.yaml"
SERVICE_ACCOUNT_PATH="$OVERLAY/$SERVICE_ACCOUNT_FILE_NAME"
PATCH_PATH="$OVERLAY/$PATCH_FILE_NAME"

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 is not installed or not in PATH."
    exit 1
  fi
}

add_kustomization_entry() {
  local section="$1"
  local entry="$2"
  local file="$3"
  local tmp_file

  if grep -qxF "  - $entry" "$file"; then
    return
  fi

  tmp_file="$(mktemp)"

  awk -v section="$section" -v entry="  - $entry" '
    BEGIN {
      in_section = 0
      section_seen = 0
      added = 0
    }

    $0 ~ "^" section ":[[:space:]]*$" {
      print
      in_section = 1
      section_seen = 1
      next
    }

    in_section && $0 ~ "^[A-Za-z0-9_-]+:[[:space:]]*$" {
      if (!added) {
        print entry
        added = 1
      }
      in_section = 0
    }

    {
      print
    }

    END {
      if (!section_seen) {
        print ""
        print section ":"
        print entry
      } else if (in_section && !added) {
        print entry
      }
    }
  ' "$file" > "$tmp_file"

  mv "$tmp_file" "$file"
}

render_patch_doc() {
  local kind="$1"
  local api_version="$2"
  local name="$3"

  if [[ "$kind" == "CronJob" ]]; then
    cat <<EOF
apiVersion: $api_version
kind: $kind
metadata:
  name: $name
spec:
  jobTemplate:
    spec:
      template:
        spec:
          automountServiceAccountToken: false
EOF
  elif [[ "$kind" == "Pod" ]]; then
    cat <<EOF
apiVersion: $api_version
kind: $kind
metadata:
  name: $name
spec:
  automountServiceAccountToken: false
EOF
  else
    cat <<EOF
apiVersion: $api_version
kind: $kind
metadata:
  name: $name
spec:
  template:
    spec:
      automountServiceAccountToken: false
EOF
  fi
}

get_service_account_name() {
  local kind="$1"
  local json="$2"

  if [[ "$kind" == "CronJob" ]]; then
    printf '%s\n' "$json" | jq -r '.spec.jobTemplate.spec.template.spec.serviceAccountName // ""'
  elif [[ "$kind" == "Pod" ]]; then
    printf '%s\n' "$json" | jq -r '.spec.serviceAccountName // ""'
  else
    printf '%s\n' "$json" | jq -r '.spec.template.spec.serviceAccountName // ""'
  fi
}

get_automount_value() {
  local kind="$1"
  local json="$2"

  if [[ "$kind" == "CronJob" ]]; then
    printf '%s\n' "$json" | jq -r '.spec.jobTemplate.spec.template.spec.automountServiceAccountToken // "<unset>"'
  elif [[ "$kind" == "Pod" ]]; then
    printf '%s\n' "$json" | jq -r '.spec.automountServiceAccountToken // "<unset>"'
  elif [[ "$kind" == "ServiceAccount" ]]; then
    printf '%s\n' "$json" | jq -r '.automountServiceAccountToken // "<unset>"'
  else
    printf '%s\n' "$json" | jq -r '.spec.template.spec.automountServiceAccountToken // "<unset>"'
  fi
}

ensure_command kubectl
ensure_command jq

if [[ ! -f "$KUSTOMIZATION_PATH" ]]; then
  echo "kustomization.yaml not found: $KUSTOMIZATION_PATH"
  exit 1
fi

echo "[1] Render overlay"
RENDERED="$(kubectl kustomize "$OVERLAY")"

echo "[2] Generate default ServiceAccount resource"
cat > "$SERVICE_ACCOUNT_PATH" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
automountServiceAccountToken: false
EOF

echo "[3] Parse rendered resources and build workload patches"
TMP_PATCH_DOCS="$(mktemp)"
trap 'rm -f "$TMP_PATCH_DOCS"' EXIT
: > "$TMP_PATCH_DOCS"

SUPPORTED_KINDS_REGEX='^(Pod|Deployment|StatefulSet|DaemonSet|Job|CronJob|ReplicaSet|ReplicationController)$'
FIRST_DOC="true"

DOC=""
while IFS= read -r line; do
  if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
    if [[ -n "$DOC" ]]; then
      JSON="$(printf '%s\n' "$DOC" | kubectl create --dry-run=client --validate=false -f - -o json 2>/dev/null || true)"

      if [[ -n "$JSON" ]]; then
        KIND="$(printf '%s\n' "$JSON" | jq -r '.kind')"
        API_VERSION="$(printf '%s\n' "$JSON" | jq -r '.apiVersion')"
        NAME="$(printf '%s\n' "$JSON" | jq -r '.metadata.name')"

        if [[ "$KIND" =~ $SUPPORTED_KINDS_REGEX ]]; then
          SA="$(get_service_account_name "$KIND" "$JSON")"

          if [[ -n "$SA" && "$SA" != "default" ]]; then
            echo "Skipping $KIND/$NAME: non-default ServiceAccount"
          else
            echo "Adding patch for $KIND/$NAME"

            if [[ "$FIRST_DOC" == "true" ]]; then
              FIRST_DOC="false"
            else
              printf '%s\n' "---" >> "$TMP_PATCH_DOCS"
            fi

            render_patch_doc "$KIND" "$API_VERSION" "$NAME" >> "$TMP_PATCH_DOCS"
          fi
        fi
      fi

      DOC=""
    fi

    continue
  fi

  DOC="${DOC}${line}"$'\n'
done <<< "$RENDERED"

if [[ -n "$DOC" ]]; then
  JSON="$(printf '%s\n' "$DOC" | kubectl create --dry-run=client --validate=false -f - -o json 2>/dev/null || true)"

  if [[ -n "$JSON" ]]; then
    KIND="$(printf '%s\n' "$JSON" | jq -r '.kind')"
    API_VERSION="$(printf '%s\n' "$JSON" | jq -r '.apiVersion')"
    NAME="$(printf '%s\n' "$JSON" | jq -r '.metadata.name')"

    if [[ "$KIND" =~ $SUPPORTED_KINDS_REGEX ]]; then
      SA="$(get_service_account_name "$KIND" "$JSON")"

      if [[ -n "$SA" && "$SA" != "default" ]]; then
        echo "Skipping $KIND/$NAME: non-default ServiceAccount"
      else
        echo "Adding patch for $KIND/$NAME"

        if [[ "$FIRST_DOC" == "true" ]]; then
          FIRST_DOC="false"
        else
          printf '%s\n' "---" >> "$TMP_PATCH_DOCS"
        fi

        render_patch_doc "$KIND" "$API_VERSION" "$NAME" >> "$TMP_PATCH_DOCS"
      fi
    fi
  fi
fi

echo "[4] Write workload patch file"
cp "$TMP_PATCH_DOCS" "$PATCH_PATH"

echo "[5] Register generated files in kustomization.yaml"
add_kustomization_entry "resources" "$SERVICE_ACCOUNT_FILE_NAME" "$KUSTOMIZATION_PATH"
add_kustomization_entry "patches" "path: $PATCH_FILE_NAME" "$KUSTOMIZATION_PATH"

echo "[6] Verify"
VERIFY_RENDERED="$(kubectl kustomize "$OVERLAY")"
VERIFY_ROWS="$(mktemp)"
trap 'rm -f "$TMP_PATCH_DOCS" "$VERIFY_ROWS"' EXIT
: > "$VERIFY_ROWS"

DOC=""
while IFS= read -r line; do
  if [[ "$line" =~ ^---[[:space:]]*$ ]]; then
    if [[ -n "$DOC" ]]; then
      JSON="$(printf '%s\n' "$DOC" | kubectl create --dry-run=client --validate=false -f - -o json 2>/dev/null || true)"
      DOC=""

      if [[ -n "$JSON" ]]; then
        KIND="$(printf '%s\n' "$JSON" | jq -r '.kind')"
        NAME="$(printf '%s\n' "$JSON" | jq -r '.metadata.name')"

        if [[ "$KIND" == "ServiceAccount" && "$NAME" == "default" ]]; then
          AUTOMOUNT="$(get_automount_value "$KIND" "$JSON")"
          STATUS="CHECK"
          [[ "$AUTOMOUNT" == "false" ]] && STATUS="OK"
          printf '%s\t%s\t%s\t%s\t%s\n' "$KIND" "$NAME" "-" "$AUTOMOUNT" "$STATUS" >> "$VERIFY_ROWS"
        elif [[ "$KIND" =~ $SUPPORTED_KINDS_REGEX ]]; then
          SA="$(get_service_account_name "$KIND" "$JSON")"

          if [[ -z "$SA" || "$SA" == "default" ]]; then
            AUTOMOUNT="$(get_automount_value "$KIND" "$JSON")"
            STATUS="CHECK"
            [[ "$AUTOMOUNT" == "false" ]] && STATUS="OK"

            if [[ -z "$SA" ]]; then
              SA="<default>"
            fi

            printf '%s\t%s\t%s\t%s\t%s\n' "$KIND" "$NAME" "$SA" "$AUTOMOUNT" "$STATUS" >> "$VERIFY_ROWS"
          fi
        fi
      fi
    fi

    continue
  fi

  DOC="${DOC}${line}"$'\n'
done <<< "$VERIFY_RENDERED"

if [[ -n "$DOC" ]]; then
  JSON="$(printf '%s\n' "$DOC" | kubectl create --dry-run=client --validate=false -f - -o json 2>/dev/null || true)"

  if [[ -n "$JSON" ]]; then
    KIND="$(printf '%s\n' "$JSON" | jq -r '.kind')"
    NAME="$(printf '%s\n' "$JSON" | jq -r '.metadata.name')"

    if [[ "$KIND" == "ServiceAccount" && "$NAME" == "default" ]]; then
      AUTOMOUNT="$(get_automount_value "$KIND" "$JSON")"
      STATUS="CHECK"
      [[ "$AUTOMOUNT" == "false" ]] && STATUS="OK"
      printf '%s\t%s\t%s\t%s\t%s\n' "$KIND" "$NAME" "-" "$AUTOMOUNT" "$STATUS" >> "$VERIFY_ROWS"
    elif [[ "$KIND" =~ $SUPPORTED_KINDS_REGEX ]]; then
      SA="$(get_service_account_name "$KIND" "$JSON")"

      if [[ -z "$SA" || "$SA" == "default" ]]; then
        AUTOMOUNT="$(get_automount_value "$KIND" "$JSON")"
        STATUS="CHECK"
        [[ "$AUTOMOUNT" == "false" ]] && STATUS="OK"

        if [[ -z "$SA" ]]; then
          SA="<default>"
        fi

        printf '%s\t%s\t%s\t%s\t%s\n' "$KIND" "$NAME" "$SA" "$AUTOMOUNT" "$STATUS" >> "$VERIFY_ROWS"
      fi
    fi
  fi
fi

{
  printf 'Kind\tName\tServiceAcct\tAutomount\tStatus\n'
  sort -k1,1 -k2,2 "$VERIFY_ROWS"
} | column -t -s $'\t'
