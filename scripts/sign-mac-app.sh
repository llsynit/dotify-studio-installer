#!/bin/bash
# Signs a macOS app bundle for distribution, so that it can be notarized.
# Usage: scripts/sign-mac-app.sh "path/to/Dotify Studio.app" "<identity>"
#
# <identity> is a "Developer ID Application: ..." certificate in the keychain, or "-" to sign
# ad hoc (only useful for testing that the signed app still runs; it can't be notarized).
#
# Everything is signed with the hardened runtime, from the inside out: native libraries inside
# jars, every binary in the app, the bundled Java runtime, and finally the app itself.
set -euo pipefail

app="$1"
identity="$2"
entitlements="$(cd "$(dirname "$0")/.." && pwd)/build-resources/macos-entitlements.plist"

options=(--force --options runtime --sign "$identity")
if [ "$identity" != "-" ]; then
	options+=(--timestamp)
fi

sign() { codesign "${options[@]}" "$@"; }
is_macho() { file -b "$1" | grep -q 'Mach-O'; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 1. Native libraries inside jars. Notarization rejects unsigned binaries even when they're in a jar.
find "$app" -name '*.jar' -print0 | while IFS= read -r -d '' jar; do
	entries=()
	while IFS= read -r entry; do entries+=("$entry"); done < <(zipinfo -1 "$jar" | grep -E '\.(dylib|jnilib)$' || true)
	[ ${#entries[@]} -gt 0 ] || continue
	rm -rf "$work/jar" && mkdir "$work/jar"
	unzip -q "$jar" "${entries[@]}" -d "$work/jar"
	signed=()
	for entry in "${entries[@]}"; do
		if is_macho "$work/jar/$entry"; then
			sign "$work/jar/$entry"
			signed+=("$entry")
		fi
	done
	if [ ${#signed[@]} -gt 0 ]; then
		(cd "$work/jar" && zip -q "$jar" "${signed[@]}")
		echo "Signed ${#signed[@]} native librar(y/ies) in $(basename "$jar")"
	fi
done

# 2. Every binary in the app except the main launcher, which is signed with the bundle in step 4.
launcher="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
count=0
while IFS= read -r -d '' f; do
	[ "$f" = "$launcher" ] && continue
	if is_macho "$f"; then
		sign --entitlements "$entitlements" "$f"
		count=$((count + 1))
	fi
done < <(find "$app/Contents" -type f -print0)
echo "Signed $count binaries"

# 3. The bundled Java runtime, which is a bundle of its own.
for runtime in "$app"/Contents/PlugIns/*; do
	sign "$runtime"
done

# 4. The app.
sign --entitlements "$entitlements" "$app"

codesign --verify --deep --strict "$app"
echo "Signed and verified $app"
