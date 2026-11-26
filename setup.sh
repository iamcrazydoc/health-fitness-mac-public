#!/bin/bash
# Builds "Health and Fitness" and installs it in ~/Applications.
# Run from this folder:  ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "1/5  Checking Xcode"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode isn't installed (or the command line tools point elsewhere)."
  echo "Install Xcode from the App Store, open it once, then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
xcodebuild -version | head -1

say "2/5  Getting XcodeGen"
XCODEGEN="$(command -v xcodegen || true)"
if [ -z "$XCODEGEN" ]; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
    XCODEGEN="$(command -v xcodegen)"
  else
    mkdir -p .tools
    curl -fsSL -o .tools/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.42.0/xcodegen.zip
    (cd .tools && unzip -oq xcodegen.zip)
    XCODEGEN="$PWD/.tools/xcodegen/bin/xcodegen"
  fi
fi
"$XCODEGEN" --version

say "3/5  Finding your Apple developer team"
if [ -z "${TEAM_ID:-}" ]; then
  TEAM_ID="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
fi
if [ -z "${TEAM_ID:-}" ]; then
  echo "No Apple Development certificate found."
  echo "Open Xcode > Settings > Accounts, add your Apple ID, select it, click"
  echo "'Manage Certificates…' and add an 'Apple Development' certificate. Then run this again."
  exit 1
fi
echo "Team: $TEAM_ID"
export TEAM_ID

say "4/5  Building"
"$XCODEGEN" generate --quiet
xcodebuild -project HealthFitness.xcodeproj -scheme HealthFitness -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" build \
  | grep -E "error:|warning: .*(sign|provision)|BUILD (SUCCEEDED|FAILED)" || true
APP="build/Build/Products/Release/Health and Fitness.app"
[ -d "$APP" ] || { echo "Build failed. Run again without the filter to see everything:"; echo "  xcodebuild -project HealthFitness.xcodeproj -scheme HealthFitness -configuration Release -derivedDataPath build -allowProvisioningUpdates build"; exit 1; }

say "5/5  Installing"
mkdir -p "$HOME/Applications"
pkill -x "Health and Fitness" 2>/dev/null || true
rm -rf "$HOME/Applications/Health and Fitness.app"
cp -R "$APP" "$HOME/Applications/"
open "$HOME/Applications/Health and Fitness.app"
echo "Installed to ~/Applications/Health and Fitness.app and opened it."
echo "Next: open Settings (⌘,) to connect Strava and athletedata, then add widgets"
echo "by right-clicking the desktop > Edit Widgets > search 'Health and Fitness'."
