#!/data/data/com.termux/files/usr/bin/bash
set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SKILL_DIR:-$SCRIPT_DIR/..}"
LAST_UPDATE_FILE="$SKILL_DIR/last_update.timestamp"

COOLDOWN_SECONDS=604800

if [ -f "$LAST_UPDATE_FILE" ]; then
    LAST_UPDATE=$(<"$LAST_UPDATE_FILE")
    NOW=$(date +%s)
    if [[ "$LAST_UPDATE" =~ ^[0-9]+$ ]] && [ "$NOW" -ge "$LAST_UPDATE" ]; then
        DIFF=$((NOW - LAST_UPDATE))
        if [ "$DIFF" -lt "$COOLDOWN_SECONDS" ]; then
            echo "UPDATE_SKIPPED"
            exit 0
        fi
    fi
fi

mkdir -p "$SKILL_DIR"

LOG_FILE="/tmp/auto_update_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Termux Update Preflight: $(date) ==="

# Этот скилл рассчитан на Termux/Android. Не пытаться выполнять его как
# обычный Linux-скрипт: там могут отличаться libc, shebang и пакетный менеджер.
if [ -z "${PREFIX:-}" ] || [ ! -x "$PREFIX/bin/pkg" ] || [ ! -x "$PREFIX/bin/apt-get" ]; then
    echo "ERROR: Termux environment was not detected."
    echo "UPDATE_UNSUPPORTED_ENVIRONMENT"
    exit 2
fi

# Обновление меняет систему, поэтому фоновый запуск без терминала запрещён.
if [ ! -t 0 ]; then
    echo "ERROR: interactive approval is required; refusing unattended update."
    echo "UPDATE_NEEDS_APPROVAL"
    exit 2
fi

echo "Environment: Termux/Android (Bionic host)"
echo "Native Termux packages use pkg/apt. glibc binaries must use glibc-runner."

echo
echo "--- Available updates (local/index checks) ---"
APT_UPGRADABLE="$(apt list --upgradable 2>/dev/null | sed '1d' | head -80)"
if [ -n "$APT_UPGRADABLE" ]; then
    echo "Termux packages:"
    printf '%s\n' "$APT_UPGRADABLE"
else
    echo "Termux packages: no updates reported by the current apt index."
fi

NPM_OUTDATED=""
NPM_PACKAGES=""
if command -v npm >/dev/null 2>&1; then
    NPM_OUTDATED="$(npm outdated -g --json 2>/dev/null || true)"
    NPM_PACKAGES="$(npm ls -g --depth=0 --json 2>/dev/null | node -e '
        let input = "";
        process.stdin.on("data", chunk => input += chunk);
        process.stdin.on("end", () => {
            try {
                const deps = JSON.parse(input).dependencies || {};
                for (const name of Object.keys(deps)) {
                    if (name !== "@anthropic-ai/claude-code") console.log(name);
                }
            } catch (_) {
                process.exitCode = 1;
            }
        });
    ' 2>/dev/null)"
    echo "Global NPM packages (Claude Code excluded):"
    if [ -n "$NPM_OUTDATED" ]; then
        printf '%s\n' "$NPM_OUTDATED" | node -e '
            let input = "";
            process.stdin.on("data", chunk => input += chunk);
            process.stdin.on("end", () => {
                try {
                    const data = JSON.parse(input);
                    for (const [name, info] of Object.entries(data)) {
                        if (name !== "@anthropic-ai/claude-code") {
                            console.log(`${name}: ${info.current} -> ${info.latest}`);
                        }
                    }
                } catch (_) {}
            });
        '
    else
        echo "No NPM updates reported."
    fi
else
    echo "Global NPM packages: npm is not installed."
fi

PYTHON_BIN=""
PIP_OUTDATED=""
PIP_PACKAGES=""
for candidate in python python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -m pip --version >/dev/null 2>&1; then
        PYTHON_BIN="$candidate"
        break
    fi
done
if [ -n "$PYTHON_BIN" ]; then
    PIP_OUTDATED="$($PYTHON_BIN -m pip list --outdated --format=json 2>/dev/null || true)"
    PIP_PACKAGES="$(printf '%s' "$PIP_OUTDATED" | "$PYTHON_BIN" -c '
import json, sys
try:
    for item in json.load(sys.stdin):
        print(item["name"])
except Exception:
    pass
')"
    echo "Python/pip packages:"
    if [ -n "$PIP_OUTDATED" ] && [ "$PIP_OUTDATED" != "[]" ]; then
printf '%s\n' "$PIP_OUTDATED" | "$PYTHON_BIN" -c '
import json, sys
try:
    for item in json.load(sys.stdin):
        print("{}: {} -> {}".format(item["name"], item["version"], item["latest_version"]))
except Exception:
    pass
'
    else
        echo "No pip updates reported."
    fi
else
    echo "Python/pip packages: pip is not installed."
fi

