#!/usr/bin/env python3
"""Normalize and review the source domain lists without visiting any sites."""

from __future__ import annotations

import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_FILES = [ROOT / "list.txt", ROOT / "kr.list"]
ALLOWLIST_FILE = ROOT / "allowlist.txt"
OUT_DIR = ROOT / "reviewed"

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$"
)

ADULT_SIGNALS = {
    "18",
    "adult",
    "anal",
    "av",
    "babe",
    "bdsm",
    "boob",
    "cam",
    "doll",
    "ero",
    "escort",
    "fetish",
    "fuck",
    "gay",
    "hentai",
    "jav",
    "jizz",
    "milf",
    "naked",
    "nude",
    "porn",
    "r18",
    "sex",
    "slut",
    "smut",
    "tube",
    "twink",
    "xxx",
}


def normalize_domain(raw: str) -> str | None:
    value = raw.strip().lower()
    if not value or value.startswith("#"):
        return None
    value = value.split("#", 1)[0].strip()
    value = re.sub(r"^[a-z][a-z0-9+.-]*://", "", value)
    value = value.split("/", 1)[0].split(":", 1)[0].strip(".")
    if value.startswith("www."):
        value = value[4:]
    return value or None


def read_domains(path: Path) -> list[str]:
    return [domain for line in path.read_text().splitlines() if (domain := normalize_domain(line))]


def read_allowlist() -> set[str]:
    if not ALLOWLIST_FILE.exists():
        return set()
    return set(read_domains(ALLOWLIST_FILE))


def has_adult_signal(domain: str) -> bool:
    compact = domain.replace("-", "").replace(".", "")
    return any(signal in compact for signal in ADULT_SIGNALS)


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    OUT_DIR.mkdir(exist_ok=True)

    per_source = {path.name: read_domains(path) for path in SOURCE_FILES}
    all_rows = [domain for domains in per_source.values() for domain in domains]
    counts = Counter(all_rows)
    unique = sorted(counts)
    invalid = sorted(domain for domain in unique if not DOMAIN_RE.match(domain))
    allowlist = read_allowlist()
    unknown_allowlist = sorted(allowlist - set(unique))

    reviewed = sorted(domain for domain in unique if domain not in allowlist and domain not in invalid)
    excluded = sorted(domain for domain in unique if domain in allowlist)
    weak_signal = sorted(domain for domain in reviewed if not has_adult_signal(domain))

    write_lines(OUT_DIR / "porn-blocklist.txt", reviewed)
    write_lines(
        OUT_DIR / "excluded-non-porn.txt",
        [
            "# Excluded from reviewed/porn-blocklist.txt",
            "# Source domains remain unchanged in list.txt and kr.list.",
            "",
            *excluded,
        ],
    )
    write_lines(
        OUT_DIR / "manual-review.txt",
        [
            "# Kept in the porn blocklist, but the domain name itself has weak adult lexical evidence.",
            "# This is an audit queue, not an allowlist.",
            "",
            *weak_signal,
        ],
    )

    report = [
        "# Blocklist Review Report",
        "",
        "This review is offline only: it normalizes and classifies domains without opening, searching, or fetching the listed websites.",
        "",
        "## Summary",
        "",
        f"- Source files: {', '.join(path.name for path in SOURCE_FILES)}",
        f"- Source rows: {len(all_rows)}",
        f"- Unique normalized domains: {len(unique)}",
        f"- Duplicate source rows: {len(all_rows) - len(unique)}",
        f"- Invalid normalized domains excluded: {len(invalid)}",
        f"- Non-porn or mixed/general-purpose domains excluded: {len(excluded)}",
        f"- Final reviewed porn blocklist domains: {len(reviewed)}",
        f"- Kept domains needing future manual audit: {len(weak_signal)}",
        "",
        "## Exclusion Policy",
        "",
        "Domains are excluded only when they are clearly gambling, financial, or general/mixed-purpose media domains rather than porn-specific domains.",
        "Mixed adult-capable domains are intentionally conservative: if a domain is meaningfully adult-related, keep it blocked unless you add it to allowlist.txt.",
        "",
        "## Excluded Domains",
        "",
        *[f"- `{domain}`" for domain in excluded],
    ]
    if invalid:
        report.extend(["", "## Invalid Domains", "", *[f"- `{domain}`" for domain in invalid]])
    if unknown_allowlist:
        report.extend(
            [
                "",
                "## Allowlist Entries Not Present In Sources",
                "",
                *[f"- `{domain}`" for domain in unknown_allowlist],
            ]
        )
    write_lines(OUT_DIR / "review-report.md", report)

    print(f"reviewed domains: {len(reviewed)}")
    print(f"excluded domains: {len(excluded)}")
    print(f"manual review queue: {len(weak_signal)}")
    print(f"wrote: {OUT_DIR / 'porn-blocklist.txt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
