#!/usr/bin/env bash
# Builds build/Piccolo.app with xcodebuild. A Debug build also builds the acceptance
# fixture, build/PiccoloFixture.app; a Release build never does.
#
# Usage: scripts/build.sh [debug|release]   (default: debug)
#
# Signing comes from the signing env file (see scripts/common.sh); without one the
# apps are signed ad-hoc. All intermediate products live under build/.
#
# PICCOLO_NOTARIZABLE=1 (set by scripts/release.sh) makes a signed Release build
# acceptable to the notary service: no get-task-allow entitlement and a secure
# timestamp. It needs network access and does not affect Debug or ad-hoc builds.

set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
    echo "Usage: scripts/build.sh [debug|release]" >&2
}

if [[ $# -gt 1 ]]; then
    usage
    exit 2
fi

case "${1:-debug}" in
    debug) CONFIGURATION="Debug" ;;
    release) CONFIGURATION="Release" ;;
    *)
        usage
        exit 2
        ;;
esac

load_signing_env

if [[ -n "$SIGN_IDENTITY" ]]; then
    # CODE_SIGN_STYLE=Manual applies to the package's resource bundle targets too (PiccoloUI has
    # resources, so Xcode builds a bundle target for it): left automatic, they refuse the identity.
    signing_overrides=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=$SIGN_IDENTITY" "DEVELOPMENT_TEAM=$SIGN_TEAM")
    log "Signing with the configured identity"
    if [[ "$CONFIGURATION" == "Release" && "${PICCOLO_NOTARIZABLE:-}" == "1" ]]; then
        signing_overrides+=("CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO" "OTHER_CODE_SIGN_FLAGS=--timestamp")
        log "Release signing for notarization: no get-task-allow, secure timestamp"
    fi
else
    signing_overrides=("CODE_SIGN_STYLE=Manual" "CODE_SIGN_IDENTITY=-" "DEVELOPMENT_TEAM=")
    log "No signing identity configured: building ad-hoc signed"
fi

derived_data="$BUILD_DIR/DerivedData"
mkdir -p "$BUILD_DIR"

# build_app <scheme> <log file name>: builds the scheme's app (the app is named like
# the scheme) and copies it to build/<scheme>.app.
build_app() {
    local scheme="$1" log_file="$BUILD_DIR/$2" product
    log "Building $scheme ($CONFIGURATION, full log: ${log_file#"$PICCOLO_ROOT"/})"
    if ! xcodebuild \
        -project "$PICCOLO_ROOT/Piccolo.xcodeproj" \
        -scheme "$scheme" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$derived_data" \
        "${signing_overrides[@]}" \
        build >"$log_file" 2>&1; then
        tail -n 40 "$log_file" >&2
        die "xcodebuild failed (full log: $log_file)"
    fi

    product="$derived_data/Build/Products/$CONFIGURATION/$scheme.app"
    [[ -d "$product" ]] || die "build succeeded but '$product' does not exist"

    # ditto keeps the bundle byte-identical, so the code signature stays valid.
    rm -rf "${BUILD_DIR:?}/$scheme.app"
    ditto "$product" "$BUILD_DIR/$scheme.app"

    codesign --verify --strict --deep "$BUILD_DIR/$scheme.app"
    log "Built ${BUILD_DIR#"$PICCOLO_ROOT"/}/$scheme.app ($CONFIGURATION)"
}

build_app "$APP_NAME" "xcodebuild-$CONFIGURATION.log"

# The fixture is a test support app: Debug only, never built for or shipped in a release.
if [[ "$CONFIGURATION" == "Debug" ]]; then
    build_app "$FIXTURE_NAME" "xcodebuild-$FIXTURE_NAME-$CONFIGURATION.log"
fi
