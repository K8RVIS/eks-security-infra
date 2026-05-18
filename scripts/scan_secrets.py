#!/usr/bin/env python3
"""
Scan IaC and configuration files for hardcoded secrets.

The scanner is intentionally dependency-free so it can run on Linux, macOS,
and Windows with a stock Python installation.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence


SEVERITY_ORDER = {
    "none": 99,
    "low": 1,
    "medium": 2,
    "high": 3,
    "critical": 4,
}

DEFAULT_MAX_FILE_SIZE = 2 * 1024 * 1024

DEFAULT_EXCLUDED_DIRS = {
    ".git",
    ".hg",
    ".svn",
    ".terraform",
    ".terragrunt-cache",
    ".venv",
    "venv",
    "env",
    "node_modules",
    "vendor",
    "dist",
    "build",
    "target",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".tox",
    ".idea",
    ".vscode",
    "coverage",
}

DEFAULT_SKIPPED_SUFFIXES = {
    ".7z",
    ".avi",
    ".bmp",
    ".class",
    ".dll",
    ".doc",
    ".docx",
    ".exe",
    ".gif",
    ".gz",
    ".ico",
    ".jar",
    ".jpeg",
    ".jpg",
    ".lockb",
    ".mov",
    ".mp3",
    ".mp4",
    ".o",
    ".pdf",
    ".png",
    ".pyc",
    ".rar",
    ".so",
    ".tar",
    ".tgz",
    ".wasm",
    ".webp",
    ".woff",
    ".woff2",
    ".xls",
    ".xlsx",
    ".zip",
}

CODE_SOURCE_SUFFIXES = {
    ".c",
    ".cc",
    ".cpp",
    ".cs",
    ".go",
    ".java",
    ".js",
    ".jsx",
    ".kt",
    ".php",
    ".ps1",
    ".py",
    ".rb",
    ".rs",
    ".scala",
    ".sh",
    ".swift",
    ".ts",
    ".tsx",
}

TERRAFORM_SOURCE_SUFFIXES = {
    ".tf",
    ".tfvars",
    ".hcl",
}

INLINE_ALLOW_MARKERS = (
    "secret-scan: ignore",
    "secret-scan:allow",
    "gitleaks:allow",
    "trufflehog:ignore",
)

DEFAULT_ALLOWLIST_PATTERNS = (
    r"(?i)\b(changeme|change-me|replace-me|placeholder)\b",
    r"(?i)\b(example|sample|dummy|mock|fake)\b",
    r"(?i)\byour[-_ ]?(password|secret|token|api[-_ ]?key|access[-_ ]?key)\b",
    r"\$\{[^}]+\}",
    r"\{\{[^}]+\}\}",
)

SENSITIVE_KEY_RE = re.compile(
    r"""
    (^|[_.\-/])
    (
        password|passwd|pwd|
        secret|secrets|
        token|tokens|
        api[_-]?key|
        access[_-]?key|
        secret[_-]?key|
        private[_-]?key|
        client[_-]?secret|
        auth[_-]?token|
        refresh[_-]?token|
        credential|credentials
    )
    ($|[_.\-/])
    """,
    re.IGNORECASE | re.VERBOSE,
)

HIGH_RISK_KEY_RE = re.compile(
    r"(?i)(password|passwd|secret|private[_-]?key|client[_-]?secret|credential)"
)

KEY_TOKEN_RE = re.compile(
    r"[A-Z]+(?=[A-Z][a-z]|[0-9]|\b)|[A-Z]?[a-z]+|[0-9]+"
)

NON_SECRET_KEY_SUFFIXES = (
    ("arn",),
    ("chart",),
    ("chart", "version"),
    ("endpoint",),
    ("file",),
    ("filename",),
    ("host",),
    ("id",),
    ("identifier",),
    ("issuer",),
    ("key", "ref"),
    ("kind",),
    ("mount",),
    ("name",),
    ("namespace",),
    ("path",),
    ("policy",),
    ("property",),
    ("ref",),
    ("reference",),
    ("role",),
    ("role", "arn"),
    ("scope",),
    ("selector",),
    ("service", "account"),
    ("serviceaccount",),
    ("store", "ref"),
    ("type",),
    ("uri",),
    ("url",),
    ("version",),
    ("volume",),
)

SENSITIVE_KEY_SEQUENCES = (
    ("api", "key"),
    ("access", "key"),
    ("secret", "access", "key"),
    ("secret", "key"),
    ("private", "key"),
    ("client", "secret"),
    ("auth", "token"),
    ("refresh", "token"),
)

SENSITIVE_KEY_TOKENS = {
    "credential",
    "credentials",
    "passwd",
    "password",
    "pwd",
    "token",
    "tokens",
}

SECRET_TOKENS = {"secret", "secrets"}

ASSIGNMENT_RE = re.compile(
    r"""
    (?P<key>[A-Za-z0-9_.\-/]+)
    \s*
    (?P<op>=|:|:=|=>)
    \s*
    (?P<value>
        "(?:\\.|[^"\\])*"
        |
        '(?:\\.|[^'\\])*'
        |
        [^\s,#\]\}]+
    )
    """,
    re.VERBOSE,
)

YAML_NAME_RE = re.compile(r"""^\s*-\s*name:\s*["']?(?P<name>[^"'\s#]+)["']?\s*(?:#.*)?$""")
YAML_VALUE_RE = re.compile(r"""^\s*value:\s*(?P<value>.+?)\s*(?:#.*)?$""")
K8S_SECRET_KIND_RE = re.compile(r"""^\s*kind:\s*["']?Secret["']?\s*(?:#.*)?$""")
K8S_DATA_SECTION_RE = re.compile(r"""^(?P<indent>\s*)(?P<section>data|stringData):\s*(?:#.*)?$""")
YAML_KEY_VALUE_RE = re.compile(r"""^\s*(?P<key>[A-Za-z0-9_.-]+):\s*(?P<value>.+?)\s*(?:#.*)?$""")
TERRAFORM_VARIABLE_RE = re.compile(r"""^\s*variable\s+"(?P<name>[^"]+)"\s*\{""")
TERRAFORM_DEFAULT_RE = re.compile(r"""^\s*default\s*=\s*(?P<value>.+?)\s*(?:#.*)?$""")
QUOTED_SECRET_RE = re.compile(r"""(?P<quote>["'])(?P<value>[A-Za-z0-9+/=_\-.]{24,})(?P=quote)""")


@dataclass(frozen=True)
class RegexRule:
    rule_id: str
    name: str
    severity: str
    pattern: re.Pattern[str]
    group: str = "secret"


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    column: int
    severity: str
    rule_id: str
    rule_name: str
    redacted: str
    context: str
    fingerprint: str
    secret: str


REGEX_RULES = (
    RegexRule(
        "private-key-block",
        "Private key material is committed",
        "critical",
        re.compile(r"-----BEGIN (?:RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----"),
        group="secret",
    ),
    RegexRule(
        "aws-access-key-id",
        "AWS access key id",
        "high",
        re.compile(r"\b(?P<secret>(?:A3T[A-Z0-9]|AKIA|ASIA|AGPA|AIDA|AROA|AIPA|ANPA)[A-Z0-9]{16})\b"),
    ),
    RegexRule(
        "aws-secret-access-key",
        "AWS secret access key assignment",
        "high",
        re.compile(
            r"""
            \baws[A-Za-z0-9_.\-/]*secret[A-Za-z0-9_.\-/]*(?:access)?[A-Za-z0-9_.\-/]*key\b
            \s*(?:=|:|:=|=>)\s*["']?(?P<secret>[A-Za-z0-9/+=]{40})["']?
            """,
            re.IGNORECASE | re.VERBOSE,
        ),
    ),
    RegexRule(
        "github-token",
        "GitHub token",
        "high",
        re.compile(r"\b(?P<secret>gh[pousr]_[A-Za-z0-9_]{30,255}|github_pat_[A-Za-z0-9_]{22}_[A-Za-z0-9_]{40,})\b"),
    ),
    RegexRule(
        "gitlab-token",
        "GitLab personal access token",
        "high",
        re.compile(r"\b(?P<secret>glpat-[A-Za-z0-9_-]{20,})\b"),
    ),
    RegexRule(
        "slack-token",
        "Slack token",
        "high",
        re.compile(r"\b(?P<secret>xox[baprs]-[A-Za-z0-9-]{10,})\b"),
    ),
    RegexRule(
        "google-api-key",
        "Google API key",
        "high",
        re.compile(r"\b(?P<secret>AIza[0-9A-Za-z_-]{35})\b"),
    ),
    RegexRule(
        "google-oauth-client-secret",
        "Google OAuth client secret",
        "high",
        re.compile(r"\b(?P<secret>GOCSPX-[A-Za-z0-9_-]{20,})\b"),
    ),
    RegexRule(
        "stripe-live-key",
        "Stripe live secret key",
        "critical",
        re.compile(r"\b(?P<secret>[rs]k_live_[0-9A-Za-z]{20,})\b"),
    ),
    RegexRule(
        "sendgrid-api-key",
        "SendGrid API key",
        "high",
        re.compile(r"\b(?P<secret>SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{32,})\b"),
    ),
    RegexRule(
        "jwt-token",
        "JWT token",
        "medium",
        re.compile(r"\b(?P<secret>eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})\b"),
    ),
    RegexRule(
        "authorization-bearer",
        "Authorization bearer token",
        "high",
        re.compile(r"""(?i)\bauthorization\b\s*(?:=|:)\s*["']?Bearer\s+(?P<secret>[A-Za-z0-9._~+/=-]{20,})"""),
    ),
    RegexRule(
        "url-basic-auth",
        "URL contains embedded credentials",
        "high",
        re.compile(r"""(?P<secret>\b[a-z][a-z0-9+.-]*://[^/\s:@"']*:[^@\s/"']{3,}@[^/\s"']+)""", re.IGNORECASE),
    ),
)


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Scan files for hardcoded secrets in IaC, manifests, and configuration files."
    )
    parser.add_argument(
        "roots",
        nargs="*",
        default=["."],
        help="Files or directories to scan. Defaults to the current directory.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format. Defaults to text.",
    )
    parser.add_argument(
        "--fail-on",
        choices=("none", "low", "medium", "high", "critical"),
        default="high",
        help="Exit with code 1 when findings at or above this severity exist. Defaults to high.",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help="Glob pattern to include. Can be repeated. When omitted, all text files are scanned.",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Glob pattern or path segment to exclude. Can be repeated.",
    )
    parser.add_argument(
        "--allowlist",
        type=Path,
        help="Path to a file containing regex patterns for accepted findings, one per line.",
    )
    parser.add_argument(
        "--no-default-allowlist",
        action="store_true",
        help="Disable built-in allowlist patterns for obvious placeholders and templates.",
    )
    parser.add_argument(
        "--enable-entropy",
        action="store_true",
        help="Also flag high-entropy quoted strings. Useful in CI, but can add false positives.",
    )
    parser.add_argument(
        "--max-file-size",
        type=int,
        default=DEFAULT_MAX_FILE_SIZE,
        help=f"Skip files larger than this many bytes. Defaults to {DEFAULT_MAX_FILE_SIZE}.",
    )
    parser.add_argument(
        "--show-secrets",
        action="store_true",
        help="Print raw secret values. By default findings are redacted.",
    )
    return parser.parse_args(argv)


