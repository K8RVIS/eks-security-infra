#!/usr/bin/env python3
"""Extract unique container image references from Kubernetes manifests.

Usage:
  python scripts/list_manifest_images.py [manifests_dir] [--json]
"""

import json
import pathlib
import sys

import yaml


def extract_images(manifests_dir: str) -> list[str]:
    images: set[str] = set()
    for path in pathlib.Path(manifests_dir).rglob("*.yaml"):
        with path.open() as fh:
            for doc in yaml.safe_load_all(fh):
                if not isinstance(doc, dict):
                    continue
                for image in _iter_images(doc):
                    images.add(image)
    return sorted(images)


def _iter_images(obj):
    if isinstance(obj, dict):
        if "image" in obj and isinstance(obj["image"], str):
            yield obj["image"]
        for value in obj.values():
            yield from _iter_images(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from _iter_images(item)


if __name__ == "__main__":
    directory = next((a for a in sys.argv[1:] if not a.startswith("-")), "manifests")
    as_json = "--json" in sys.argv

    images = extract_images(directory)

    if as_json:
        print(json.dumps(images))
    else:
        for image in images:
            print(image)
