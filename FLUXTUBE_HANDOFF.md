# FluxTube YouTube-Style Watch Screen — Handoff

## 저장소
- **Fork**: `https://github.com/gtoyoung/FluxTube.git` (private)
- **원본**: `https://github.com/mu-fazil-vk/FluxTube`

## CI 빌드
- **Workflow**: `.github/workflows/android-debug-build.yml`
- **트리거**: `main` 브랜치 push 시 자동 빌드
- **APK 다운로드**: GitHub → Actions → 해당 Run → Artifacts → `FluxTube-debug`
- **주의**: 기존 `android-draft-release.yml`은 비활성화됨 (signing key 없음)

---

## 변경한 파일 목록

### 신규 생성
| 파일 | 역할 |
|------|------|
| `lib/core/platform/fullscreen_utils.dart` | 전체화면 유틸 (immersive + 회전) |
| `lib/presentation/watch/youtube_like/youtube_watch_screen.dart` | 통합 Watch 화면 |
| `lib/presentation/watch/youtube_like/widgets/youtube_player_widget.dart` | 통합 플레이어 위젯 |
| `lib/presentation/watch/youtube_like/widgets/youtube_controls_overlay.dart` | YouTube 스타일 컨트롤 오버레이 |
| `lib/presentation/watch/youtube_like/widgets/youtube_quality_sheet.dart` | 화질 선택 바텀시트 |
| `lib/presentation/watch/youtube_like/widgets/youtube_video_info_section.dart` | 영상 정보 (제목/조회수/채널/액션) |

### 수정
| 파일 | 변경 |
|------|------|
| `lib/presentation/watch/screen_watch.dart` | Piped 백엔드 → `YouTubeWatchScreen` 라우팅 |

---

## 아키텍처

```
screen_watch.dart
  └─ YouTubeWatchScreen (Piped only, 나머진 기존 screen 유지)
       ├─ [Portrait] Column
       │   ├─ AspectRatio(16:9) → YouTubePlayerWidget
       │   ├─ YouTubeVideoInfoSection
       │   │   ├─ Title
       │   │   ├─ Views/Date
       │   │   ├─ ChannelInfoSection (기존 재사용)
       │   │   └─ LikeSection (기존 재사용)
       │   └─ DescriptionSection / CommentSection / RelatedVideoSection
       │
       └─ [Landscape] YouTubePlayerWidget (전체화면)
            └─ YouTubeControlsOverlay (자동숨김)
                 ├─ TopBar: back button
                 ├─ Center: replay10 / play-pause / forward10
                 └─ BottomBar: seek slider + time + quality + fullscreen
```

### 플레이어 상태 관리
- `GlobalPlayerController` (singleton) — media_kit Player + VideoController 보유
- `YouTubePlayerWidget`에서 `_globalPlayer` 참조
- 화질 변경 시 `_player.open(Media(newUrl))`으로 새 스트림 로드

---

## 현재 동작 상태

### ✅ 동작하는 것
- 기본 Piped 백엔드로 영상 재생
- 전체화면 전환 (immersive + landscape lock)
- 컨트롤 오버레이 탭 표시/자동 숨김 (4초)
- 더블탭 좌우 10초 시크
- 재생/일시정지
- Seek 바 드래그
- 화질 선택 바텀시트 (quality list → 선택 → `_player.open`)
- Portrait 레이아웃 (플레이어 + 정보 + 댓글/추천)

### ❌ 동작하지 않거나 미완성
- **Invidious/NewPipe/Explode 백엔드**: 새 WatchScreen 사용 안 함 (기존 screen 유지)
- **가로모드 상단 타이틀**: `PlayerState.title` 없어서 제거됨
- **SponsorBlock**: 연동 안 됨 (기존 `GenericPlayerSettingsSheet`에 있음)
- **재생속도/자막/오디오트랙 변경**: 아직 Quality Sheet만 있음
- **PiP**: `pipClicked` 콜백이 빈 함수로 전달됨
- **볼륨/밝기 제스처**: 필드는 있지만 구현 안 됨
- **회전 감지 자동 전체화면**: 아직 미구현 (버튼으로만 전환)

---

## 남은 작업 (우선순위 순)

### 1. 다른 백엔드 지원
현재 `YouTubeWatchScreen`은 `WatchState.watchResp` (Piped 모델)에 의존.
Invidious (`invidiousWatchResp`), NewPipe (`newpipeWatchResp`)도 지원하려면 각 백엔드별 stream 추출 로직 추가 필요.

### 2. 전체화면 개선
- `OrientationBuilder`로 기기 회전 감지 → 자동 전체화면
- 가로모드에서 시스템 back 버튼 → 전체화면 해제 (현재 PopScope에 있음)
- 컨트롤 오버레이에 현재 시간/전체 시간 가독성 개선

### 3. 설정 시트 확장
`YouTubeQualitySheet` → `YouTubeSettingsSheet`로 확장:
- 재생속도 (0.25x ~ 2x)
- 자막 선택
- 오디오 트랙 선택
- SponsorBlock 토글

### 4. 코드 정리
- 사용하지 않는 import 제거
- `core/colors.dart`의 `kGreyDarkColor` → `Colors.grey.shade800`으로 대체 (kGreyDarkColor가 실제로 존재하는지 확인 필요)
- lint 에러 수정

---

## 빌드 방법

```bash
# 로컬 (Flutter SDK 필요)
flutter pub get
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk

# CI (GitHub Actions)
git push origin main
# → 자동 빌드, Actions 탭에서 APK 다운로드
```

## 참고: CI Workflow

`.github/workflows/android-debug-build.yml`:
- `ubuntu-latest`, Java 17, Flutter stable
- `flutter build apk --debug` (서명 불필요)
- artifact 7일 보관