def compile_allowlist(args: argparse.Namespace) -> list[re.Pattern[str]]:
    patterns: list[str] = []
    if not args.no_default_allowlist:
        patterns.extend(DEFAULT_ALLOWLIST_PATTERNS)

    if args.allowlist:
        try:
            for line in args.allowlist.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if stripped and not stripped.startswith("#"):
                    patterns.append(stripped)
        except OSError as exc:
            raise SystemExit(f"failed to read allowlist {args.allowlist}: {exc}") from exc

    compiled: list[re.Pattern[str]] = []
    for pattern in patterns:
        try:
            compiled.append(re.compile(pattern))
        except re.error as exc:
            raise SystemExit(f"invalid allowlist regex {pattern!r}: {exc}") from exc
    return compiled


def normalized_path(path: Path) -> str:
    return path.as_posix()


def relative_path(path: Path, base: Path) -> str:
    try:
        return normalized_path(path.resolve().relative_to(base.resolve()))
    except ValueError:
        return normalized_path(path.resolve())


def matches_any_glob(path: str, name: str, patterns: Iterable[str]) -> bool:
    for pattern in patterns:
        normalized = pattern.replace("\\", "/")
        if fnmatch.fnmatch(path, normalized) or fnmatch.fnmatch(name, normalized):
            return True
    return False


