#!/usr/bin/env python3
"""Validate the exact WebAPI report payloads consumed by Atlas."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"Atlas report validation failed: {message}", file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 3:
    fail("expected PERSON_JSON CONDITION_ERA_JSON")

person = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
condition_era = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))


def mapped_count(field: str) -> int:
    rows = person.get(field)
    if not isinstance(rows, list):
        fail(f"person response has no {field} array")
    return sum(
        int(row.get("countValue") or 0)
        for row in rows
        if int(row.get("conceptId") or 0) != 0
    )


race_count = mapped_count("race")
ethnicity_count = mapped_count("ethnicity")
if race_count == 0:
    fail("race contains no mapped concepts")
if ethnicity_count == 0:
    fail("ethnicity contains no mapped concepts")
if not isinstance(condition_era, list) or not condition_era:
    fail("condition-era report is empty")

print(
    "Atlas reports ready: "
    f"mapped race={race_count}, mapped ethnicity={ethnicity_count}, "
    f"condition-era concepts={len(condition_era)}"
)
