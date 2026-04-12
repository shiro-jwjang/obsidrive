# Implementation Plan: Obsidrive MVP

> Spec-Driven Development — Step 2: PLAN

---

## Summary

구글드라이브 기반 옵시디언 볼트 모바일 리더. Flutter + Riverpod 아키텍처로 Google Drive API v3 연동, 마크다운 렌더링, 위키링크 탐색, 오프라인 캐시를 구현.

## Technical Context

**Language/Version:** Dart 3.x (Flutter 3.22+)
**Primary Dependencies:** flutter, flutter_riverpod, google_sign_in, googleapis, flutter_markdown, isar, flutter_secure_storage
**Storage:** Isar (로컬 DB) + 파일시스템 캐시
**Testing:** flutter_test, mockito, integration_test
**Target Platform:** iOS 15+ / Android API 26+
**CI:** GitHub Actions (lint + unit test; iOS 빌드는 Mac runner 필요, 초기엔 수동)

## Architecture: Feature-First + Clean Layering

```
lib/
├── app/                        # 앱 진입점, 테마, 라우팅
│   ├── app.dart                # MaterialApp + Riverpod
│   ├── theme.dart              # 다크/라이트 테마 정의
│   └── router.dart             # GoRouter (필요시)
│
├── core/                       # 공통 인프라
│   ├── drive_api.dart          # Google Drive API v3 래퍼
│   ├── auth_provider.dart      # Google Sign-In 상태 관리
│   ├── markdown_parser.dart    # 위키링크, 태그, frontmatter 파서
│   └── constants.dart          # 상수
│
├── features/
│   ├── auth/                   # M-01: 인증
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── domain/
│   │   │   └── auth_state.dart
│   │   └── presentation/
│   │       └── login_screen.dart
│   │
│   ├── vault/                  # M-02, M-07: 볼트 선택 + 트리
│   │   ├── data/
│   │   │   ├── drive_folder_service.dart
│   │   │   └── vault_repository.dart
│   │   ├── domain/
│   │   │   ├── vault.dart (entity)
│   │   │   ├── note.dart (entity)
│   │   │   ├── sync_status.dart (entity)
│   │   │   └── vault_provider.dart
│   │   └── presentation/
│   │       ├── vault_picker_screen.dart
│   │       └── folder_tree_widget.dart
│   │
│   ├── reader/                 # M-03, M-04: 마크다운 + 위키링크
│   │   ├── data/
│   │   │   └── note_content_repository.dart
│   │   ├── domain/
│   │   │   └── reader_provider.dart
│   │   └── presentation/
│   │       ├── reader_screen.dart
│   │       └── wikilink_span.dart
│   │
│   ├── cache/                  # M-05: 오프라인 캐시
│   │   ├── data/
│   │   │   ├── cache_service.dart
│   │   │   └── isar_database.dart
│   │   └── domain/
│   │       └── cache_provider.dart
│   │
│   └── settings/               # M-06: 테마 + 설정
│       ├── data/
│       │   └── settings_repository.dart
│       └── presentation/
│           └── settings_screen.dart
│
└── main.dart

test/
├── unit/
│   ├── core/
│   │   └── markdown_parser_test.dart
│   ├── features/
│   │   ├── vault/
│   │   │   └── drive_folder_service_test.dart
│   │   ├── reader/
│   │   │   └── wikilink_test.dart
│   │   └── cache/
│   │       └── cache_service_test.dart
│   └── ...
├── widget/
│   ├── folder_tree_widget_test.dart
│   └── reader_screen_test.dart
└── integration/
    └── app_test.dart
```

## Data Model (Isar)

### Vault
```
@collection
class Vault {
  Id id = Isar.autoIncrement;
  String driveFolderId;    // Google Drive folder ID
  String name;             // Display name
  String? parentPath;      // Root path in Drive
  DateTime lastSyncedAt;
}
```

### Note
```
@collection
class Note {
  Id id = Isar.autoIncrement;
  String driveFileId;      // Google Drive file ID
  String title;            // Filename without .md
  String filePath;         // Full path relative to vault root
  String? cachedContent;   // Cached markdown content
  DateTime? cachedAt;
  DateTime driveModifiedTime;
  int vaultId;             // FK to Vault
}
```

### WikilinkIndex
```
@collection
class WikilinkIndex {
  Id id = Isar.autoIncrement;
  int sourceNoteId;        // Note that contains the link
  String targetTitle;      // [[target title]]
  int? resolvedNoteId;     // Resolved target note (null if broken)
  String? alias;           // [[target|alias]]
}
```

### AppSettings
```
@collection
class AppSettings {
  Id id = 0;               // Singleton
  String themeMode;        // 'light' | 'dark' | 'system'
  int? selectedVaultId;
}
```

## Google Drive API 인증 설계

### 흐름
1. `google_sign_in` 패키지로 사용자 인증
2. Scopes: `drive.readonly` (필요시 `drive.appdata`)
3. 인증 성공 → `GoogleAuthClient` (http Client wrapper) 생성
4. `googleapis/drive/v3.dart` API 인스턴스 생성
5. 토큰 → `flutter_secure_storage`에 암호화 저장

### API 사용 패턴
```dart
// 폴더 내 .md 파일 재귀 목록
drive.files.list(
  q: "'{folderId}' in parents and mimeType='text/markdown' or name contains '.md'",
  spaces: 'drive',
  fields: 'files(id,name,modifiedTime,parents),nextPageToken',
  pageSize: 1000,
);

// 파일 내용 다운로드
drive.files.get(fileId, downloadOptions: DownloadOptions.fullMedia);
```

## Wikilink 파서 설계

### 파싱 대상 패턴
```
[[노트명]]           → target="노트명", alias=null
[[노트명|별칭]]       → target="노트명", alias="별칭"
[[폴더/노트명]]       → target="폴더/노트명", alias=null
[[#해딩]]            → target=null, heading="해딩" (v1.5)
```

### 정규식
```dart
final wikilinkRegex = RegExp(r'\[\[([^\]|#]+?)(?:\|([^\]]+?))?\]\]');
```

### 렌더링 전략
- flutter_markdown의 `MarkdownElementBuilder` 커스텀 확장
- `[[...]]` 패턴을 special inline syntax로 처리
- 링크 탭 → 볼트 내 title 기반 Isar 쿼리 → 노트 열기

## Constitution Check

- [x] 최대 3개 모듈 구조? → core / features / app (3레이어)
- [x] 프레임워크 직접 사용? → Riverpod 직접, 불필요한 추상화 없음
- [x] 테스트 전략 정의됨? → Unit (파서, 서비스) + Widget (화면) + Integration (전체 흐름)
- [x] TDD 적용? → 파서, 서비스 레이어는 반드시 TDD

## Testing Strategy

| 레이어 | 테스트 종류 | 비고 |
|--------|------------|------|
| core/markdown_parser | Unit | 위키링크, frontmatter 파싱 |
| features/vault/data | Unit | Drive API 모킹 |
| features/cache/data | Unit | Isar CRUD |
| features/reader | Widget | 마크다운 렌더링 + 링크 탭 |
| E2E | Integration | 로그인 → 볼트선택 → 노트읽기 |

**TDD 필수 대상:**
- markdown_parser (위키링크 파싱)
- drive_folder_service (API 래핑)
- cache_service (오프라인 로직)

---

## Next Step

→ tasks.md 에서 Phase별 태스크 분해 후 Codex + tmux로 실행
