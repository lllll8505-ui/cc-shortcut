#!/usr/bin/env bash
# reset-as-fresh-user.sh
#
# 신규 사용자가 앱을 처음 설치한 상태로 되돌립니다.
# (TCC 권한 + 저장된 규칙 + UserDefaults 모두 초기화)
#
# 사용:  ./reset-as-fresh-user.sh

set -e

BUNDLE_ID="com.ccmmjj.CC-Shortcut"
APP_NAME="CC Shortcut"

echo "▶︎ 앱 종료 시도"
osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || echo "    (실행 중이 아님)"
# 안전을 위해 잠깐 대기
sleep 1
pkill -x "$APP_NAME" 2>/dev/null || true

echo "▶︎ TCC 손쉬운 사용 권한 초기화"
tccutil reset Accessibility "$BUNDLE_ID" 2>&1 | sed 's/^/    /'

echo "▶︎ 저장된 규칙 삭제"
rm -rf "$HOME/Library/Application Support/$APP_NAME" && echo "    OK"

echo "▶︎ UserDefaults 삭제 (Sparkle 상태 등)"
defaults delete "$BUNDLE_ID" 2>/dev/null && echo "    OK" || echo "    (이미 비어있음)"

echo ""
echo "✅ 초기화 완료. Xcode에서 ⌘⇧K (Clean Build Folder) 후 ⌘R로 실행하면"
echo "   처음 설치한 사용자가 보는 화면으로 시작합니다."
