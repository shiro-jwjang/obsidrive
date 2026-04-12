# Tasks: Obsidrive MVP

> Spec-Driven Development — Step 3: TASKS
> Codex + tmux phased execution 기준

---

## Phase 0: 프로젝트 세팅 (수동)

- [ ] T001 ~/projects/obsidrive 에 Flutter 프로젝트 생성
- [ ] T002 pubspec.yaml 의존성 추가 (riverpod, google_sign_in, googleapis, flutter_markdown, isar, flutter_secure_storage, path_provider)
- [ ] T003 [P] 디렉토리 구조 생성 (core/, features/auth/, features/vault/, features/reader/, features/cache/, features/settings/)
- [ ] T004 [P] .gitignore, README.md, CODEX.md 작성
- [ ] T005 git init + initial commit

---

## Phase 1: 인증 (US-1, M-01)

- [ ] T006 TDD — auth_repository 테스트 작성 (test/unit/features/auth/auth_repository_test.dart)
  - Given Google Sign-In 성공 mock, When signIn(), Then returns user with token
  - Given 저장된 토큰 존재, When restoreSession(), Then returns user without UI
  - Given 토큰 만료, When refreshToken(), Then new token returned
- [ ] T007 auth_repository 구현 (lib/features/auth/data/auth_repository.dart)
- [ ] T008 auth_provider (Riverpod) 구현 (lib/features/auth/domain/auth_state.dart)
- [ ] T009 login_screen UI 구현 (lib/features/auth/presentation/login_screen.dart)
- [ ] T010 위젯 테스트 — 로그인 화면 렌더링 + 탭 이벤트

---

## Phase 2: 볼트 선택 + 파일 스캔 (US-2, M-02)

- [ ] T011 TDD — drive_folder_service 테스트 (test/unit/features/vault/drive_folder_service_test.dart)
  - Given Drive API mock, When listFolders(), Then returns folder list
  - Given folder with .md files, When scanVault(), Then returns Note list recursively
  - Given 500+ files, When scanVault(), Then paginates correctly
  - Given .obsidian 폴더, When scanVault(), Then excludes from results
- [ ] T012 drive_folder_service 구현 (lib/features/vault/data/drive_folder_service.dart)
- [ ] T013 Isar 데이터 모델 정의 (Vault, Note, WikilinkIndex, AppSettings)
- [ ] T014 vault_repository 구현 (lib/features/vault/data/vault_repository.dart)
- [ ] T015 vault_provider (Riverpod) 구현 (lib/features/vault/domain/vault_provider.dart)
- [ ] T016 vault_picker_screen UI — 구글드라이브 폴더 탐색 + 선택

---

## Phase 3: 파일 트리 (US-7, M-07)

- [ ] T017 위젯 테스트 — folder_tree_widget (test/widget/folder_tree_widget_test.dart)
  - Given 폴더+파일 목록, When render, Then 폴더는 확장 가능, .md 파일만 표시
  - Given 폴더 탭, When expand, Then 하위 항목 표시
  - Given .md 파일 탭, When tap, Then reader_screen으로 네비게이션
- [ ] T018 folder_tree_widget 구현 (lib/features/vault/presentation/folder_tree_widget.dart)
- [ ] T019 홈 화면 통합 (folder_tree + sync status 표시)

---

## Phase 4: 마크다운 렌더링 (US-3, M-03)

- [ ] T020 TDD — frontmatter 파서 테스트 (test/unit/core/markdown_parser_test.dart)
  - Given "---\ntitle: Test\n---\ncontent", When parseFrontmatter(), Then returns "content"
  - Given no frontmatter, When parseFrontmatter(), Then returns original text
- [ ] T021 frontmatter 파서 구현 (lib/core/markdown_parser.dart)
- [ ] T022 TDD — note_content_repository 테스트 (캐시 hit/miss 로직)
  - Given 캐시된 노트, When getContent(), Then returns cached content (no API call)
  - Given 미캐시 노트, When getContent(), Then fetches from Drive + caches
  - Given 캐시 만료 (driveModifiedTime > cachedAt), When getContent(), Then re-fetches
- [ ] T023 note_content_repository 구현 (lib/features/reader/data/note_content_repository.dart)
- [ ] T024 reader_provider 구현 (lib/features/reader/domain/reader_provider.dart)
- [ ] T025 reader_screen UI — 마크다운 렌더링 + 스크롤 (lib/features/reader/presentation/reader_screen.dart)
- [ ] T026 위젯 테스트 — reader_screen 렌더링 (제목, 굵기, 리스트, 코드블록)

---

## Phase 5: 위키링크 (US-4, M-04)