def is_excluded_path(path: Path, rel_path: str, extra_excludes: Sequence[str]) -> bool:
    path_parts = set(path.parts)
    if path_parts & DEFAULT_EXCLUDED_DIRS:
        return True
    if path.suffix.lower() in DEFAULT_SKIPPED_SUFFIXES:
        return True
    if matches_any_glob(rel_path, path.name, extra_excludes):
        return True
    return any(part in extra_excludes for part in path.parts)


def iter_scan_files(roots: Sequence[str], args: argparse.Namespace, base: Path) -> Iterator[Path]:
    for root_text in roots:
        root = Path(root_text)
        if root.is_file():
            rel = relative_path(root, base)
            if not is_excluded_path(root, rel, args.exclude) and include_file(root, rel, args.include):
                yield root
            continue

        if not root.exists():
            print(f"warning: scan root does not exist: {root}", file=sys.stderr)
            continue

        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            kept_dirs: list[str] = []
            for dirname in dirnames:
                child = current / dirname
                rel = relative_path(child, base)
                if not is_excluded_path(child, rel, args.exclude):
                    kept_dirs.append(dirname)
            dirnames[:] = kept_dirs

            for filename in filenames:
                path = current / filename
                rel = relative_path(path, base)
                if is_excluded_path(path, rel, args.exclude):
                    continue
                if include_file(path, rel, args.include):
                    yield path


