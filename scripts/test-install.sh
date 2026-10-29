#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL_SCRIPT="${1:-$PWD/scripts/install.sh}"
FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/newmemo-install-test.XXXXXX")
ACTIVE_INSTALL_PID=""
cleanup_fixture() {
  if [ -n "$ACTIVE_INSTALL_PID" ]; then
    kill -TERM "$ACTIVE_INSTALL_PID" 2>/dev/null || true
    wait "$ACTIVE_INSTALL_PID" 2>/dev/null || true
  fi
  rm -rf "$FIXTURE"
}
trap cleanup_fixture EXIT
mkdir -p "$FIXTURE/bin"
export NEWMEMO_INSTALL_SOURCE="$FIXTURE/source.app"
export NEWMEMO_INSTALL_DESTINATION="$FIXTURE/Applications/새 메모.app"
export NEWMEMO_INSTALL_LSREGISTER="$FIXTURE/bin/lsregister"
export NEWMEMO_INSTALL_TEST_LOG="$FIXTURE/commands.log"
export PATH="$FIXTURE/bin:$PATH"
cat > "$FIXTURE/bin/codesign" <<'SH'
#!/bin/bash
target="${!#}"
printf 'verify %s\n' "$target" >> "$NEWMEMO_INSTALL_TEST_LOG"
case "${NEWMEMO_INSTALL_TEST_FAILURE:-}" in
  staging) [[ "$target" == "$NEWMEMO_INSTALL_DESTINATION" ]] ;;
  replacement) [[ "$target" != "$NEWMEMO_INSTALL_DESTINATION" ]] ;;
  paused)
    if [[ "$target" != "$NEWMEMO_INSTALL_DESTINATION" ]]; then
      touch "$NEWMEMO_INSTALL_TEST_LOG.ready"
      while [[ ! -e "$NEWMEMO_INSTALL_TEST_LOG.release" ]]; do sleep 0.01; done
    fi
    ;;
  *) exit 0 ;;
esac
SH
cat > "$FIXTURE/bin/mv" <<'SH'
#!/bin/bash
/bin/mv "$@" || exit $?
case "${NEWMEMO_INSTALL_TEST_FAILURE:-}" in
  signal-backup|foreign-destination)
    if [[ "${!#}" == */previous.app ]]; then
      if [[ "$NEWMEMO_INSTALL_TEST_FAILURE" == foreign-destination ]]; then
        mkdir "$NEWMEMO_INSTALL_DESTINATION"
        touch "$NEWMEMO_INSTALL_DESTINATION/foreign.txt"
      fi
      kill -TERM "$PPID"
    fi
    ;;
  signal-replacement)
    if [[ "$1" == */.newmemo-install.*/새\ 메모.app && "${!#}" == "$NEWMEMO_INSTALL_DESTINATION" ]]; then
      kill -TERM "$PPID"
    fi
    ;;
esac
SH
cat > "$FIXTURE/bin/lsregister" <<'SH'
#!/bin/bash
printf 'register %s %s\n' "$1" "$2" >> "$NEWMEMO_INSTALL_TEST_LOG"
if [[ "${NEWMEMO_INSTALL_TEST_FAILURE:-}" == registration && "$1" == -f && -f "$2/new.txt" ]]; then
  exit 1
fi
SH
cat > "$FIXTURE/bin/pgrep" <<'SH'
#!/bin/bash
[[ "${NEWMEMO_INSTALL_TEST_FAILURE:-}" == running ]]
SH
cat > "$FIXTURE/bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill\n' >> "$NEWMEMO_INSTALL_TEST_LOG"
SH
cat > "$FIXTURE/bin/open" <<'SH'
#!/bin/bash
printf 'open\n' >> "$NEWMEMO_INSTALL_TEST_LOG"
SH
chmod +x "$FIXTURE/bin/"*