- [ ] T027 TDD — wikilink 파서 테스트 (test/unit/core/wikilink_parser_test.dart)
  - Given "[[노트명]]", When parse(), Then returns [Wikilink(target="노트명")]
  - Given "[[노트명|별칭]]", When parse(), Then returns [Wikilink(target="노트명", alias="별칭")]
  - Given "[[폴더/노트명]]", When parse(), Then returns [Wikilink(target="폴더/노트명")]
  - Given "일반 텍스트 [[링크]] 일반 텍스트", When parse(), Then 링크만 추출
  - Given "[[존재안함]]", When resolveInVault(), Then targetNoteId = null
- [ ] T028 wikilink 파서 구현 (lib/core/markdown_parser.dart 확장)
- [ ] T029 WikilinkIndex 저장 로직 (노트 로드 시 자동 인덱싱)
- [ ] T030 위젯 테스트 — wikilink 탭 → 노트 열기
- [ ] T031 wikilink_span 커스텀 위젯 (lib/features/reader/presentation/wikilink_span.dart)
  - 존재하는 링크 → 파란색 + 탭 가능
  - 존재하지 않는 링크 → 회색 + "찾을 수 없음"
- [ ] T032 reader_screen에 위키링크 통합 + 백스택 관리

---

## Phase 6: 오프라인 캐시 (US-5, M-05)

- [ ] T033 TDD — cache_service 테스트 (test/unit/features/cache/cache_service_test.dart)
  - Given 온라인 + 싱크, When syncVault(), Then 모든 .md 파일 로컬 저장
  - Given 오프라인, When getCachedNote(), Then 캐시된 노트 반환
  - Given 오프라인, When getUncachedNote(), Then null 반환
  - Given 온라인 복귀, When checkForUpdates(), Then 변경분만 재다운로드
- [ ] T034 cache_service 구현 (lib/features/cache/data/cache_service.dart)
- [ ] T035 Isar 데이터베이스 초기화 + 마이그레이션 설정
- [ ] T036 네트워크 상태 감지 (connectivity_plus) + 오프라인 배너 UI

---

## Phase 7: 테마 + 설정 (US-6, M-06)

- [ ] T037 settings_repository 구현 (lib/features/settings/data/settings_repository.dart)
- [ ] T038 theme.dart — 다크/라이트 ThemeData 정의
- [ ] T039 settings_screen UI (테마 선택: 라이트/다크/시스템)
- [ ] T040 시스템 테마 변경 감지 + 자동 전환

---

## Phase 8: 통합 + 폴리싱

- [ ] T041 통합 테스트 — 로그인 → 볼트선택 → 노트읽기 → 위키링크 → 뒤로가기 전체 흐름
- [ ] T042 [P] 스플래시 스크린 + 앱 아이콘
- [ ] T043 [P] 에러 핸들링 전체 (네트워크 오류, API 할당량, 인증 만료)
- [ ] T044 앱 내 첫 실행 온보딩 가이드 (간단한 툴팁)
- [ ] T045 성능 프로파일링 (500노트 기준 로딩 시간 측정)

---

## Codex 실행 계획

### 배치 1: Phase 0 (수동) + Phase 1 (Codex)
```bash
# Phase 0은 수동으로 세팅
cd ~/projects/obsidrive
flutter create . --project-name obsidrive --org com.snailblu
# 의존성 추가 후
git add -A && git commit -m "init: project scaffold"

# Phase 1은 Codex에 위임
tmux new-session -d -s codex-obsidrive
tmux send-keys -t codex-obsidrive 'codex --full-auto exec "Phase 1: Auth 구현. specs/001-mvp/spec.md US-1 참조. T006~T010 수행. TDD: 테스트 먼저 작성 후 구현."' Enter
```

### 배치 2: Phase 2 + Phase 3 (Codex)
```bash
tmux send-keys -t codex-obsidrive 'codex --full-auto exec "Phase 2+3: 볼트 선택 + 파일 트리. specs/001-mvp/spec.md US-2, US-7 참조. T011~T019 수행. TDD."' Enter
```

### 배치 3: Phase 4 + Phase 5 (Codex)
```bash
tmux send-keys -t codex-obsidrive 'codex --full-auto exec "Phase 4+5: 마크다운 렌더링 + 위키링크. specs/001-mvp/spec.md US-3, US-4 참조. T020~T032 수행. TDD."' Enter
```

### 배치 4: Phase 6 + Phase 7 + Phase 8 (Codex)
```bash
tmux send-keys -t codex-obsidrive 'codex --full-auto exec "Phase 6+7+8: 캐시 + 테마 + 통합. specs/001-mvp/spec.md US-5, US-6 참조. T033~T045 수행. TDD."' Enter
```

---

## Milestone

| Milestone | 태스크 | 산출물 |
|-----------|--------|--------|
| M1: Auth 완료 | T001-T010 | 로그인 → 자동인증 |
| M2: 볼트 로딩 완료 | T011-T019 | 폴더 선택 → 트리 표시 |
| M3: 리더 완료 | T020-T032 | 마크다운 읽기 + 위키링크 |
| M4: MVP 완료 | T033-T045 | 오프라인 + 테마 + 통합테스트 |
