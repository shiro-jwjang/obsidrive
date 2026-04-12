# Obsidrive

Google Drive-synced Obsidian vault markdown reader for mobile.

## Setup

```bash
flutter pub get
flutter test
flutter run -d chrome    # Web preview
flutter run              # iOS (Mac only, requires Xcode)
```

## Architecture

Feature-first + clean layering. See `specs/001-mvp/plan.md` for details.

```
lib/
├── app/           # Theme, routing, app entry
├── core/          # Shared infrastructure (API, parsers)
├── features/      # Feature modules (auth, vault, reader, cache, settings)
└── shared/        # Common widgets, utilities
```

## Development

- **Spec-Driven Development**: See `specs/001-mvp/`
- **TDD**: Write failing test → implement → refactor
- **State**: Riverpod
- **DB**: SQLite (sqflite) — works on web, iOS, Android
