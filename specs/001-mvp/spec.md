# Feature Specification: Obsidrive MVP (v1.0)

> Spec-Driven Development — Step 1: SPECIFY
> PRD: docs/PRD.md 참조

---

## User Scenarios & Testing

### US-1: 구글 계정 연결 (M-01)
**Priority:** P1 (BLOCKING — 모든 기능의 전제조건)

사용자가 처음 앱을 열면 구글 계정 로그인 화면이 나타난다. Google Sign-In으로 인증하고, 앱이 구글드라이브 읽기 권한을 획득한다. 이후 앱 재실행 시 자동 로그인된다.

**Acceptance Scenarios:**
1. **Given** 앱 첫 실행, **When** 시작 화면에서 "구글 계정으로 시작" 탭, **Then** 구글 로그인 시트 표시 → 성공 시 홈화면 이동
2. **Given** 로그인된 상태, **When** 앱 재실행, **Then** 자동 로그인 → 홈화면 바로 표시
3. **Given** 토큰 만료 상태, **When** API 호출, **Then** refresh_token으로 자동 갱신 → 사용자 무감지
4. **Given** 로그인 실패(네트워크 오류), **When** 재시도, **Then** 에러 메시지 + 재시도 버튼

**Edge Cases:**
- 구글 계정에 구글드라이브가 비활성화된 경우?
- 다중 구글 계정 기기에서 계정 선택?
- 앱 권한 거부 후 재요청?

---

### US-2: 볼트 폴더 선택 (M-02, M-07)
**Priority:** P1

사용자가 구글드라이브 내 옵시디언 볼트 폴더를 선택한다. 앱이 폴더를 재귀적으로 스캔하여 .md 파일 목록을 가져오고, 폴더 트리로 표시한다.

**Acceptance Scenarios:**
1. **Given** 첫 로그인 완료, **When** 볼트 폴더 선택 화면, **Then** 구글드라이브 루트 폴더 목록 표시
2. **Given** 폴더 선택, **When** "이 폴더를 볼트로 사용" 탭, **Then** 하위 .md 파일 재귀 스캔 → 완료 후 트리 표시
3. **Given** 볼트 설정 완료 상태, **When** 앱 재실행, **Then** 저장된 볼트 폴더 기준으로 바로 트리 표시
4. **Given** 볼트 내 500개 이상 파일, **When** 스캔, **Then** 페이지네이션으로 전체 스캔 (Drive API 페이지당 1000개)

**Edge Cases:**
- 선택한 폴더에 .md 파일이 없는 경우?
- 폴더가 너무 깊이 중첩된 경우 (100+ depth)?
- 구글드라이브 용량 초과 폴더?
- 한글/일본어 파일명 인코딩?

---

### US-3: 마크다운 노트 읽기 (M-03)
**Priority:** P1

사용자가 파일 트리에서 .md 파일을 탭하면, 마크다운이 렌더링된 화면이 표시된다.

**Acceptance Scenarios:**
1. **Given** 볼트 싱크 완료, **When** 노트 파일 탭, **Then** 마크다운 렌더링된 내용 표시 (제목, 굵기, 리스트, 표, 코드블록)
2. **Given** 노트 열람 중, **When** 스크롤, **Then** 부드러운 스크롤 (60fps)
3. **Given** 빈 .md 파일, **When** 열기, **Then** "빈 노트" 안내 표시

**Edge Cases:**
- 매우 큰 파일 (10,000줄 이상)?
- 잘못된 마크다운 문법?
- frontmatter (YAML `---`) 처리?

---

### US-4: 위키링크 탐색 (M-04)
**Priority:** P1

마크다운 내 `[[노트명]]` 형태의 위키링크를 인식하고, 탭하면 해당 노트가 새 탭으로 열린다.

**Acceptance Scenarios:**
1. **Given** 노트에 `[[다른 노트]]` 포함, **When** 렌더링, **Then** 링크로 표시 (파란색 + 탭 가능)
2. **Given** 위키링크 탭, **When** 해당 파일이 볼트에 존재, **Then** 새 탭으로 노트 열기
3. **Given** 위키링크 탭, **When** 해당 파일이 볼트에 없음, **Then** "노트를 찾을 수 없습니다" 안내
4. **Given** `[[노트명|별칭]]` 형태, **When** 렌더링, **Then** "별칭" 텍스트로 표시, 탭 시 "노트명"으로 이동
5. **Given** `[[폴더/노트명]]` 형태, **When** 탭, **Then** 경로 포함하여 해당 노트 열기

**Edge Cases:**
- 동명 노트가 여러 폴더에 있는 경우?
- 파일 확장자 포함/미포함 (`[[note]]` vs `[[note.md]]`)?
- 자기 참조 링크 (`[[자기자신]]`)?