def include_file(path: Path, rel_path: str, include_patterns: Sequence[str]) -> bool:
    if not include_patterns:
        return True
    return matches_any_glob(rel_path, path.name, include_patterns)


def read_text_file(path: Path, max_file_size: int) -> str | None:
    try:
        size = path.stat().st_size
    except OSError:
        return None
    if size > max_file_size:
        return None

    try:
        data = path.read_bytes()
    except OSError:
        return None

    if b"\x00" in data:
        return None

    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return data.decode("utf-16")
        except UnicodeDecodeError:
            return data.decode("utf-8", errors="replace")


def strip_wrapping_quotes(value: str) -> str:
    value = value.strip().rstrip(",")
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def yaml_scalar_value(raw_value: str) -> str:
    value = raw_value.strip().rstrip(",")
    if not value:
        return value
    if value[0] in {"'", '"'}:
        quote = value[0]
        escaped = False
        for index in range(1, len(value)):
            char = value[index]
            if char == "\\" and quote == '"' and not escaped:
                escaped = True
                continue
            if char == quote and not escaped:
                return value[1:index]
            escaped = False
        return value[1:]
    return re.split(r"\s+#", value, maxsplit=1)[0].strip()


def split_key_tokens(key: str) -> list[str]:
    tokens: list[str] = []
    for part in re.split(r"[_.\-/\s]+", key.strip()):
        if not part:
            continue
        tokens.extend(token.lower() for token in KEY_TOKEN_RE.findall(part))
    return tokens


def tokens_end_with(tokens: Sequence[str], suffix: Sequence[str]) -> bool:
    if len(tokens) < len(suffix):
        return False
    return tuple(tokens[-len(suffix) :]) == tuple(suffix)


def contains_token_sequence(tokens: Sequence[str], sequence: Sequence[str]) -> bool:
    length = len(sequence)
    if not length or len(tokens) < length:
        return False
    wanted = tuple(sequence)
    return any(tuple(tokens[index : index + length]) == wanted for index in range(len(tokens) - length + 1))


def is_non_secret_metadata_key(tokens: Sequence[str]) -> bool:
    return any(tokens_end_with(tokens, suffix) for suffix in NON_SECRET_KEY_SUFFIXES)


def is_ambiguous_secret_name_key(key: str) -> bool:
    tokens = split_key_tokens(key)
    return tokens in (["secret"], ["secrets"], ["secret", "key"])


