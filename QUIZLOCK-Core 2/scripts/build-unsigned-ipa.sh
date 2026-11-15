#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/QUIZLOCK.xcodeproj"
SCHEME="QUIZLOCK"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
PACKAGE_DIR="$ROOT_DIR/build/UnsignedIPA"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/QUIZLOCK.app"
DIST_DIR="$ROOT_DIR/dist"
IPA_PATH="$DIST_DIR/QUIZLOCK-unsigned.ipa"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This script must run on macOS with Xcode installed. Linux cannot build an iOS app because it does not include Apple's iOS SDK or xcodebuild."
fi

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is missing. Install Xcode and select it with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen is missing. Install it with: brew install xcodegen"
command -v zip >/dev/null 2>&1 || fail "zip is missing."

cd "$ROOT_DIR"

printf '\n[1/5] Generating Xcode project...\n'
xcodegen generate --spec "$ROOT_DIR/project.yml"
[[ -d "$PROJECT_FILE" ]] || fail "XcodeGen did not create $PROJECT_FILE"

printf '\n[2/5] Resolving Swift Package dependencies...\n'
xcodebuild \
  -resolvePackageDependencies \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME"

printf '\n[3/5] Building for physical iOS devices with code signing disabled...\n'
rm -rf "$DERIVED_DATA"
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY='' \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM='' \
  PROVISIONING_PROFILE_SPECIFIER='' \
  clean build

[[ -d "$APP_PATH" ]] || fail "Build completed but the expected app bundle was not found: $APP_PATH"
[[ -f "$APP_PATH/Info.plist" ]] || fail "The built app bundle has no Info.plist."

printf '\n[4/5] Preparing unsigned Payload bundle...\n'
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/Payload" "$DIST_DIR"
/usr/bin/ditto "$APP_PATH" "$PACKAGE_DIR/Payload/QUIZLOCK.app"

# Remove any code-signature/provisioning remnants so the output is explicitly unsigned.
find "$PACKAGE_DIR/Payload" -type d -name '_CodeSignature' -prune -exec rm -rf {} +
find "$PACKAGE_DIR/Payload" -type f \( -name 'embedded.mobileprovision' -o -name 'CodeResources' \) -delete

if find "$PACKAGE_DIR/Payload" -type d -name '_CodeSignature' -print -quit | grep -q .; then
  fail "A code-signature directory remains in the package; refusing to label it unsigned."
fi
if find "$PACKAGE_DIR/Payload" -type f -name 'embedded.mobileprovision' -print -quit | grep -q .; then
  fail "A provisioning profile remains in the package; refusing to label it unsigned."
fi

printf '\n[5/5] Creating IPA archive...\n'
rm -f "$IPA_PATH"
(
  cd "$PACKAGE_DIR"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)

/usr/bin/unzip -Z1 "$IPA_PATH" | grep -Fxq 'Payload/QUIZLOCK.app/Info.plist' || fail "IPA archive verification failed: Info.plist is missing."
/usr/bin/unzip -Z1 "$IPA_PATH" | grep -Eq '^Payload/QUIZLOCK.app/PlugIns/QUIZLOCKMonitor\.appex/Info\.plist$' || fail "IPA archive verification failed: the Screen Time monitor extension is missing."

printf '\nSUCCESS: %s\n' "$IPA_PATH"
printf 'This IPA is intentionally unsigned. It cannot be installed on a standard iPhone until a signing tool signs it locally.\n'
printf 'Family Controls also requires the relevant Apple entitlement in the resulting signed app and extension.\n'
