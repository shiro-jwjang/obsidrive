# Obsidrive — Codex Instructions

## Project
Google Drive-synced Obsidian vault markdown reader. Flutter + Riverpod.

## Conventions
- **Language**: Dart 3.x with null safety
- **State management**: Riverpod (flutter_riverpod)
- **Database**: SQLite via sqflite
- **Testing**: flutter_test + mockito. TDD mandatory — write failing test first.
- **Naming**: snake_case files, PascalCase classes, camelCase methods
- **Imports**: relative imports within project, package imports for external
- **Korean**: UI strings in Korean. Code comments and variable names in English.

## Structure
```
lib/
├── app/           # MaterialApp, theme, router
├── core/          # drive_api, markdown_parser, constants
├── features/
│   ├── auth/      # Google Sign-In (data/domain/presentation)
│   ├── vault/     # Folder selection, sync, tree
│   ├── reader/    # Markdown rendering, wikilinks
│   ├── cache/     # Offline cache
│   └── settings/  # Theme, preferences
└── shared/        # Common widgets, utils
```

## Key Patterns
- Repository pattern for data access
- Riverpod providers for state
- GoRouter for navigation
- Feature modules are self-contained (data/domain/presentation)

## Wikilink Format
- `[[노트명]]` → link to note by title
- `[[노트명|별칭]]` → link with display alias
- `[[폴더/노트명]]` → link with path

## Testing
- Unit tests: `test/unit/` — parsers, services, repositories
- Widget tests: `test/widget/` — UI components
- Integration tests: `test/integration/` — full flows
- Always run `flutter test` after changes