reset_fixture() {
  rm -rf "$NEWMEMO_INSTALL_SOURCE" "$FIXTURE/Applications"
  mkdir -p "$NEWMEMO_INSTALL_SOURCE" "$NEWMEMO_INSTALL_DESTINATION"
  printf 'new\n' > "$NEWMEMO_INSTALL_SOURCE/new.txt"
  printf 'old\n' > "$NEWMEMO_INSTALL_DESTINATION/old.txt"
  printf 'unrelated\n' > "$FIXTURE/Applications/unrelated.txt"
  : > "$NEWMEMO_INSTALL_TEST_LOG"
  rm -f "$NEWMEMO_INSTALL_TEST_LOG.ready" "$NEWMEMO_INSTALL_TEST_LOG.release"
  export NEWMEMO_INSTALL_TEST_FAILURE="${1:-}"
}
check_old() {
  [[ -f "$NEWMEMO_INSTALL_DESTINATION/old.txt" && ! -e "$NEWMEMO_INSTALL_DESTINATION/new.txt" ]]
  [[ -f "$FIXTURE/Applications/unrelated.txt" ]]
  [[ -z "$(find "$FIXTURE/Applications" -name '.newmemo-install.*' -print)" ]]
  [[ ! -e "$NEWMEMO_INSTALL_DESTINATION.install-lock" ]]
}
expect_failure() {
  if bash "$INSTALL_SCRIPT" > "$FIXTURE/output.txt" 2>&1; then
    cat "$FIXTURE/output.txt"
    echo "FAIL: $NEWMEMO_INSTALL_TEST_FAILURE 오류가 성공으로 처리됨" >&2
    exit 1
  fi
}

reset_fixture
bash "$INSTALL_SCRIPT" > "$FIXTURE/output.txt" 2>&1
[[ -f "$NEWMEMO_INSTALL_DESTINATION/new.txt" && ! -e "$NEWMEMO_INSTALL_DESTINATION/old.txt" ]]
[[ -f "$FIXTURE/Applications/unrelated.txt" ]]
echo 'PASS: 기존 전용 파일을 남기지 않고 번들 교체'

reset_fixture staging
expect_failure
check_old
if grep -Eq '^register|^pkill|^open' "$NEWMEMO_INSTALL_TEST_LOG"; then
  echo 'FAIL: staging 검증 실패 뒤 기존 앱 등록 또는 프로세스를 변경함' >&2
  exit 1
fi
echo 'PASS: staging 검증 실패는 기존 번들과 등록 보존'

reset_fixture replacement
expect_failure
check_old
grep -Eq '^register -f ' "$NEWMEMO_INSTALL_TEST_LOG"
echo 'PASS: 교체 후 검증 실패는 이전 번들과 등록 복원'

reset_fixture registration
expect_failure
check_old
echo 'PASS: 등록 실패는 이전 번들 복원'

reset_fixture running
expect_failure
check_old
[[ ! -s "$NEWMEMO_INSTALL_TEST_LOG" ]]
echo 'PASS: 실행 중인 앱은 설치하지 않음'

reset_fixture
rm -rf "$NEWMEMO_INSTALL_DESTINATION"
bash "$INSTALL_SCRIPT" > "$FIXTURE/output.txt" 2>&1
[[ -f "$NEWMEMO_INSTALL_DESTINATION/new.txt" ]]
echo 'PASS: 최초 설치'

for failure in signal-backup signal-replacement; do
  reset_fixture "$failure"
  expect_failure
  check_old
  echo "PASS: $failure 직후 시그널에도 이전 앱 복원"
done

reset_fixture foreign-destination
expect_failure
[[ -f "$NEWMEMO_INSTALL_DESTINATION/foreign.txt" ]]
[[ ! -e "$NEWMEMO_INSTALL_DESTINATION/previous.app" ]]
[[ -n "$(find "$FIXTURE/Applications" -path '*/previous.app/old.txt' -print)" ]]
[[ ! -e "$NEWMEMO_INSTALL_DESTINATION.install-lock" ]]
echo 'PASS: 복구 대상 충돌 시 중첩 이동 없이 백업 보존'

reset_fixture paused
bash "$INSTALL_SCRIPT" > "$FIXTURE/first-install-output.txt" 2>&1 &
ACTIVE_INSTALL_PID=$!
for ((attempt=0; attempt<100; attempt++)); do
  if [[ -e "$NEWMEMO_INSTALL_TEST_LOG.ready" ]]; then break; fi
  sleep 0.05
done
[[ -e "$NEWMEMO_INSTALL_TEST_LOG.ready" ]]
export NEWMEMO_INSTALL_TEST_FAILURE=""
expect_failure
[[ -f "$NEWMEMO_INSTALL_DESTINATION/old.txt" && ! -e "$NEWMEMO_INSTALL_DESTINATION/new.txt" ]]
touch "$NEWMEMO_INSTALL_TEST_LOG.release"
wait "$ACTIVE_INSTALL_PID"
ACTIVE_INSTALL_PID=""
[[ -f "$NEWMEMO_INSTALL_DESTINATION/new.txt" && ! -e "$NEWMEMO_INSTALL_DESTINATION/old.txt" ]]
[[ ! -e "$NEWMEMO_INSTALL_DESTINATION.install-lock" ]]
echo 'PASS: 동시 설치는 하나만 진행하고 다른 요청은 안전하게 거부'
echo 'PASS: 10 install scenarios'
