#!/bin/bash
# build-ipa.sh — build AirCard-iOS and package an IPA.
#
#   ./build-ipa.sh                 # unsigned .ipa (for inspection only)
#   ./build-ipa.sh --sign          # signed .ipa using your Apple ID (installable)
#   ./build-ipa.sh --sign "Team ID" # signed with a specific team
#
# An UNSIGNED .ipa will NOT install on an iPhone. iOS refuses apps without a
# valid signature. Use --sign to get something you can actually sideload.
#
# Requires: macOS, Xcode, `xcodegen`, and (for signing) an Apple ID in Xcode.
set -euo pipefail

CONFIG="Release"
MODE="unsigned"
TEAM_ID="${DEVELOPMENT_TEAM:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --sign)
            MODE="signed"
            # Optional next arg is the team id.
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                TEAM_ID="$2"
                shift
            fi
            ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) CONFIG="$1" ;;
    esac
    shift
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Preflight: fail loudly and early rather than deep inside xcodebuild.
# ---------------------------------------------------------------------------
for tool in xcodebuild xcodegen; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: '$tool' not found."
        [ "$tool" = "xcodegen" ] && echo "       Install it with: brew install xcodegen"
        exit 1
    fi
done

if [ ! -d "$ROOT/AirliftFFI.xcframework" ]; then
    echo "Error: AirliftFFI.xcframework is missing."
    echo "       Build it first with: ./build-ios.sh"
    exit 1
fi

echo "==> Generating Xcode project from project.yml"
xcodegen generate

echo "==> Building AirCard-iOS ($CONFIG) for device arm64..."
rm -rf build/DerivedData build/Payload
mkdir -p build

XCODEBUILD_ARGS=(
    -project AirCard-iOS.xcodeproj
    -scheme AirCard-iOS
    -configuration "$CONFIG"
    -derivedDataPath build/DerivedData
    -destination 'generic/platform=iOS'
    clean build
)

if [ "$MODE" = "signed" ]; then
    echo "==> Signing with your Apple ID"
    # Xcode resolves the certificate and provisioning profile for us.
    XCODEBUILD_ARGS+=(CODE_SIGN_STYLE=Automatic)
    if [ -n "$TEAM_ID" ]; then
        XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi
else
    echo "==> Building UNSIGNED (this IPA cannot be installed on a device)"
    XCODEBUILD_ARGS+=(
        CODE_SIGN_IDENTITY=""
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGN_ENTITLEMENTS=""
    )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"

APP_PATH="$(find build/DerivedData/Build/Products -name "AirCard-iOS.app" -type d | head -n 1)"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: AirCard-iOS.app not found in DerivedData. Read the xcodebuild errors above."
    exit 1
fi

echo "==> Packaging IPA..."
rm -rf build/AirCard-iOS.app build/Payload
cp -R "$APP_PATH" build/AirCard-iOS.app

if [ "$MODE" = "unsigned" ]; then
    # Strip any signature so the archive is self-consistent.
    rm -rf build/AirCard-iOS.app/_CodeSignature
    rm -f build/AirCard-iOS.app/embedded.mobileprovision
fi

mkdir -p build/Payload
cp -R build/AirCard-iOS.app build/Payload/AirCard-iOS.app
cd build
rm -f "AirCard-iOS.ipa"
zip -qr "AirCard-iOS.ipa" Payload
rm -rf Payload AirCard-iOS.app
cd "$ROOT"

echo
echo "==> Done: build/AirCard-iOS.ipa"
ls -lh "build/AirCard-iOS.ipa"
if [ "$MODE" = "unsigned" ]; then
    cat <<'EOF'

NOTE: this IPA is UNSIGNED and iOS will refuse to install it.
      Re-run with:  ./build-ipa.sh --sign
      Then install with a sideloading tool (e.g. AltStore, Sideloadly, or
      Apple Configurator 2), or install it yourself from Xcode by selecting
      your device and pressing Run.
EOF
fi