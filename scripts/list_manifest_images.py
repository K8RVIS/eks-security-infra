#!/usr/bin/env python3
import argparse
import pathlib
import re
import sys


IMAGE_PATTERN = re.compile(r"^\s*image:\s*(['\"]?)(?P<image>[^'\"\s#]+)\1(?:\s+#.*)?$")
YAML_SUFFIXES = {".yaml", ".yml"}


def iter_yaml_files(paths):
    for raw_path in paths:
        path = pathlib.Path(raw_path)
        if path.is_file() and path.suffix in YAML_SUFFIXES:
            yield path
        elif path.is_dir():
            yield from sorted(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file() and candidate.suffix in YAML_SUFFIXES
            )


def collect_images(paths):
    images = set()
    for manifest_path in iter_yaml_files(paths):
        for line in manifest_path.read_text(encoding="utf-8").splitlines():
            match = IMAGE_PATTERN.match(line)
            if match:
                images.add(match.group("image"))
    return sorted(images)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="List container images referenced by Kubernetes YAML manifests.")
    parser.add_argument("paths", nargs="+", help="Manifest files or directories to scan.")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    for image in collect_images(args.paths):
        print(image)


if __name__ == "__main__":
    main()
