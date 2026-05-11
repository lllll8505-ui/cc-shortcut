#!/usr/bin/env bash
# post-archive.sh
#
# 사용법:
#   ./post-archive.sh ~/Desktop/CC\ Shortcut.app 1.0.1
#
# 동작:
#   1. notarization 결과를 stapler로 검증 후 .app에 staple
#   2. .app을 Mac용 zip(ditto)로 압축
#   3. Sparkle EdDSA 서명 생성
#   4. appcast.xml에 새 <item> 항목을 맨 위에 삽입
#   5. git tag + push, GitHub Release 생성, zip 업로드
#
# 종료 후 모든 사용자가 다음 자동 업데이트 알림을 받습니다.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "사용법: $0 <앱경로.app> <버전>" >&2
    echo "예시:   $0 ~/Desktop/CC\\ Shortcut.app 1.0.1" >&2
    exit 1
fi

APP_PATH="$1"
VERSION="$2"
TAG="v${VERSION}"

# 프로젝트 루트 (이 스크립트 위치)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPCAST="${PROJECT_ROOT}/appcast.xml"
SIGN_UPDATE="${PROJECT_ROOT}/tools/bin/sign_update"

# 검증
if [ ! -d "$APP_PATH" ]; then
    echo "❌ .app을 찾을 수 없습니다: $APP_PATH" >&2
    exit 1
fi
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "❌ sign_update 도구가 없습니다: $SIGN_UPDATE" >&2
    exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ gh CLI가 필요합니다. brew install gh 후 gh auth login" >&2
    exit 1
fi

APP_NAME="$(basename "$APP_PATH" .app)"
ZIP_NAME="${APP_NAME// /-}-${VERSION}.zip"
ZIP_PATH="${PROJECT_ROOT}/dist/${ZIP_NAME}"
mkdir -p "${PROJECT_ROOT}/dist"

echo "▶︎ Notarization 검증 및 staple"
xcrun stapler staple "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 | sed 's/^/    /'

echo "▶︎ ZIP 압축 (ditto)"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
SIZE_BYTES=$(stat -f%z "$ZIP_PATH")
echo "    $ZIP_PATH (${SIZE_BYTES} bytes)"

echo "▶︎ Sparkle EdDSA 서명 생성"
SIGN_OUTPUT="$("$SIGN_UPDATE" "$ZIP_PATH")"
echo "    $SIGN_OUTPUT"
# sign_update 출력 예시:
#   sparkle:edSignature="abc...==" length="123456"
ED_SIGNATURE="$(echo "$SIGN_OUTPUT" | sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p')"
if [ -z "$ED_SIGNATURE" ]; then
    echo "❌ EdDSA 서명 추출 실패" >&2
    exit 1
fi

PUB_DATE="$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"

# GitHub remote에서 owner/repo 추출
GH_OWNER_REPO="$(git -C "$PROJECT_ROOT" config --get remote.origin.url \
    | sed -E 's#(git@github.com:|https://github.com/)([^/]+/[^.]+)(\.git)?#\2#')"
if [ -z "$GH_OWNER_REPO" ]; then
    echo "❌ git remote.origin.url에서 owner/repo를 읽지 못했습니다." >&2
    exit 1
fi
DOWNLOAD_URL="https://github.com/${GH_OWNER_REPO}/releases/download/${TAG}/${ZIP_NAME}"

echo "▶︎ appcast.xml 갱신"
NEW_ITEM=$(cat <<EOF
        <item>
            <title>버전 ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${SIZE_BYTES}"
                type="application/octet-stream"
                sparkle:edSignature="${ED_SIGNATURE}"/>
        </item>
EOF
)

python3 - "$APPCAST" "$NEW_ITEM" <<'PYEOF'
import sys, re
path, new_item = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
# 새 <item>을 <language>...</language> 다음, 또는 <channel> 직후에 삽입
# 항상 가장 최신이 맨 위에 오도록 첫 <item> 앞에 삽입
m = re.search(r'(\s*<item>)', content)
if m:
    insert_at = m.start()
    new = content[:insert_at] + '\n' + new_item + content[insert_at:]
else:
    new = content.replace('</channel>', new_item + '\n    </channel>')
with open(path, 'w', encoding='utf-8') as f:
    f.write(new)
print("    appcast.xml 갱신 완료")
PYEOF

echo "▶︎ git commit + tag + push"
cd "$PROJECT_ROOT"
git add appcast.xml
git commit -m "Release ${VERSION}" || echo "    (변경사항 없음, 커밋 생략)"
git tag -a "$TAG" -m "Release ${VERSION}" || echo "    (태그 이미 존재)"
git push origin HEAD
git push origin "$TAG"

echo "▶︎ GitHub Release 생성 + zip 업로드"
RELEASE_NOTES_FILE="$(mktemp)"
cat > "$RELEASE_NOTES_FILE" <<EOF
## CC Shortcut ${VERSION}

내려받기: [\`${ZIP_NAME}\`](${DOWNLOAD_URL})

이미 설치된 사용자는 메뉴바 아이콘 → "업데이트 확인..."에서 자동 업데이트됩니다.
EOF

gh release create "$TAG" "$ZIP_PATH" \
    --title "CC Shortcut ${VERSION}" \
    --notes-file "$RELEASE_NOTES_FILE" \
    --repo "$GH_OWNER_REPO"

rm -f "$RELEASE_NOTES_FILE"

echo ""
echo "✅ 완료. 모든 사용자에게 ${VERSION} 업데이트가 전파됩니다."
echo "   다운로드 URL: ${DOWNLOAD_URL}"