UV_TOOLS=""
if command -v uv >/dev/null 2>&1; then
    UV_TOOLS="$(uv tool list 2>/dev/null || true)"
    echo "uv tools:"
    if [ -n "$UV_TOOLS" ]; then
        printf '%s\n' "$UV_TOOLS"
        echo "uv tool update availability will be checked by 'uv tool upgrade --all' after approval."
    else
        echo "No uv tools reported."
    fi
fi

echo "Antigravity CLI: update availability is checked by 'agy update' after approval."

if command -v agy >/dev/null 2>&1; then
    if command -v glibc-runner >/dev/null 2>&1; then
        echo "Termux runtime: glibc-runner is available for glibc binaries."
    else
        echo "WARNING: glibc-runner is unavailable; glibc-based applications may fail."
        echo "Recommendation: install/repair glibc only after explicit approval."
    fi
fi

echo
echo "The update will:"
echo "  1) refresh and upgrade Termux packages;"
echo "  2) check for shadowing wrappers in ~/.local/bin/ (termux-fix-path Module 7);"
echo "  3) update global NPM packages (Claude Code excluded);"
echo "  4) repair Termux shebangs for all global NPM CLI binaries;"
echo "  5) update outdated pip packages and uv tools when detected;"
echo "  6) let agy check and ask before applying its own update;"
echo "  7) verify launches and guide recovery via termux-fix-path Module 9 if needed."
printf "Proceed with the update? [y/N] "
IFS= read -r APPROVAL
case "$APPROVAL" in
    y|Y|yes|YES)
        ;;
    *)
        echo "UPDATE_CANCELLED"
        exit 0
        ;;
esac

PIP_APPROVED=0
if [ -n "$PIP_PACKAGES" ]; then
    echo
    echo "WARNING: pip may overwrite Python packages managed by Termux/pkg."
    printf "Update the detected pip packages separately? [y/N] "
    IFS= read -r PIP_APPROVAL
    case "$PIP_APPROVAL" in
        y|Y|yes|YES) PIP_APPROVED=1 ;;
        *) echo "Pip updates skipped by default." ;;
    esac
fi

echo
echo "=== Termux Update Started: $(date) ==="
ERRORS=0
export DEBIAN_FRONTEND=noninteractive

echo "[1/4] Updating Termux packages (apt)..."
if ! apt-get update; then
    echo "ERROR: apt-get update failed!"
    ERRORS=$((ERRORS + 1))
elif ! apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade; then
    echo "ERROR: apt-get upgrade failed!"
    ERRORS=$((ERRORS + 1))
fi

