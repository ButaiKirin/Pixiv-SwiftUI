---
name: xcstrings-manager
description: Manage Xcode String Catalog (.xcstrings) localization files through a command-line interface. Used when adding, updating, or querying localization strings.
---

When managing localization strings in Localizable.xcstrings, use the localization_manager.py script:

- **Check statistics**: Run `python3 scripts/localization_manager.py stats` to see translation coverage
- **List keys**: Run `python3 scripts/localization_manager.py list [pattern]` to browse existing keys
- **Get details**: Run `python3 scripts/localization_manager.py get <key>` to view translations for a specific key
- **Search**: Run `python3 scripts/localization_manager.py search <query>` to find keys by content
- **Add new strings**: Run `python3 scripts/localization_manager.py add <key> [zh_value] [en_value]`
  - If zh_value is omitted, the key itself is used as the Chinese translation
  - If en_value is omitted, only Chinese is set and English remains empty
- **Update translations**: Run `python3 scripts/localization_manager.py update <key> <lang> <value>`
  - lang can be `zh-Hans` or `en`
- **Remove strings**: Run `python3 scripts/localization_manager.py remove <key>`

Always verify the change by running `get` or `list` after modifications.
