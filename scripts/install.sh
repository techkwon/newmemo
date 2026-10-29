#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${NEWMEMO_INSTALL_SOURCE:-$PWD/build/새 메모.app}"
DEST="${NEWMEMO_INSTALL_DESTINATION:-$HOME/Applications/새 메모.app}"
LSREGISTER="${NEWMEMO_INSTALL_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}"
if [ ! -d "$SOURCE" ]; then bash scripts/build.sh; fi
if pgrep -x NewMemo >/dev/null; then
  echo "열려 있는 새 메모 문서를 저장하고 앱을 종료한 뒤 다시 설치해 주세요." >&2
  exit 1
fi
if [ -L "$DEST" ] || { [ -e "$DEST" ] && [ ! -d "$DEST" ]; }; then
  echo "설치 대상이 일반 앱 폴더가 아닙니다: $DEST" >&2
  exit 1
fi
mkdir -p "$(dirname "$DEST")"
# Atomic mkdir serializes installers targeting the same bundle.
LOCK="$DEST.install-lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "같은 앱의 설치가 진행 중이거나 이전 설치 잠금이 남아 있습니다: $LOCK" >&2
  exit 1
fi
STAGING=""
STAGED=""
STAGED_ID=""
BACKUP=""
UNREGISTERED=0
COMPLETED=0
cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [ "$COMPLETED" -eq 0 ]; then
    # Inspect filesystem identity rather than a flag set after mv: a signal can
    # arrive between the successful rename and the next shell statement.
    if [ -n "$STAGED_ID" ] && [ "$(stat -f '%d:%i' "$DEST" 2>/dev/null)" = "$STAGED_ID" ]; then
      "$LSREGISTER" -u "$DEST" >/dev/null 2>&1
      if ! rm -rf "$DEST"; then
        echo "실패한 설치를 제거하지 못했습니다. 백업을 보존했습니다: $BACKUP" >&2
        rmdir "$LOCK"
        exit 1
      fi
    fi
    if [ -n "$BACKUP" ] && [ -d "$BACKUP" ]; then
      if [ -e "$DEST" ] || [ -L "$DEST" ]; then
        echo "설치 대상에 다른 항목이 있어 이전 앱을 덮어쓰지 않았습니다. 백업을 보존했습니다: $BACKUP" >&2
        rmdir "$LOCK"
        exit 1
      fi
      if ! mv "$BACKUP" "$DEST"; then
        echo "이전 앱을 복원하지 못했습니다. 백업을 보존했습니다: $BACKUP" >&2
        rmdir "$LOCK"
        exit 1
      fi
    fi
    if [ "$UNREGISTERED" -eq 1 ] && [ -d "$DEST" ]; then
      if ! "$LSREGISTER" -f "$DEST"; then
        echo "이전 앱은 복원했지만 Finder 등록을 복구하지 못했습니다: $DEST" >&2
        status=1
      fi
    fi
  fi
  if [ -n "$STAGING" ]; then rm -rf "$STAGING"; fi
  rmdir "$LOCK"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Keep staging and backup on the destination volume so replacement uses rename.
STAGING=$(mktemp -d "$(dirname "$DEST")/.newmemo-install.XXXXXX")
STAGED="$STAGING/새 메모.app"
BACKUP="$STAGING/previous.app"
# Verify a fresh bundle before changing the installed app or its registration.
ditto "$SOURCE" "$STAGED"
codesign --verify --deep --strict "$STAGED"
STAGED_ID=$(stat -f '%d:%i' "$STAGED")
if pgrep -x NewMemo >/dev/null; then
  echo "검증 중 새 메모가 실행되었습니다. 문서를 저장하고 앱을 종료한 뒤 다시 설치해 주세요." >&2
  exit 1
fi
if [ -d "$DEST" ]; then
  UNREGISTERED=1
  "$LSREGISTER" -u "$DEST"
fi
pkill -TERM -x NewMemoFinder || true
if [ -d "$DEST" ]; then
  mv "$DEST" "$BACKUP"
fi
mv "$STAGED" "$DEST"
codesign --verify --deep --strict "$DEST"
"$LSREGISTER" -f "$DEST"
COMPLETED=1
# Opening the app lets macOS discover its extension. Explicit pluginkit -a would
# create duplicate registry entries on macOS 27 when automatic discovery follows.
if ! open "$DEST"; then
  echo "설치는 완료했지만 앱을 열지 못했습니다. 설치된 앱을 직접 열어 주세요: $DEST" >&2
fi
echo "설치 완료: $DEST"
echo "Finder 메뉴가 보이지 않으면 앱의 ‘Finder 확장 설정’을 열어 ‘새 메모 Finder 메뉴’를 켜세요."
