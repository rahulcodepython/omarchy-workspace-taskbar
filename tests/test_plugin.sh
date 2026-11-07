#!/usr/bin/env bash
set -u -o pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$PLUGIN_DIR/manifest.json"

PASSED=0
FAILED=0
TOTAL=0

report() {
  local status="$1"
  local test_name="$2"
  local details="${3:-}"
  ((TOTAL++))
  if [[ "$status" == "PASS" ]]; then
    ((PASSED++))
    printf "  \033[32m✔ PASS\033[0m: %s\n" "$test_name"
  else
    ((FAILED++))
    printf "  \033[31m✖ FAIL\033[0m: %s\n" "$test_name"
    if [[ -n "$details" ]]; then
      printf "         \033[33mReason: %s\033[0m\n" "$details"
    fi
  fi
}

echo "================================================================="
echo "       OMARCHY PLUGIN AUTOMATED TEST SUITE & VERIFICATION        "
echo "  Target: $PLUGIN_DIR"
echo "================================================================="

echo ""
echo "[Group 1: Manifest Schema & Data Integrity]"

# Test 1.1: manifest.json existence and JSON syntax
if [[ -f "$MANIFEST" ]] && jq -e . "$MANIFEST" >/dev/null 2>&1; then
  report "PASS" "TC-101: manifest.json is present and valid JSON"
else
  report "FAIL" "TC-101: manifest.json is present and valid JSON" "File missing or invalid JSON"
fi

# Test 1.2: schemaVersion is numeric 1
if jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1; then
  report "PASS" "TC-102: schemaVersion is exactly numeric 1"
else
  report "FAIL" "TC-102: schemaVersion is exactly numeric 1" "schemaVersion must be numeric 1"
fi

# Test 1.3: Required top-level keys
missing_keys=()
for k in id name version kinds entryPoints; do
  if ! jq -e --arg k "$k" 'has($k)' "$MANIFEST" >/dev/null 2>&1; then
    missing_keys+=("$k")
  fi
