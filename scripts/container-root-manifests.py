import argparse
import difflib
import re
from pathlib import Path


WORKLOAD_KINDS = {
    "Deployment",
    "StatefulSet",
    "DaemonSet",
    "ReplicaSet",
    "ReplicationController",
    "Job",
    "CronJob",
    "Pod",
}

CONTAINER_LIST_KEYS = {
    "containers",
    "initContainers",
    "ephemeralContainers",
}

SECURITY_CONTEXT_VALUES = {
    "runAsNonRoot": "true",
    "runAsUser": "1000",
    "readOnlyRootFilesystem": "true",
}


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0].rstrip()


def indentation(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def scalar_value(line: str) -> str:
    return line.split(":", 1)[1].strip().strip('"').strip("'")


def find_yaml_files(root: Path) -> list[Path]:
    files = []
    for pattern in ("*.yaml", "*.yml"):
        files.extend(root.rglob(pattern))

    return sorted(
        path for path in files
        if path.is_file() and ".git" not in path.parts
    )


def split_documents_with_separators(text: str) -> list[str]:
    parts = re.split(r"(?m)(^---\s*$)", text)
    documents = []
    current = ""

    for part in parts:
        if re.match(r"(?m)^---\s*$", part):
            if current:
                documents.append(current)
            current = part + "\n"
        else:
            current += part

    if current:
        documents.append(current)

    return documents


def top_level_value(lines: list[str], key: str) -> str | None:
    pattern = re.compile(rf"^{re.escape(key)}:\s*(.+)?$")

    for line in lines:
        clean = strip_comment(line)
        if not clean or indentation(clean) != 0:
            continue

        match = pattern.match(clean)
        if match:
            return (match.group(1) or "").strip().strip('"').strip("'")

    return None


def metadata_name(lines: list[str]) -> str:
    in_metadata = False

    for line in lines:
        clean = strip_comment(line)
        if not clean:
            continue

        indent = indentation(clean)

        if clean == "metadata:" and indent == 0:
            in_metadata = True
            continue

        if in_metadata and indent == 0:
            in_metadata = False

        if in_metadata and indent == 2 and clean.strip().startswith("name:"):
            return scalar_value(clean)

    return "unknown"


def collect_container_blocks(lines: list[str]) -> list[dict]:
    blocks = []
    active_list = None
    active_list_indent = 0
    active_container = None

    for index, raw_line in enumerate(lines):
        clean = strip_comment(raw_line)
        if not clean.strip():
            continue

        indent = indentation(clean)
        stripped = clean.strip()

        if active_list is not None and indent <= active_list_indent:
            if active_container:
                active_container["end"] = index
                blocks.append(active_container)
                active_container = None
            active_list = None

        for key in CONTAINER_LIST_KEYS:
            if stripped == f"{key}:":
                if active_container:
                    active_container["end"] = index
                    blocks.append(active_container)
                    active_container = None

                active_list = key
                active_list_indent = indent
                break

        if active_list is None:
            continue

        if indent == active_list_indent + 2 and stripped.startswith("- "):
            if active_container:
                active_container["end"] = index
                blocks.append(active_container)

            name = "unknown"
            if stripped.startswith("- name:"):
                name = stripped.split(":", 1)[1].strip().strip('"').strip("'")

            active_container = {
                "name": name,
                "start": index,
                "end": index + 1,
                "container_indent": indent,
            }
            continue

        if active_container is not None:
            active_container["end"] = index + 1

            if stripped.startswith("name:"):
                active_container["name"] = scalar_value(stripped)

    if active_container:
        blocks.append(active_container)

    return blocks


def find_security_context_range(lines: list[str], block: dict) -> tuple[int, int] | None:
    container_indent = block["container_indent"]
    security_indent = container_indent + 2

    start = None

    for index in range(block["start"], block["end"]):
        clean = strip_comment(lines[index])
        if not clean.strip():
            continue

        if indentation(clean) == security_indent and clean.strip() == "securityContext:":
            start = index
            break

    if start is None:
        return None

    end = block["end"]
    for index in range(start + 1, block["end"]):
        clean = strip_comment(lines[index])
        if not clean.strip():
            continue

        if indentation(clean) <= security_indent:
            end = index
            break

    return start, end


def upsert_security_context(lines: list[str], block: dict) -> list[str]:
    updated = lines[:]
    container_indent = block["container_indent"]
    security_indent = container_indent + 2
    value_indent = security_indent + 2

    security_range = find_security_context_range(updated, block)

    if security_range is None:
        insert_at = block["end"]
        new_lines = [" " * security_indent + "securityContext:"]
        for key, value in SECURITY_CONTEXT_VALUES.items():
            new_lines.append(" " * value_indent + f"{key}: {value}")

        return updated[:insert_at] + new_lines + updated[insert_at:]

    start, end = security_range
    existing = updated[start:end]
    existing_keys = set()

    for index, line in enumerate(existing):
        stripped = strip_comment(line).strip()
        for key, value in SECURITY_CONTEXT_VALUES.items():
            if re.match(rf"^{re.escape(key)}\s*:", stripped):
                existing[index] = " " * value_indent + f"{key}: {value}"
                existing_keys.add(key)

    insert_at = len(existing)
    for key, value in SECURITY_CONTEXT_VALUES.items():
        if key not in existing_keys:
            existing.insert(insert_at, " " * value_indent + f"{key}: {value}")
            insert_at += 1

    return updated[:start] + existing + updated[end:]


def has_volume_mounts(lines: list[str]) -> bool:
    return any(strip_comment(line).strip() == "volumeMounts:" for line in lines)


def has_fs_group(lines: list[str]) -> bool:
    return any(re.match(r"^\s*fsGroup:\s*1000\s*$", strip_comment(line)) for line in lines)


def insert_fs_group_if_needed(lines: list[str]) -> list[str]:
    if not has_volume_mounts(lines) or has_fs_group(lines):
        return lines

    spec_indexes = [
        index for index, line in enumerate(lines)
        if strip_comment(line).strip() == "spec:"
    ]

    if not spec_indexes:
        return lines

    containers_index = next(
        (
            index for index, line in enumerate(lines)
            if strip_comment(line).strip() in {f"{key}:" for key in CONTAINER_LIST_KEYS}
        ),
        None,
    )

    if containers_index is None:
        return lines

    pod_spec_index = max(
        (index for index in spec_indexes if index < containers_index),
        default=None,
    )

    if pod_spec_index is None:
        return lines

    pod_spec_indent = indentation(strip_comment(lines[pod_spec_index]))
    child_indent = pod_spec_indent + 2

    insert_at = pod_spec_index + 1
    new_lines = [
        " " * child_indent + "securityContext:",
        " " * (child_indent + 2) + "fsGroup: 1000",
    ]

    return lines[:insert_at] + new_lines + lines[insert_at:]


def container_image(lines: list[str], block: dict) -> str | None:
    for index in range(block["start"], block["end"]):
        stripped = strip_comment(lines[index]).strip()
        if stripped.startswith("image:"):
            return scalar_value(stripped)
    return None


def container_ports(lines: list[str], block: dict) -> list[int]:
    ports = []

    for index in range(block["start"], block["end"]):
        stripped = strip_comment(lines[index]).strip()
        if stripped.startswith("containerPort:"):
            value = stripped.split(":", 1)[1].strip()
            if value.isdigit():
                ports.append(int(value))

    return ports


def mount_paths(lines: list[str], block: dict) -> list[str]:
    paths = []

    for index in range(block["start"], block["end"]):
        stripped = strip_comment(lines[index]).strip()
        if stripped.startswith("mountPath:"):
            paths.append(scalar_value(stripped))

    return paths


def add_manual_warning(
    warnings: list[dict],
    kind: str,
    name: str,
    container: str,
    issue: str,
    suggestion: list[str],
) -> None:
    warnings.append(
        {
            "resource": f"{kind}/{name}",
            "container": container,
            "issue": issue,
            "suggestion": suggestion,
        }
    )


def collect_manual_warnings(lines: list[str], kind: str, name: str, blocks: list[dict]) -> list[dict]:
    warnings = []

    for block in blocks:
        image = container_image(lines, block)
        ports = container_ports(lines, block)
        paths = mount_paths(lines, block)

        if image and image.startswith("nginx:"):
            add_manual_warning(
                warnings,
                kind,
                name,
                block["name"],
                f"image {image} may assume root execution and port 80.",
                [
                    "Consider changing the image to nginxinc/nginx-unprivileged with a matching tag.",
                    "If the container listens on port 80, also change it to a non-privileged port such as 8080.",
                    "Keep the port name, for example name: http, so Services using targetPort: http continue to work.",
                ],
            )

        if 80 in ports:
            add_manual_warning(
                warnings,
                kind,
                name,
                block["name"],
                "containerPort 80 is privileged for non-root containers.",
                [
                    "Change containerPort: 80 to containerPort: 8080 if the application can listen on 8080.",
                    "Check whether the application needs an env var such as PORT=8080.",
                    "Confirm the Service uses targetPort by name, for example targetPort: http.",
                ],
            )

        if "/data" in paths and not has_fs_group(lines):
            add_manual_warning(
                warnings,
                kind,
                name,
                block["name"],
                "mountPath /data may need writable volume permissions for runAsUser 1000.",
                [
                    "Add pod-level securityContext.fsGroup: 1000 if the volume should be writable by UID 1000.",
                    "If the image requires a different UID/GID, adjust runAsUser and fsGroup together.",
                ],
            )

        writable_root_paths = [path for path in paths if path in {"/tmp", "/var/cache", "/var/run", "/run"}]
        if not writable_root_paths:
            continue

        add_manual_warning(
            warnings,
            kind,
            name,
            block["name"],
            f"writable runtime paths detected: {', '.join(writable_root_paths)}.",
            [
                "Keep these paths mounted as emptyDir or another writable volume when readOnlyRootFilesystem is true.",
                "If the application writes elsewhere, add a dedicated volumeMount for that path.",
            ],
        )

    return warnings


def patch_document(document: str) -> tuple[str, list[dict]]:
    lines = document.splitlines()
    kind = top_level_value(lines, "kind")
    name = metadata_name(lines)

    if kind not in WORKLOAD_KINDS:
        return document, []

    blocks = collect_container_blocks(lines)

    if not blocks:
        return document, []

    warnings = collect_manual_warnings(lines, kind, name, blocks)

    for block in reversed(blocks):
        lines = upsert_security_context(lines, block)

    if has_volume_mounts(lines):
        lines = insert_fs_group_if_needed(lines)

    return "\n".join(lines) + ("\n" if document.endswith("\n") else ""), warnings


def patch_file(path: Path) -> tuple[str, str, list[dict]]:
    before = path.read_text(encoding="utf-8")
    documents = split_documents_with_separators(before)

    patched_documents = []
    warnings = []

    for document in documents:
        patched, document_warnings = patch_document(document)
        patched_documents.append(patched)
        warnings.extend(document_warnings)

    after = "".join(patched_documents)
    return before, after, warnings


def print_diff(path: Path, before: str, after: str, repo_root: Path) -> None:
    rel_path = path.relative_to(repo_root).as_posix()
    diff = difflib.unified_diff(
        before.splitlines(keepends=True),
        after.splitlines(keepends=True),
        fromfile=f"a/{rel_path}",
        tofile=f"b/{rel_path}",
    )
    print("".join(diff), end="")


def print_manual_warnings(all_warnings: list[tuple[Path, dict]], repo_root: Path) -> None:
    if not all_warnings:
        return

    print("\nManual review required:")
    for path, warning in all_warnings:
        print(f"\n- file: {path.relative_to(repo_root).as_posix()}")
        print(f"  resource: {warning['resource']}")
        print(f"  container: {warning['container']}")
        print(f"  issue: {warning['issue']}")
        print("  suggested change:")
        for suggestion in warning["suggestion"]:
            print(f"    - {suggestion}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Apply non-root container hardening to Kubernetes manifest YAML files."
    )
    parser.add_argument(
        "--manifests-dir",
        default="manifests",
        help="Directory containing Kubernetes manifests.",
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write changes to manifest files. Without this, only diffs are printed.",
    )
    args = parser.parse_args()

    repo_root = Path.cwd()
    manifests_dir = (repo_root / args.manifests_dir).resolve()

    if not manifests_dir.exists():
        raise SystemExit(f"manifests directory not found: {manifests_dir}")

    changed = []
    all_warnings = []

    for path in find_yaml_files(manifests_dir):
        before, after, warnings = patch_file(path)

        for warning in warnings:
            all_warnings.append((path, warning))

        if before != after:
            changed.append((path, before, after))

    if not changed:
        print("No manifest changes needed.")
    else:
        for path, before, after in changed:
            print_diff(path, before, after, repo_root)

    print_manual_warnings(all_warnings, repo_root)

    if args.write and changed:
        for path, _, after in changed:
            path.write_text(after, encoding="utf-8")
        print(f"\nApplied hardening changes to {len(changed)} file(s).")
    elif not args.write:
        print("\nDry run only. Re-run with --write to modify manifest files.")

if __name__ == "__main__":
    main()