def is_sensitive_key(key: str) -> bool:
    tokens = split_key_tokens(key)
    if not tokens:
        return False

    # Names such as external_secrets_namespace and workload_secret_arn are
    # references to secret-related resources, not secret values themselves.
    if is_non_secret_metadata_key(tokens):
        return False

    if any(token in SENSITIVE_KEY_TOKENS for token in tokens):
        return True

    if any(contains_token_sequence(tokens, sequence) for sequence in SENSITIVE_KEY_SEQUENCES):
        return True

    return tokens[-1] in SECRET_TOKENS


def looks_like_terraform_reference(value: str) -> bool:
    stripped = value.strip()
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?(?:\.[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?)+", stripped):
        return True
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\(.*\)", stripped):
        return True
    return bool(re.fullmatch(r"\[[^\]]*\]|\{[^}]*\}", stripped))


def looks_like_identifier_reference_value(value: str) -> bool:
    stripped = value.strip()
    if looks_high_entropy(stripped):
        return False
    if re.match(r"^arn:[a-z0-9-]+:", stripped, re.IGNORECASE):
        return True
    if re.fullmatch(r"/[A-Za-z0-9_.:/-]+", stripped):
        return True
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:/-]{2,127}", stripped) and re.search(r"[-_./:]", stripped))


def looks_like_template_or_reference(value: str) -> bool:
    stripped = value.strip()
    lowered = stripped.lower()
    if stripped.startswith(("${", "{{", "$(", "$", "<<")):
        return True
    if lowered.startswith(("var.", "local.", "module.", "data.", "resource.", "path.", "terraform.")):
        return True
    if lowered.startswith(("file(", "jsonencode(", "yamlencode(", "templatefile(", "sensitive(")):
        return True
    return False


