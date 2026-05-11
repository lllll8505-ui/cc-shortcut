# CC Shortcut

macOS 단축키 리매핑 앱. 시스템 단축키보다 높은 우선순위로 동작하며, 사용자가 등록한 "트리거 단축키"를 누르면 "원본 단축키"가 실행됩니다.

- 메뉴바 전용 (Dock 미표시)
- Accessibility 권한 필요
- 자동 업데이트 지원 (Sparkle)

## 사용

1. 앱 실행 시 손쉬운 사용 권한 허용
2. 메뉴바 아이콘 좌클릭 → 설정 윈도우
3. `+`로 규칙 추가 → 트리거 단축키 입력 → 원본 단축키 입력 → 저장
4. 메뉴바 아이콘 우클릭 → "업데이트 확인…" / "종료"

## 개발자: 새 버전 릴리스

```bash
# 1. Xcode에서 MARKETING_VERSION / CURRENT_PROJECT_VERSION 올림
# 2. Product → Archive
# 3. Organizer → Distribute App → Developer ID → Upload → 공증 통과 후 Export
# 4. 바탕화면에 받은 .app으로 아래 실행:
./post-archive.sh ~/Desktop/CC\ Shortcut.app 1.0.1
```

`post-archive.sh`가 staple → zip → Sparkle 서명 → appcast.xml 갱신 → git tag → GitHub Release까지 자동 처리합니다.