echo "[1.1] Checking for shadowing wrappers in ~/.local/bin/ (termux-fix-path Module 7)..."
LOCAL_BIN="$HOME/.local/bin"
BACKUP_DIR="$HOME/.local/state/backups"
if [ -d "$LOCAL_BIN" ]; then
    for item in "$LOCAL_BIN"/*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"

        # Check for misplaced backups/directories in ~/.local/bin/
        if [ -d "$item" ] || [[ "$base" == *backup* ]] || [[ "$base" == *.bak ]]; then
            echo "WARNING: Misplaced backup/directory found in $LOCAL_BIN: $base"
            echo "Backups must never reside in PATH ($LOCAL_BIN). Move it to $BACKUP_DIR."
            continue
        fi

        # Check if a native counterpart exists in $PREFIX/bin
        if [ -x "$PREFIX/bin/$base" ]; then
            # If item is a symlink already pointing directly to $PREFIX/bin/$base, it is harmless
            real_item="$(realpath "$item" 2>/dev/null || true)"
            real_native="$(realpath "$PREFIX/bin/$base" 2>/dev/null || true)"
            if [ "$real_item" = "$real_native" ]; then
                continue
            fi

            echo "WARNING: Intercepting wrapper detected: $LOCAL_BIN/$base shadows $PREFIX/bin/$base"
            # Verify if native binary is functional
            if "$PREFIX/bin/$base" --version >/dev/null 2>&1 || "$PREFIX/bin/$base" -v >/dev/null 2>&1 || "$PREFIX/bin/$base" --help >/dev/null 2>&1; then
                echo "Native binary $PREFIX/bin/$base is functional."
                printf "Move shadowing wrapper to %s and clear shell hash cache? [y/N] " "$BACKUP_DIR"
                IFS= read -r DEACTIVATE_CHOICE
                case "$DEACTIVATE_CHOICE" in
                    y|Y|yes|YES)
                        mkdir -p "$BACKUP_DIR"
                        BACKUP_TARGET="$BACKUP_DIR/${base}_$(date +%Y%m%d_%H%M%S).bak"
                        mv "$item" "$BACKUP_TARGET"
                        hash -r 2>/dev/null || true
                        echo "Wrapper moved to $BACKUP_TARGET and shell cache cleared (hash -r)."
                        ;;
                    *)
                        echo "Skipped wrapper deactivation. Notice: $LOCAL_BIN/$base will continue to intercept $PREFIX/bin/$base."
                        ;;
                esac
            else
                echo "Native binary $PREFIX/bin/$base failed basic check; keeping $LOCAL_BIN/$base intact."
            fi
        fi
    done
fi

echo "[2/4] Updating global NPM packages (Claude Code excluded)..."
if command -v npm >/dev/null 2>&1; then
    if [ -n "$NPM_PACKAGES" ] && ! npm update -g $NPM_PACKAGES; then
        echo "ERROR: npm update -g failed!"
        ERRORS=$((ERRORS + 1))
    elif [ -z "$NPM_PACKAGES" ]; then
        echo "No global NPM packages to update."
    fi
else
    echo "NPM is not installed; skipping global NPM packages."
fi

echo "[2.1] Repairing Termux shebangs for all global NPM CLI binaries..."
if command -v termux-fix-shebang >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    NPM_PREFIX="$(npm prefix -g 2>/dev/null || true)"
    if [ -n "$NPM_PREFIX" ] && [ -d "$NPM_PREFIX/bin" ]; then
        for bin_entry in "$NPM_PREFIX/bin"/*; do
            [ -e "$bin_entry" ] || continue
            real_file="$(realpath "$bin_entry" 2>/dev/null || true)"
            if [ -n "$real_file" ] && [ -f "$real_file" ]; then
                # Never run termux-fix-shebang on ELF binaries (termux-fix-path Module 2)
                if ! file "$real_file" 2>/dev/null | grep -q 'ELF'; then
                    if head -n 1 "$real_file" 2>/dev/null | grep -q '^#!'; then
                        termux-fix-shebang "$real_file" 2>/dev/null || true
                    fi
                fi
            fi
        done
    fi

    # Also check package-internal bin scripts (e.g. codex-cli-termux helper scripts)
    if [ -n "$NPM_PREFIX" ] && [ -d "$NPM_PREFIX/lib/node_modules" ]; then
        find "$NPM_PREFIX/lib/node_modules" -maxdepth 4 -type f -path '*/bin/*' \
            ! -name '*.so' ! -name '*.bin' ! -name '*.node' 2>/dev/null | while read -r script_file; do
            if [ -f "$script_file" ] && ! file "$script_file" 2>/dev/null | grep -q 'ELF'; then
                if head -n 1 "$script_file" 2>/dev/null | grep -q '^#!'; then
                    termux-fix-shebang "$script_file" 2>/dev/null || true
                fi
            fi
        done
    fi
    echo "Global NPM CLI shebangs checked and repaired."
else
    echo "WARNING: termux-fix-shebang or npm is unavailable; skipped shebang repair."
fi

echo "[3/4] Updating Python/pip packages..."
if [ "$PIP_APPROVED" -eq 1 ] && [ -n "$PYTHON_BIN" ] && [ -n "$PIP_PACKAGES" ]; then
    if ! "$PYTHON_BIN" -m pip install --upgrade $PIP_PACKAGES; then
        echo "ERROR: pip update failed!"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "Pip updates skipped or not detected."
fi

echo "[3.1/4] Updating uv tools..."
if [ -n "$UV_TOOLS" ] && ! uv tool upgrade --all; then
    echo "ERROR: uv tool update failed!"
    ERRORS=$((ERRORS + 1))
fi

echo "[4/4] Updating Antigravity CLI..."
if ! command -v agy >/dev/null 2>&1; then
    echo "agy is not installed; skipping."
elif ! agy update; then
    echo "ERROR: agy update failed or was cancelled!"
    ERRORS=$((ERRORS + 1))
fi

echo "=== Post-update verification: $(date) ==="
if command -v codex >/dev/null 2>&1; then
    if ! codex --version; then
        echo "ERROR: Codex failed after update. Check Termux shebangs and Node (termux-fix-path Module 9)."
        ERRORS=$((ERRORS + 1))
    fi
fi

if command -v agy >/dev/null 2>&1; then
    if ! agy --help >/dev/null 2>&1; then
        echo "ERROR: agy failed after update."
        echo "Follow recovery in termux-fix-path Module 9: pkg reinstall -y glibc"
        echo "Then verify: agy --help"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo "=== System Update Completed: $(date) ==="
echo "Total Errors: $ERRORS"
echo "Log saved to: $LOG_FILE"

if [ "$ERRORS" -gt 0 ]; then
    echo "Refer to termux-fix-path (Module 9) for recovery procedures:"
    echo "  1) Inspect errors in: $LOG_FILE"
    echo "  2) Verify launcher / ELF / loader with file and readelf"
    echo "  3) Restore from ~/.local/state/backups/ or run pkg reinstall <pkg>"
    echo "  4) Do NOT delete \$PREFIX or run blind mass-updates."
    echo "UPDATE_FAILED"
    exit 1
else
    date +%s > "$LAST_UPDATE_FILE"
    echo "UPDATE_SUCCESS"
    exit 0
fi
