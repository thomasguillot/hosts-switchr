#!/usr/bin/env python3
"""Keep App/Sources/Localizable.xcstrings in step with the strings in the source.

`xcodebuild` never writes back to a String Catalog — merging extracted keys into it is an Xcode
IDE behaviour — so a headless build silently leaves new strings out of the catalog and they ship
as untranslated English. This reads the compiler's own .stringsdata output instead, which is the
same extraction the IDE uses.

  scripts/sync-localizations.py            add new keys, drop stale ones, mirror en to en-GB
  scripts/sync-localizations.py --check    report only, non-zero exit if anything is off (CI)

en-GB is kept as a mirror of en. Nothing in the current copy differs between US and UK English,
so mirroring is what makes the app actually advertise English (UK) rather than falling back
silently. To diverge a string, add it to EN_GB_OVERRIDES and this script will leave it alone.
"""
import argparse
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App/Sources/Localizable.xcstrings"
DERIVED = ROOT / "App/build/loc"
REQUIRED = ["en", "fr", "es"]

# Keys whose en-GB wording is deliberately not a copy of en.
EN_GB_OVERRIDES: set[str] = set()


def build():
    subprocess.run(
        ["xcodebuild", "-project", "HostsSwitchr.xcodeproj", "-scheme", "HostsSwitchr",
         "-destination", "platform=macOS", "-derivedDataPath", str(DERIVED), "build"],
        cwd=ROOT / "App", check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def extracted_keys():
    """Keys declared by the app target only. The build compiles HostsKit too, and its strings
    belong to the package's own catalog, so filter on the source file each entry came from."""
    app_sources = str(ROOT / "App/Sources")
    found = {}
    for path in DERIVED.rglob("*.stringsdata"):
        data = json.loads(path.read_text())
        if not str(data.get("source", "")).startswith(app_sources):
            continue
        for entries in data.get("tables", {}).values():
            for entry in entries:
                found.setdefault(entry["key"], entry.get("comment") or "")
    if not found:
        sys.exit("error: no .stringsdata found for the app target — did the build run?")
    return found


def mirror(unit):
    """en-GB copy of an en localization, preserving plural variations."""
    return json.loads(json.dumps(unit))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="report only, never write")
    args = parser.parse_args()

    build()
    keys = extracted_keys()
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]

    added = [k for k in keys if k not in strings]
    stale = [k for k in strings if k not in keys]

    if not args.check:
        for key in added:
            entry = {"extractionState": "manual",
                     "localizations": {"en": {"stringUnit": {"state": "new", "value": key}}}}
            if keys[key]:
                entry["comment"] = keys[key]
            strings[key] = entry
        for key in stale:
            del strings[key]
        for key, entry in strings.items():
            if key in EN_GB_OVERRIDES or entry.get("shouldTranslate") is False:
                continue
            localizations = entry.get("localizations")
            if localizations and "en" in localizations:
                localizations["en-GB"] = mirror(localizations["en"])
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

    untranslated = {}
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        missing = [lang for lang in REQUIRED if lang not in localizations]
        if missing:
            untranslated[key] = missing

    verb = ("missing from", "orphaned in") if args.check else ("added to", "removed from")
    if added:
        print(f"{len(added)} key(s) {verb[0]} the catalog: " + ", ".join(sorted(added)[:5]))
    if stale:
        print(f"{len(stale)} key(s) {verb[1]} the catalog: " + ", ".join(sorted(stale)[:5]))
    for key, missing in sorted(untranslated.items()):
        print(f"  untranslated ({', '.join(missing)}): {key}")

    if untranslated or (args.check and (added or stale)):
        sys.exit(f"{len(untranslated)} string(s) need translating; "
                 f"{len(added)} key(s) not in the catalog")
    print(f"{len(strings)} string(s), all languages present")


if __name__ == "__main__":
    main()
