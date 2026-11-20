#!/bin/bash
# Smoke test for a macOS installer image built by `./gradlew dmg`.
# Usage: scripts/test-dmg.sh build/distributions/dotify-studio-<version>-macos-<arch>.dmg
#
# Checks that the image is compressed, that the launcher and the bundled Java runtime have the
# same architecture, and that the app starts and gets as far as loading its plugins.
# An Intel image can be tested on Apple Silicon if Rosetta is installed.
set -euo pipefail

dmg="$1"
timeout="${SMOKE_TEST_TIMEOUT:-90}"
work="$(mktemp -d)"
mnt="$work/mnt"
log="$work/app.log"
pid=""

cleanup() {
	if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
	hdiutil detach "$mnt" -quiet 2>/dev/null || hdiutil detach "$mnt" -force -quiet 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "== $dmg"
format="$(hdiutil imageinfo "$dmg" | awk '/^Format:/ {print $2}')"
[ "$format" = "UDZO" ] || fail "image format is $format, expected UDZO (compressed)"

mkdir -p "$mnt"
hdiutil attach "$dmg" -nobrowse -readonly -noautoopen -mountpoint "$mnt" >/dev/null
app="$(find "$mnt" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$app" ] || fail "no .app in image"
[ -L "$mnt/Applications" ] || fail "no Applications shortcut in image"

launcher="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
runtime="$(/usr/libexec/PlistBuddy -c 'Print :JVMRuntime' "$app/Contents/Info.plist")"
java="$app/Contents/PlugIns/$runtime/Contents/Home/bin/java"
[ -x "$java" ] || fail "bundled runtime not found at $java"

launcher_archs="$(lipo -archs "$launcher")"
java_arch="$(lipo -archs "$java")"
echo "launcher: $launcher_archs, runtime: $java_arch ($runtime)"
[ "$launcher_archs" = "$java_arch" ] || fail "launcher ($launcher_archs) does not match runtime ($java_arch)"

runtimes="$(ls "$app/Contents/PlugIns" | wc -l | tr -d ' ')"
[ "$runtimes" = "1" ] || fail "expected one bundled runtime, found $runtimes"

"$java" -version 2>&1 | head -1

# Signing. Set REQUIRE_NOTARIZED=1 to require an image that macOS opens after it has been downloaded.
if codesign --verify --deep --strict "$app" 2>/dev/null; then
	signer="$(codesign -dv --verbose=2 "$app" 2>&1 | awk -F= '/^Authority=/ {print $2; exit}')"
	flags="$(codesign -dv "$app" 2>&1 | sed -n 's/.*flags=\(0x[0-9a-f]*\)(\([^)]*\)).*/\2/p')"
	echo "signed: ${signer:-ad hoc} ($flags)"
	case "$flags" in *runtime*) ;; *) fail "app is signed without the hardened runtime";; esac
else
	echo "signed: no"
fi
if [ "${REQUIRE_NOTARIZED:-0}" = "1" ]; then
	spctl --assess --type open --context context:primary-signature -v "$dmg" || fail "Gatekeeper rejects the image"
	xcrun stapler validate "$dmg" || fail "no notarization ticket stapled to the image"
	spctl --assess --type execute -v "$app" || fail "Gatekeeper rejects the app"
fi

"$launcher" >"$log" 2>&1 &
pid=$!
for _ in $(seq 1 "$timeout"); do
	if grep -q "Found jars" "$log"; then break; fi
	kill -0 "$pid" 2>/dev/null || { cat "$log"; fail "app exited during startup"; }
	sleep 1
done
grep -q "Found jars" "$log" || { cat "$log"; fail "app did not finish starting within ${timeout}s"; }
sleep 3
kill -0 "$pid" 2>/dev/null || { cat "$log"; fail "app exited after startup"; }
if grep -qE "Exception|Error" "$log"; then cat "$log"; fail "errors in app output"; fi
echo "PASS: app started ($(grep -c 'Found jars' "$log") plugin jar(s) loaded)"
