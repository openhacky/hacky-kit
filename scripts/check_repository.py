#!/usr/bin/env python3
from __future__ import annotations

import re
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATED = {".DS_Store", ".build", ".swiftpm", "DerivedData", "xcuserdata"}


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(
            f"git {' '.join(args)} failed with {result.returncode}: {result.stderr.strip()}"
        )
    return result.stdout


def repository_files() -> list[Path]:
    values = git("ls-files", "-z") + git(
        "ls-files", "--others", "--exclude-standard", "-z"
    )
    relative = {Path(value) for value in values.split("\0") if value}
    return sorted(path for path in relative if (ROOT / path).is_file())


def readable_text(path: Path) -> str | None:
    try:
        return (ROOT / path).read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def former_surface_pattern() -> re.Pattern[str]:
    old_standard = "PO" + "SA"
    old_app = "Om" + "a"
    private_state = "Pre" + "sence"
    future_catalog = "H" + "ub"
    private_glue = "Lo" + "op"
    future_merge = "H" + "ab"
    old_extension = "x" + "_"
    words = [old_standard, private_state, old_extension]
    bounded = [old_app, future_catalog, private_glue, future_merge]
    expression = "|".join(re.escape(value) for value in words)
    expression += "|" + "|".join(
        rf"(?<![A-Za-z0-9]){re.escape(value)}(?![A-Za-z0-9])"
        for value in bounded
    )
    return re.compile(expression, re.IGNORECASE)


def main() -> None:
    errors: list[str] = []
    files = repository_files()

    for path in files:
        if any(part in GENERATED for part in path.parts):
            errors.append(f"generated artifact is tracked or pending: {path}")

    former = former_surface_pattern()
    for path in files:
        if former.search(path.as_posix()):
            errors.append(f"former public name in path: {path}")
        text = readable_text(path)
        if text is None:
            continue
        if "/Users/" in text and path != Path("scripts/check_repository.py"):
            errors.append(f"absolute user path: {path}")
        match = former.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(f"former or private public-surface term in {path}:{line}")

    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for required in (
        'name: "HackyKit"',
        '.library(name: "HackyKit", targets: ["HackyKit"])',
        'name: "HackyKitTests"',
        'dependencies: ["HackyKit"]',
    ):
        if required not in package:
            errors.append(f"Package.swift missing {required}")

    source_root = ROOT / "Sources" / "HackyKit"
    test_root = ROOT / "Tests" / "HackyKitTests"
    if not source_root.is_dir():
        errors.append("Sources/HackyKit is missing")
    if not test_root.is_dir():
        errors.append("Tests/HackyKitTests is missing")

    public_source = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(source_root.glob("*.swift"))
    )
    for declaration in (
        "public struct HackyDocument",
        "public struct HackyBuilder",
        "public enum HackyActivationV01",
        "public enum HackyJSONEncoder",
        "public enum HackyValidator",
        "public enum HackyPDFRenderer",
        "public enum HackyPDFExtractor",
    ):
        if declaration not in public_source:
            errors.append(f"public API missing {declaration}")

    symbol_graph = (
        ROOT / ".build" / "arm64-apple-macosx" / "symbolgraph" / "HackyKit.symbols.json"
    )
    if symbol_graph.is_file():
        graph = json.loads(symbol_graph.read_text(encoding="utf-8"))
        public_titles = "\n".join(
            symbol.get("names", {}).get("title", "")
            for symbol in graph.get("symbols", [])
        )
        if former.search(public_titles):
            errors.append("former or private term in generated public symbol graph")

    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    if "https://github.com/openhacky/hacky-kit.git" not in readme:
        errors.append("README must use the openhacky package URL")
    if 'from: "0.1.1"' not in readme:
        errors.append("README must install the 0.1.1 patch release")

    activation_source = (source_root / "HackyActivationV01.swift").read_text(encoding="utf-8")
    canonical_japanese_ending = "Hackyの効果が切れました。"
    old_japanese_ending = "Hackyの効果が" + "なくなりました。"
    if canonical_japanese_ending not in activation_source:
        errors.append("canonical Japanese ending line is missing")
    for path in files:
        text = readable_text(path)
        if text is not None and old_japanese_ending in text:
            errors.append(f"retired Japanese ending line in {path}")

    code_license = (ROOT / "LICENSE").read_text(encoding="utf-8")
    if "Apache License" not in code_license or "Version 2.0" not in code_license:
        errors.append("LICENSE must contain Apache-2.0")
    documentation_license = (ROOT / "LICENSE-DOCS").read_text(encoding="utf-8")
    if "Creative Commons Attribution 4.0 International" not in documentation_license:
        errors.append("LICENSE-DOCS must contain CC BY 4.0")

    if errors:
        raise SystemExit("Repository invariant failure:\n- " + "\n- ".join(errors))
    print(f"repository invariants valid ({len(files)} current files)")


if __name__ == "__main__":
    main()
