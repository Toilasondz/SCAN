#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${THEOS:-}" || ! -f "$THEOS/makefiles/common.mk" ]]; then
  echo "ERROR: THEOS is not configured. Set THEOS to your Theos installation path." >&2
  exit 1
fi

make clean
make

mkdir -p dist
candidate=""
while IFS= read -r file; do
  candidate="$file"
  break
done < <(find .theos/obj -type f \( -name 'HSONScanner.dylib' -o -name 'libHSONScanner.dylib' \) 2>/dev/null | sort)

if [[ -z "$candidate" ]]; then
  echo "ERROR: build completed but HSONScanner.dylib was not found under .theos/obj." >&2
  exit 2
fi

cp "$candidate" dist/HSONScanner.dylib
echo "Built: $(pwd)/dist/HSONScanner.dylib"
file dist/HSONScanner.dylib
