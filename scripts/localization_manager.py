#!/usr/bin/env python3
"""
Localization Manager for Xcode String Catalog (.xcstrings)

This script provides a simple interface for coding agents to manage
Localizable.xcstrings files without directly editing the large JSON file.

Usage:
    python localization_manager.py <command> [args]

Commands:
    list [pattern]              List all keys (optional: filter by pattern)
    get <key>                   Get a specific key's translations
    add <key> [zh] [en]         Add a new key with optional translations
    update <key> <lang> <val>   Update translation for a specific language
    remove <key>                Remove a key
    stats                       Show statistics about the catalog
    search <query>              Search keys and translations
"""

import json
import sys
import os
from pathlib import Path
from typing import Optional

DEFAULT_CATALOG_PATH = Path(__file__).parent.parent / "Pixiv-SwiftUI" / "Localizable.xcstrings"


def load_catalog(path: Path) -> dict:
    """Load the xcstrings catalog from file."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_catalog(path: Path, data: dict) -> None:
    """Save the xcstrings catalog to file with proper formatting."""
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def list_keys(catalog: dict, pattern: Optional[str] = None, limit: int = 50) -> None:
    """List all keys in the catalog, optionally filtered by pattern."""
    strings = catalog.get("strings", {})
    keys = list(strings.keys())

    if pattern:
        keys = [k for k in keys if pattern.lower() in k.lower()]

    print(f"\nFound {len(keys)} keys" + (f" (filtered by '{pattern}')" if pattern else "") + ":\n")

    for i, key in enumerate(keys[:limit]):
        localizations = strings[key].get("localizations", {})
        en_val = localizations.get("en", {}).get("stringUnit", {}).get("value", "N/A")
        status = "✓" if "en" in localizations else "✗"
        print(f"  [{status}] {key}")
        print(f"      EN: {en_val[:60]}{'...' if len(en_val) > 60 else ''}")

    if len(keys) > limit:
        print(f"\n  ... and {len(keys) - limit} more (use a more specific pattern to filter)")


def get_key(catalog: dict, key: str) -> None:
    """Get details for a specific key."""
    strings = catalog.get("strings", {})

    if key not in strings:
        print(f"Error: Key '{key}' not found")
        # Try to suggest similar keys
        similar = [k for k in strings.keys() if key.lower() in k.lower() or k.lower() in key.lower()]
        if similar:
            print(f"\nDid you mean one of these?")
            for s in similar[:5]:
                print(f"  - {s}")
        return

    entry = strings[key]
    print(f"\nKey: {key}")
    print("=" * 60)

    localizations = entry.get("localizations", {})

    # Show all available languages
    for lang, data in localizations.items():
        unit = data.get("stringUnit", {})
        state = unit.get("state", "unknown")
        value = unit.get("value", "")
        print(f"\n  Language: {lang}")
        print(f"  State: {state}")
        print(f"  Value: {value}")

    if not localizations:
        print("  No localizations found")


def add_key(catalog: dict, key: str, zh_value: Optional[str] = None, en_value: Optional[str] = None) -> None:
    """Add a new key to the catalog."""
    strings = catalog.get("strings", {})

    if key in strings:
        print(f"Error: Key '{key}' already exists")
        return

    entry = {"localizations": {}}

    # Always add zh-Hans as source language
    zh_val = zh_value if zh_value else key
    entry["localizations"]["zh-Hans"] = {
        "stringUnit": {
            "state": "translated",
            "value": zh_val
        }
    }

    # Add English translation if provided
    if en_value:
        entry["localizations"]["en"] = {
            "stringUnit": {
                "state": "translated",
                "value": en_value
            }
        }

    strings[key] = entry
    catalog["strings"] = strings

    print(f"✓ Added key: '{key}'")
    if en_value:
        print(f"  zh-Hans: {zh_val}")
        print(f"  en: {en_value}")
    else:
        print(f"  zh-Hans: {zh_val}")
        print(f"  en: (not set - will use key as fallback)")


def update_translation(catalog: dict, key: str, language: str, value: str) -> None:
    """Update translation for a specific language."""
    strings = catalog.get("strings", {})

    if key not in strings:
        print(f"Error: Key '{key}' not found")
        return

    if language not in ["zh-Hans", "en"]:
        print(f"Error: Unsupported language '{language}'. Use 'zh-Hans' or 'en'")
        return

    entry = strings[key]
    if "localizations" not in entry:
        entry["localizations"] = {}

    entry["localizations"][language] = {
        "stringUnit": {
            "state": "translated",
            "value": value
        }
    }

    print(f"✓ Updated '{key}' [{language}]: {value}")


def remove_key(catalog: dict, key: str) -> None:
    """Remove a key from the catalog."""
    strings = catalog.get("strings", {})

    if key not in strings:
        print(f"Error: Key '{key}' not found")
        return

    del strings[key]
    print(f"✓ Removed key: '{key}'")


def show_stats(catalog: dict) -> None:
    """Show statistics about the catalog."""
    strings = catalog.get("strings", {})
    source_lang = catalog.get("sourceLanguage", "unknown")

    total_keys = len(strings)
    en_count = sum(1 for e in strings.values() if "en" in e.get("localizations", {}))
    zh_count = sum(1 for e in strings.values() if "zh-Hans" in e.get("localizations", {}))

    print("\nLocalization Catalog Statistics")
    print("=" * 40)
    print(f"Source Language: {source_lang}")
    print(f"Total Keys: {total_keys}")
    print(f"\nTranslation Coverage:")
    print(f"  English (en): {en_count}/{total_keys} ({100*en_count/total_keys:.1f}%)")
    print(f"  Chinese (zh-Hans): {zh_count}/{total_keys} ({100*zh_count/total_keys:.1f}%)")


def search_catalog(catalog: dict, query: str) -> None:
    """Search for keys and translations."""
    strings = catalog.get("strings", {})
    query_lower = query.lower()

    results = []
    for key, entry in strings.items():
        if query_lower in key.lower():
            results.append((key, "key"))
            continue

        localizations = entry.get("localizations", {})
        for lang, data in localizations.items():
            value = data.get("stringUnit", {}).get("value", "")
            if query_lower in value.lower():
                results.append((key, f"translation ({lang})"))
                break

    print(f"\nSearch results for '{query}' ({len(results)} matches):\n")
    for key, match_type in results[:20]:
        print(f"  [{match_type}] {key}")
    if len(results) > 20:
        print(f"\n  ... and {len(results) - 20} more")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1]
    args = sys.argv[2:]

    # Allow custom path via environment variable
    catalog_path = Path(os.environ.get("XCSTRINGS_PATH", DEFAULT_CATALOG_PATH))

    if not catalog_path.exists():
        print(f"Error: Catalog file not found: {catalog_path}")
        sys.exit(1)

    # Load catalog
    try:
        catalog = load_catalog(catalog_path)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in catalog file: {e}")
        sys.exit(1)

    modified = False

    # Execute command
    if command == "list":
        pattern = args[0] if args else None
        list_keys(catalog, pattern)

    elif command == "get":
        if not args:
            print("Error: Missing key argument")
            print("Usage: get <key>")
            sys.exit(1)
        get_key(catalog, args[0])

    elif command == "add":
        if not args:
            print("Error: Missing key argument")
            print("Usage: add <key> [zh_value] [en_value]")
            sys.exit(1)
        key = args[0]
        zh_value = args[1] if len(args) > 1 else None
        en_value = args[2] if len(args) > 2 else None
        add_key(catalog, key, zh_value, en_value)
        modified = True

    elif command == "update":
        if len(args) < 3:
            print("Error: Missing arguments")
            print("Usage: update <key> <language> <value>")
            print("  language: 'zh-Hans' or 'en'")
            sys.exit(1)
        update_translation(catalog, args[0], args[1], args[2])
        modified = True

    elif command == "remove":
        if not args:
            print("Error: Missing key argument")
            print("Usage: remove <key>")
            sys.exit(1)
        remove_key(catalog, args[0])
        modified = True

    elif command == "stats":
        show_stats(catalog)

    elif command == "search":
        if not args:
            print("Error: Missing query argument")
            print("Usage: search <query>")
            sys.exit(1)
        search_catalog(catalog, args[0])

    else:
        print(f"Unknown command: {command}")
        print(__doc__)
        sys.exit(1)

    # Save if modified
    if modified:
        save_catalog(catalog_path, catalog)
        print(f"\n✓ Changes saved to {catalog_path}")


if __name__ == "__main__":
    main()