---

### US-5: 오프라인 캐시 (M-05)
**Priority:** P1

네트워크 연결 시 볼트 파일을 로컬에 저장하여, 오프라인에서도 열람할 수 있다.

**Acceptance Scenarios:**
1. **Given** Wi-Fi 연결 + 볼트 싱크 완료, **When** 네트워크 해제 후 앱 사용, **Then** 캐시된 모든 노트 정상 열람
2. **Given** 오프라인 상태, **When** 캐시되지 않은 노트 링크 탭, **Then** "오프라인 — 싱크 후 사용 가능" 안내
3. **Given** 온라인 복귀, **When** 앱 포그라운드, **Then** 자동으로 변경분 싱크

**Edge Cases:**
- 캐시 용량 관리 (1GB 이상 볼트)?
- 앱 업데이트 후 캐시 호환성?
- 부분 싱크 중 네트워크 단절?

---

### US-6: 테마 전환 (M-06)
**Priority:** P2

사용자가 다크/라이트/시스템 자동 중 테마를 선택할 수 있다.

**Acceptance Scenarios:**
1. **Given** 설정 화면, **When** 테마 옵션 선택 (다크/라이트/시스템), **Then** 즉시 적용
2. **Given** 시스템 자동 모드, **When** OS 다크모드 전환, **Then** 앱 테마 자동 전환
3. **Given** 노트 열람 중, **When** 테마 전환, **Then** 렌더링 깜빡임 없이 전환

---

### US-7: 파일/폴더 트리 탐색 (M-07)
**Priority:** P1

옵시디언 볼트의 폴더 구조를 트리 뷰로 표시하고, 탭하여 하위 폴더/파일을 탐색한다.

**Acceptance Scenarios:**
1. **Given** 볼트 싱크 완료, **When** 홈 화면, **Then** 폴더 트리 표시 (접힌 상태)
2. **Given** 폴더 탭, **When** 확장, **Then** 하위 폴더 + .md 파일 표시
3. **Given** .md 파일 탭, **When** 열기, **Then** 마크다운 렌더링 화면으로 이동
4. **Given** 폴더에 .md 외 파일 존재, **When** 트리 표시, **Then** .md 파일만 표시 (이미지 등은 숨김)

---

## Requirements

### Functional Requirements

- **FR-001:** System MUST authenticate user via Google Sign-In with drive.readonly scope
- **FR-002:** System MUST let user select a Google Drive folder as vault root
- **FR-003:** System MUST recursively scan selected folder for .md files via Drive API v3
- **FR-004:** System MUST render GFM markdown (headings, bold, italic, lists, tables, code blocks, blockquotes, links, images)
- **FR-005:** System MUST parse `[[wikilink]]`, `[[name|alias]]`, `[[path/name]]` patterns
- **FR-006:** System MUST open wikilink target in a new navigation tab
- **FR-007:** System MUST cache synced files locally for offline access
- **FR-008:** System MUST support dark, light, and system-auto themes
- **FR-009:** System MUST display folder tree with expand/collapse
- **FR-010:** System MUST skip frontmatter (YAML `---` block) in rendering
- **FR-011:** System MUST show "not found" for broken wikilinks
- **FR-012:** System MUST persist vault selection across app restarts
- **FR-013:** System MUST auto-refresh Google OAuth token on expiry

### Key Entities

- **Vault:** 사용자가 선택한 구글드라이브 폴더. id, name, driveFolderId, lastSyncedAt
- **Note:** .md 파일. id, title, filePath, driveFileId, content, cachedAt, updatedAt
- **Wikilink:** 노트 간 링크. sourceNoteId, targetTitle, targetNoteId(nullable), alias(nullable)
- **SyncStatus:** 싱크 상태. vaultId, totalFiles, syncedFiles, status(idle/syncing/error), lastError
- **AppSettings:** 테마, 선택 볼트, 캐시 용량. themeMode, selectedVaultId, cacheSizeMB

---

## Assumptions

- 볼트 크기는 초기에 1,000노트 이하로 가정
- 구글드라이브 API는 읽기 전용 (v1에서는 업로드 불필요)
- .md 파일만 타겟, 이미지/첨부는 v1.5에서 처리
- Firebase 프로젝트는 별도 수동 설정 (google-services.json / GoogleService-Info.plist)
- Flutter 3.22+ 기준

## Open Questions

- [NEEDS CLARIFICATION: .obsidian 폴더(옵시디언 설정)도 트리에 표시할지? → 기본 숨김 권장]
- [NEEDS CLARIFICATION: 동명 노트 충돌 시 어떻게 처리? → 첫 번째 매치 + 경로 표시? 사용자 선택?]
