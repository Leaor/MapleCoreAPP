#!/usr/bin/env bash
# Parses every Swift file in the app, widget, shared and test folders.
# Linux has no SwiftUI SDK, so this catches syntax errors only; type-checking needs Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
while IFS= read -r -d '' f; do
  if ! out=$(swiftc -frontend -parse "$f" 2>&1); then
    echo "$out"; status=1
  fi
done < <(find MapleCore MapleCoreWidgets Shared MapleCoreTests MapleCoreUITests -name '*.swift' -print0)
[ $status -eq 0 ] && echo "Syntax OK: $(find MapleCore MapleCoreWidgets Shared MapleCoreTests MapleCoreUITests -name '*.swift' | wc -l) files"
exit $status
