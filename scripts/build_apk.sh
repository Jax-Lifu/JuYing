#!/usr/bin/env bash
# ============================================================================
# 聚映 (JuYing) Linux / macOS / Git Bash APK 编译与归档脚本
# 位置: scripts/build_apk.sh（可在项目根目录或 scripts 目录下任意位置直接调用）
# 自动将最终编译产物复制到 dist/<版本或日期子目录>/ 下
#
# 用法:
#   ./scripts/build_apk.sh                    默认编译 Debug + Release 并归档至 dist/v{版本}_{日期}/
#   ./scripts/build_apk.sh --debug            仅编译 Debug APK
#   ./scripts/build_apk.sh --release          仅编译 Release APK（含 R8 mapping.txt 归档）
#   ./scripts/build_apk.sh --by-version       按版本号分子目录存放: dist/v0.1.0/
#   ./scripts/build_apk.sh --by-date          按日期分子目录存放:   dist/20261024/
#   ./scripts/build_apk.sh --clean            编译前执行 clean
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

BUILD_TARGET="all"
DIST_MODE="version_date"
DO_CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug|-debug|debug)
            BUILD_TARGET="debug"
            shift
            ;;
        --release|-release|release|-r)
            BUILD_TARGET="release"
            shift
            ;;
        --all|-all|all|-a)
            BUILD_TARGET="all"
            shift
            ;;
        --by-version|-v)
            DIST_MODE="version"
            shift
            ;;
        --by-date|-d)
            DIST_MODE="date"
            shift
            ;;
        --by-version-date)
            DIST_MODE="version_date"
            shift
            ;;
        --clean)
            DO_CLEAN=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

GRADLE_TASKS=()
VARIANTS=()
if [[ "$DO_CLEAN" -eq 1 ]]; then
    GRADLE_TASKS+=("clean")
fi
if [[ "$BUILD_TARGET" == "debug" ]]; then
    GRADLE_TASKS+=(":app:assembleDebug")
    VARIANTS=("debug")
elif [[ "$BUILD_TARGET" == "release" ]]; then
    GRADLE_TASKS+=(":app:assembleRelease")
    VARIANTS=("release")
else
    GRADLE_TASKS+=(":app:assembleDebug" ":app:assembleRelease")
    VARIANTS=("debug" "release")
fi

echo ""
echo "============================================================================"
echo "[1/2] 正在编译 APK (目标: $BUILD_TARGET, 归档模式: $DIST_MODE)"
echo "      执行任务: ${GRADLE_TASKS[*]} -PdistMode=$DIST_MODE"
echo "============================================================================"

if [[ -f "$PROJECT_ROOT/gradlew" && "$(uname -s)" != MINGW* && "$(uname -s)" != CYGWIN* && "$(uname -s)" != MSYS* ]]; then
    chmod +x "$PROJECT_ROOT/gradlew"
    "$PROJECT_ROOT/gradlew" "${GRADLE_TASKS[@]}" "-PdistMode=$DIST_MODE"
else
    "$PROJECT_ROOT/gradlew.bat" "${GRADLE_TASKS[@]}" "-PdistMode=$DIST_MODE"
fi

APP_VER="0.1.0"
BUILD_DATE="$(date +%Y%m%d)"
for v in "${VARIANTS[@]}"; do
    apk_file="$(ls -t "$PROJECT_ROOT/app/build/outputs/apk/$v"/*.apk 2>/dev/null | head -n1 || true)"
    if [[ -n "$apk_file" ]]; then
        base_name="$(basename "$apk_file" .apk)"
        IFS='_' read -r _ _ ver dt <<< "$base_name"
        [[ -n "${ver:-}" ]] && APP_VER="$ver"
        [[ -n "${dt:-}" ]] && BUILD_DATE="$dt"
    fi
done

if [[ "$DIST_MODE" == "version" ]]; then
    SUB_DIR="v${APP_VER}"
elif [[ "$DIST_MODE" == "date" ]]; then
    SUB_DIR="${BUILD_DATE}"
else
    SUB_DIR="v${APP_VER}_${BUILD_DATE}"
fi

TARGET_DIST="$PROJECT_ROOT/dist/$SUB_DIR"
mkdir -p "$TARGET_DIST"

for v in "${VARIANTS[@]}"; do
    apk_file="$(ls -t "$PROJECT_ROOT/app/build/outputs/apk/$v"/*.apk 2>/dev/null | head -n1 || true)"
    if [[ -n "$apk_file" && -f "$apk_file" ]]; then
        cp -f "$apk_file" "$TARGET_DIST/"
        if [[ "$v" == "release" && -f "$PROJECT_ROOT/app/build/outputs/mapping/release/mapping.txt" ]]; then
            base_name="$(basename "$apk_file" .apk)"
            cp -f "$PROJECT_ROOT/app/build/outputs/mapping/release/mapping.txt" "$TARGET_DIST/${base_name}_mapping.txt"
        fi
    fi
done

echo ""
echo "============================================================================"
echo "[2/2] 编译与归档完成！输出目录: $TARGET_DIST"
echo "============================================================================"
ls -lh "$TARGET_DIST"
echo ""