done
if [[ ${#missing_keys[@]} -eq 0 ]]; then
  report "PASS" "TC-103: All required top-level fields exist (id, name, version, kinds, entryPoints)"
else
  report "FAIL" "TC-103: All required top-level fields exist" "Missing fields: ${missing_keys[*]}"
fi

# Test 1.4: ID namespace validation
ID=$(jq -r '.id // ""' "$MANIFEST")
if [[ "$ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$ID" != *".."* ]] && [[ "$ID" != omarchy.* ]]; then
  report "PASS" "TC-104: Plugin ID format is namespaced and avoids reserved namespaces ('$ID')"
else
  report "FAIL" "TC-104: Plugin ID format is namespaced" "ID '$ID' violates namespace or naming rules"
fi

# Test 1.5: kinds non-empty array
if jq -e '(.kinds | type == "array") and (.kinds | length > 0) and (.kinds | index("bar-widget") != null)' "$MANIFEST" >/dev/null 2>&1; then
  report "PASS" "TC-105: 'kinds' is non-empty array declaring 'bar-widget'"
else
  report "FAIL" "TC-105: 'kinds' is non-empty array declaring 'bar-widget'" "Invalid kinds declaration"
fi

# Test 1.6: barWidget defaultSection validation
if jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $sec
    | ($sec | type) == "string" and (["left", "centerBegin", "center", "centerEnd", "tray", "right"] | index($sec)) != null
  else
    true
  end
' "$MANIFEST" >/dev/null 2>&1; then
  SECTION=$(jq -r '.barWidget.defaultSection // "none"' "$MANIFEST")
  report "PASS" "TC-106: barWidget.defaultSection is valid ('$SECTION')"
else
  report "FAIL" "TC-106: barWidget.defaultSection is valid" "Invalid section name"
fi

echo ""
echo "[Group 2: Security & Filesystem Invariants]"

# Test 2.1: Zero symlinks
symlinks=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print 2>/dev/null || true)
if [[ -z "$symlinks" ]]; then
  report "PASS" "TC-201: Zero symlinks in repository (anti-privilege-escalation)"
else
  report "FAIL" "TC-201: Zero symlinks in repository" "Found symlinks: $symlinks"
fi

# Test 2.2: Entry point path safety
SAFE_EP=1
while IFS= read -r ep_json; do
  [[ -n "$ep_json" ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  if [[ -z "$ep" || "$ep" == /* || "$ep" == *".."* || ! -f "$PLUGIN_DIR/$ep" ]]; then
    SAFE_EP=0
    break
  fi
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")
if [[ "$SAFE_EP" -eq 1 ]]; then
  report "PASS" "TC-202: All entry points are safe relative paths pointing to existing files"
else
  report "FAIL" "TC-202: All entry points are safe relative paths" "Unsafe or missing entry point file"
fi

# Test 2.3: Text.PlainText security rule check
if grep -q "textFormat: Text.PlainText" "$PLUGIN_DIR/WorkspaceTaskbar.qml"; then
  report "PASS" "TC-203: UI labels use explicit Text.PlainText (protects against rich-text injection)"
else
  report "FAIL" "TC-203: UI labels use explicit Text.PlainText" "Missing Text.PlainText format on dynamic labels"
fi

echo ""
echo "[Group 3: Official Omarchy Engine Validation]"

# Test 3.1: omarchy plugin validate CLI execution
if omarchy plugin validate "$PLUGIN_DIR" >/dev/null 2>&1; then
  report "PASS" "TC-301: Passed official 'omarchy plugin validate' CLI check (exit 0)"
else
  report "FAIL" "TC-301: Passed official 'omarchy plugin validate' CLI check" "CLI validator failed"
fi

echo ""
echo "[Group 4: QML Contract & Component Verification]"

# Test 4.1: moduleName in QML matches manifest.json id
QML_MODULE=$(grep -oP 'moduleName:\s*"\K[^"]+' "$PLUGIN_DIR/WorkspaceTaskbar.qml" || true)
if [[ "$QML_MODULE" == "$ID" ]]; then
  report "PASS" "TC-401: QML moduleName ('$QML_MODULE') strictly matches manifest ID ('$ID')"
else
  report "FAIL" "TC-401: QML moduleName strictly matches manifest ID" "Mismatch: QML=$QML_MODULE vs ID=$ID"
fi

# Test 4.2: Required Omarchy and Quickshell imports
QML_FILE="$PLUGIN_DIR/WorkspaceTaskbar.qml"
missing_imports=()
for imp in "QtQuick" "Quickshell" "Quickshell.Hyprland" "qs.Commons" "qs.Ui"; do
  if ! grep -q "import $imp" "$QML_FILE"; then
    missing_imports+=("$imp")
  fi
done
if [[ ${#missing_imports[@]} -eq 0 ]]; then
  report "PASS" "TC-402: All required Quickshell and Omarchy module imports are present"
else
  report "FAIL" "TC-402: All required imports are present" "Missing: ${missing_imports[*]}"
fi

# Test 4.3: Hyprland focus dispatch implementation
if grep -q "hl.dsp.focus" "$QML_FILE" && grep -q 'hl.dsp.layout("center")' "$QML_FILE"; then
  report "PASS" "TC-403: Dispatcher supports window focus and scrolling layout centering"
else
  report "FAIL" "TC-403: Dispatcher supports window focus and scrolling layout centering" "Missing dispatch calls"
fi

echo ""
echo "[Group 5: Repository Assets & Release Readiness]"

# Test 5.1: preview.png existence and image format
if [[ -f "$PLUGIN_DIR/preview.png" ]]; then
  DIMS=$(identify -format "%wx%h" "$PLUGIN_DIR/preview.png" 2>/dev/null || true)
  if [[ -n "$DIMS" ]]; then
    report "PASS" "TC-501: preview.png is valid image asset (dimensions: $DIMS)"
  else
    report "FAIL" "TC-501: preview.png is valid image asset" "Could not parse image dimensions"
  fi
else
  report "FAIL" "TC-501: preview.png is valid image asset" "preview.png missing"
fi

# Test 5.2: Documentation and License
if [[ -f "$PLUGIN_DIR/README.md" ]] && [[ -f "$PLUGIN_DIR/LICENSE" ]] && [[ -f "$PLUGIN_DIR/PUBLISHING.md" ]]; then
  report "PASS" "TC-502: Documentation files complete (README.md, LICENSE, PUBLISHING.md)"
else
  report "FAIL" "TC-502: Documentation files complete" "One or more documentation files missing"
fi

# Test 5.3: Git repository cleanliness
cd "$PLUGIN_DIR"
UNCOMMITTED=$(git status --porcelain | grep -v "tests/" || true)
if [[ -z "$UNCOMMITTED" ]]; then
  report "PASS" "TC-503: Git working directory clean (no uncommitted tracked/untracked changes)"
else
  report "FAIL" "TC-503: Git working directory clean" "Uncommitted changes: $UNCOMMITTED"
fi

# Test 5.4: Git release tag exists
TAG=$(git tag -l "v1.0.0")
if [[ "$TAG" == "v1.0.0" ]]; then
  report "PASS" "TC-504: Git release tag 'v1.0.0' is created"
else
  report "FAIL" "TC-504: Git release tag 'v1.0.0' is created" "Tag missing"
fi

echo ""
echo "================================================================="
echo "                          SUMMARY REPORT                         "
echo "================================================================="
echo "Total Tests Executed: $TOTAL"
printf "Passed: \033[32m%d\033[0m\n" "$PASSED"
printf "Failed: \033[31m%d\033[0m\n" "$FAILED"
echo "================================================================="

if [[ "$FAILED" -eq 0 ]]; then
  echo "OVERALL VERDICT: ALL TESTS PASSED (100% SUCCESS)"
  exit 0
else
  echo "OVERALL VERDICT: FAILED (Review error logs above)"
  exit 1
fi