def looks_like_code_expression(value: str) -> bool:
    stripped = value.strip()
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", stripped):
        return True
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*\(.*", stripped):
        return True
    if any(operator in stripped for operator in ("+", "(", ")", "[", "]", "{", "}")):
        return True
    return False


def is_plain_url_without_credentials(value: str) -> bool:
    if not re.match(r"^[a-z][a-z0-9+.-]*://", value, re.IGNORECASE):
        return False
    return not re.match(r"^[a-z][a-z0-9+.-]*://[^/\s:@]+:[^@\s]+@", value, re.IGNORECASE)


def is_low_value_literal(value: str) -> bool:
    lowered = value.strip().lower()
    return lowered in {
        "",
        "null",
        "none",
        "nil",
        "true",
        "false",
        "yes",
        "no",
        "on",
        "off",
        "required",
        "optional",
        "enabled",
        "disabled",
        "default",
        "string",
        "number",
        "object",
        "list",
        "map",
        "set",
        "[]",
        "{}",
        "''",
        '""',
    }


def likely_secret_value(key: str, value: str) -> bool:
    normalized_value = strip_wrapping_quotes(value).strip()
    if is_low_value_literal(normalized_value):
        return False
    if looks_like_template_or_reference(normalized_value):
        return False
    if len(normalized_value) < 6:
        return False
    if is_plain_url_without_credentials(normalized_value) and re.search(r"(?i)(url|uri|endpoint|issuer|audience)", key):
        return False
    if is_ambiguous_secret_name_key(key) and looks_like_identifier_reference_value(normalized_value):
        return False
    return True


def shannon_entropy(value: str) -> float:
    if not value:
        return 0.0
    frequencies = {char: value.count(char) for char in set(value)}
    length = len(value)
    return -sum((count / length) * math.log2(count / length) for count in frequencies.values())


def looks_high_entropy(value: str) -> bool:
    if len(value) < 24:
        return False
    if re.fullmatch(r"[0-9a-fA-F-]{32,36}", value):
        return False
    has_alpha = bool(re.search(r"[A-Za-z]", value))
    has_digit = bool(re.search(r"\d", value))
    if not (has_alpha and has_digit):
        return False
    return shannon_entropy(value) >= 4.0


def redact(secret: str, show_secret: bool) -> str:
    if show_secret:
        return secret
    if len(secret) <= 4:
        return "*" * len(secret)
    if len(secret) <= 10:
        return f"{secret[:1]}...{secret[-1:]}"
    return f"{secret[:4]}...{secret[-4:]}"


def finding_fingerprint(rel_path: str, line_no: int, rule_id: str, secret: str) -> str:
    data = f"{rel_path}:{line_no}:{rule_id}:{secret}".encode("utf-8", errors="replace")
    return hashlib.sha256(data).hexdigest()[:16]


def line_allowed(line_text: str) -> bool:
    lowered = line_text.lower()
    return any(marker in lowered for marker in INLINE_ALLOW_MARKERS)


def allowed_by_patterns(
    allowlist: Sequence[re.Pattern[str]],
    rel_path: str,
    line_no: int,
    rule_id: str,
    secret: str,
    line_text: str,
) -> bool:
    candidate = f"{rel_path}:{line_no}:{rule_id}:{secret}:{line_text}"
    return any(pattern.search(candidate) for pattern in allowlist)


def make_finding(
    *,
    rel_path: str,
    line_no: int,
    line_text: str,
    rule_id: str,
    rule_name: str,
    severity: str,
    secret: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
    column: int | None = None,
) -> Finding | None:
    clean_secret = strip_wrapping_quotes(secret).strip()
    if not clean_secret:
        return None
    if line_allowed(line_text):
        return None
    if allowed_by_patterns(allowlist, rel_path, line_no, rule_id, clean_secret, line_text):
        return None

    if column is None:
        index = line_text.find(secret)
        if index == -1:
            index = line_text.find(clean_secret)
        column = index + 1 if index >= 0 else 1

    redacted_secret = redact(clean_secret, show_secret)
    context = line_text.strip()
    if clean_secret in context:
        context = context.replace(clean_secret, redacted_secret)
    elif secret in context:
        context = context.replace(secret, redacted_secret)

    return Finding(
        path=rel_path,
        line=line_no,
        column=column,
        severity=severity,
        rule_id=rule_id,
        rule_name=rule_name,
        redacted=redacted_secret,
        context=context,
        fingerprint=finding_fingerprint(rel_path, line_no, rule_id, clean_secret),
        secret=clean_secret,
    )


def generic_assignment_severity(key: str, value: str) -> str:
    if HIGH_RISK_KEY_RE.search(key):
        return "high"
    if len(value) >= 20 or looks_high_entropy(value):
        return "high"
    return "medium"


def scan_regex_rules(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    for line_no, line in enumerate(lines, start=1):
        for rule in REGEX_RULES:
            for match in rule.pattern.finditer(line):
                secret = match.groupdict().get(rule.group) or match.group(0)
                finding = make_finding(
                    rel_path=rel_path,
                    line_no=line_no,
                    line_text=line,
                    rule_id=rule.rule_id,
                    rule_name=rule.name,
                    severity=rule.severity,
                    secret=secret,
                    show_secret=show_secret,
                    allowlist=allowlist,
                    column=match.start() + 1,
                )
                if finding:
                    yield finding


def scan_generic_assignments(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    source_suffix = Path(rel_path).suffix.lower()
    for line_no, line in enumerate(lines, start=1):
        for match in ASSIGNMENT_RE.finditer(line):
            key = match.group("key")
            raw_value = match.group("value")
            value = strip_wrapping_quotes(raw_value)
            if not is_sensitive_key(key):
                continue
            value_is_quoted = raw_value.strip().startswith(("'", '"'))
            if (
                not value_is_quoted
                and source_suffix in CODE_SOURCE_SUFFIXES
                and looks_like_code_expression(value)
            ):
                continue
            if (
                not value_is_quoted
                and source_suffix in TERRAFORM_SOURCE_SUFFIXES
                and looks_like_terraform_reference(value)
            ):
                continue
            if not likely_secret_value(key, value):
                continue
            finding = make_finding(
                rel_path=rel_path,
                line_no=line_no,
                line_text=line,
                rule_id="sensitive-key-assignment",
                rule_name=f"Sensitive key '{key}' has a hardcoded value",
                severity=generic_assignment_severity(key, value),
                secret=value,
                show_secret=show_secret,
                allowlist=allowlist,
                column=match.start("value") + 1,
            )
            if finding:
                yield finding


def scan_k8s_env_values(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    pending: list[tuple[str, int]] = []
    for line_no, line in enumerate(lines, start=1):
        name_match = YAML_NAME_RE.match(line)
        if name_match:
            env_name = name_match.group("name")
            if is_sensitive_key(env_name):
                pending.append((env_name, line_no + 5))

        pending = [(name, expires) for name, expires in pending if expires >= line_no]
        value_match = YAML_VALUE_RE.match(line)
        if not value_match or not pending:
            continue

        value = yaml_scalar_value(value_match.group("value"))
        if not likely_secret_value(pending[-1][0], value):
            continue
        finding = make_finding(
            rel_path=rel_path,
            line_no=line_no,
            line_text=line,
            rule_id="k8s-env-hardcoded-secret",
            rule_name=f"Kubernetes env var '{pending[-1][0]}' has a hardcoded value",
            severity="high",
            secret=value,
            show_secret=show_secret,
            allowlist=allowlist,
            column=line.find(value) + 1 if value in line else 1,
        )
        if finding:
            yield finding


def line_indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def split_yaml_documents(lines: Sequence[str]) -> Iterator[tuple[int, list[str]]]:
    start_line = 1
    current: list[str] = []
    for line_no, line in enumerate(lines, start=1):
        if re.match(r"^\s*---\s*(?:#.*)?$", line):
            if current:
                yield start_line, current
            start_line = line_no + 1
            current = []
            continue
        current.append(line)
    if current:
        yield start_line, current


def scan_k8s_secret_documents(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    if not rel_path.lower().endswith((".yaml", ".yml")):
        return

    for doc_start, document in split_yaml_documents(lines):
        if not any(K8S_SECRET_KIND_RE.match(line) for line in document):
            continue

        in_data = False
        data_indent = 0
        section = ""
        for offset, line in enumerate(document):
            line_no = doc_start + offset
            section_match = K8S_DATA_SECTION_RE.match(line)
            if section_match:
                in_data = True
                data_indent = len(section_match.group("indent"))
                section = section_match.group("section")
                continue

            if not in_data:
                continue
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line_indent(line) <= data_indent:
                in_data = False
                section = ""
                continue

            key_value_match = YAML_KEY_VALUE_RE.match(line)
            if not key_value_match:
                continue

            key = key_value_match.group("key")
            value = yaml_scalar_value(key_value_match.group("value"))
            if value in {"|", ">"}:
                value = f"{section}.{key}:<multiline>"
            if not likely_secret_value(key, value):
                continue

            finding = make_finding(
                rel_path=rel_path,
                line_no=line_no,
                line_text=line,
                rule_id="k8s-secret-data",
                rule_name=f"Kubernetes Secret {section}.{key} is hardcoded",
                severity="high",
                secret=value,
                show_secret=show_secret,
                allowlist=allowlist,
                column=line.find(value) + 1 if value in line else 1,
            )
            if finding:
                yield finding


def scan_terraform_variable_defaults(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    if not rel_path.lower().endswith((".tf", ".tfvars", ".hcl")):
        return

    variable_name: str | None = None
    variable_start_line = 0
    brace_depth = 0

    for line_no, line in enumerate(lines, start=1):
        if variable_name is None:
            variable_match = TERRAFORM_VARIABLE_RE.match(line)
            if not variable_match:
                continue
            variable_name = variable_match.group("name")
            variable_start_line = line_no
            brace_depth = line.count("{") - line.count("}")
            continue

        default_match = TERRAFORM_DEFAULT_RE.match(line)
        if default_match and is_sensitive_key(variable_name):
            value = strip_wrapping_quotes(default_match.group("value"))
            if likely_secret_value(variable_name, value):
                finding = make_finding(
                    rel_path=rel_path,
                    line_no=line_no,
                    line_text=line,
                    rule_id="terraform-sensitive-variable-default",
                    rule_name=f"Terraform variable '{variable_name}' has a hardcoded default",
                    severity="high",
                    secret=value,
                    show_secret=show_secret,
                    allowlist=allowlist,
                    column=line.find(value) + 1 if value in line else 1,
                )
                if finding:
                    yield finding

        brace_depth += line.count("{") - line.count("}")
        if brace_depth <= 0:
            variable_name = None
            variable_start_line = 0

    if variable_name is not None and variable_start_line:
        return


def scan_entropy(
    lines: Sequence[str],
    rel_path: str,
    show_secret: bool,
    allowlist: Sequence[re.Pattern[str]],
) -> Iterator[Finding]:
    for line_no, line in enumerate(lines, start=1):
        if line.lstrip().startswith(("#", "//")):
            continue
        for match in QUOTED_SECRET_RE.finditer(line):
            value = match.group("value")
            if not looks_high_entropy(value):
                continue
            finding = make_finding(
                rel_path=rel_path,
                line_no=line_no,
                line_text=line,
                rule_id="high-entropy-string",
                rule_name="High-entropy quoted string",
                severity="medium",
                secret=value,
                show_secret=show_secret,
                allowlist=allowlist,
                column=match.start("value") + 1,
            )
            if finding:
                yield finding


def scan_file(
    path: Path,
    base: Path,
    args: argparse.Namespace,
    allowlist: Sequence[re.Pattern[str]],
) -> list[Finding]:
    text = read_text_file(path, args.max_file_size)
    if text is None:
        return []

    rel_path = relative_path(path, base)
    lines = text.splitlines()
    findings: list[Finding] = []
    findings.extend(scan_regex_rules(lines, rel_path, args.show_secrets, allowlist))
    findings.extend(scan_generic_assignments(lines, rel_path, args.show_secrets, allowlist))
    findings.extend(scan_k8s_env_values(lines, rel_path, args.show_secrets, allowlist))
    findings.extend(scan_k8s_secret_documents(lines, rel_path, args.show_secrets, allowlist))
    findings.extend(scan_terraform_variable_defaults(lines, rel_path, args.show_secrets, allowlist))
    if args.enable_entropy:
        findings.extend(scan_entropy(lines, rel_path, args.show_secrets, allowlist))
    return deduplicate_findings(findings)


def deduplicate_findings(findings: Sequence[Finding]) -> list[Finding]:
    seen: set[tuple[str, int, str, str]] = set()
    deduped: list[Finding] = []
    for finding in findings:
        key = (finding.path, finding.line, finding.rule_id, finding.redacted)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(finding)
    return deduped


def finding_to_dict(finding: Finding, show_secret: bool) -> dict[str, object]:
    data: dict[str, object] = {
        "path": finding.path,
        "line": finding.line,
        "column": finding.column,
        "severity": finding.severity,
        "rule_id": finding.rule_id,
        "rule_name": finding.rule_name,
        "redacted": finding.redacted,
        "context": finding.context,
        "fingerprint": finding.fingerprint,
    }
    if show_secret:
        data["secret"] = finding.secret
    return data


def render_text(findings: Sequence[Finding], scanned_files: int) -> str:
    if not findings:
        return f"No hardcoded secrets found. Scanned {scanned_files} file(s)."

    sorted_findings = sorted(
        findings,
        key=lambda item: (-SEVERITY_ORDER[item.severity], item.path, item.line, item.column, item.rule_id),
    )
    lines = [
        f"Found {len(sorted_findings)} potential hardcoded secret(s) in {scanned_files} scanned file(s).",
        "",
    ]
    for finding in sorted_findings:
        lines.append(
            f"[{finding.severity.upper()}] {finding.path}:{finding.line}:{finding.column} "
            f"{finding.rule_id} - {finding.rule_name}"
        )
        lines.append(f"  value: {finding.redacted}")
        if finding.context:
            lines.append(f"  line: {finding.context}")
        lines.append(f"  fingerprint: {finding.fingerprint}")
        lines.append("")
    return "\n".join(lines).rstrip()


def should_fail(findings: Sequence[Finding], fail_on: str) -> bool:
    if fail_on == "none":
        return False
    threshold = SEVERITY_ORDER[fail_on]
    return any(SEVERITY_ORDER[finding.severity] >= threshold for finding in findings)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    base = Path.cwd()
    allowlist = compile_allowlist(args)

    all_findings: list[Finding] = []
    scanned_files = 0
    for path in iter_scan_files(args.roots, args, base):
        scanned_files += 1
        all_findings.extend(scan_file(path, base, args, allowlist))

    all_findings = deduplicate_findings(all_findings)

    if args.format == "json":
        payload = {
            "scanned_files": scanned_files,
            "finding_count": len(all_findings),
            "findings": [finding_to_dict(finding, args.show_secrets) for finding in all_findings],
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(render_text(all_findings, scanned_files))

    return 1 if should_fail(all_findings, args.fail_on) else 0


if __name__ == "__main__":
    raise SystemExit(main())
