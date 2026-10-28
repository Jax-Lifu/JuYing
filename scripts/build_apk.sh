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

# 确保使用项目隔离的 Python 3.11 (.venv)
ensure_python311() {
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        export PATH="$PROJECT_ROOT/.venv/bin:$PATH"
        return
    elif [[ -x "$PROJECT_ROOT/.venv/Scripts/python.exe" ]]; then
        export PATH="$PROJECT_ROOT/.venv/Scripts:$PATH"
        return
    fi

    if command -v uv >/dev/null 2>&1; then
        echo "检测到尚未初始化 .venv，正在通过 uv sync 自动初始化..."
        uv sync
        if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
            export PATH="$PROJECT_ROOT/.venv/bin:$PATH"
            return
        fi
    fi
}
ensure_python311

# 智能检测并适配当前平台的 Android SDK 路径
ensure_android_sdk() {
    # 1. 优先使用已定义且有效的环境变量
    if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME:-}" ]]; then
        for candidate in "$HOME/Android/Sdk" "/root/Android/Sdk" "/opt/android-sdk" "/usr/lib/android-sdk"; do
            if [[ -d "$candidate" ]]; then
                export ANDROID_HOME="$candidate"
                export ANDROID_SDK_ROOT="$candidate"
                break
            fi
        done
    fi

    # 2. 如果 local.properties 存在，检查其中的 sdk.dir 在当前系统上是否存在
    if [[ -f "$PROJECT_ROOT/local.properties" ]]; then
        local sdk_dir
        sdk_dir=$(grep -E '^\s*sdk\.dir\s*=' "$PROJECT_ROOT/local.properties" | cut -d'=' -f2- | tr -d '\r' | sed 's/\\:/:/g; s/\\\\/\//g')
        if [[ ! -d "$sdk_dir" ]]; then
            # 当前系统的 local.properties 无效（例如由 Windows 生成的盘符路径），临时移开并在退出时恢复
            mv "$PROJECT_ROOT/local.properties" "$PROJECT_ROOT/local.properties.win_tmp"
            trap 'mv -f "$PROJECT_ROOT/local.properties.win_tmp" "$PROJECT_ROOT/local.properties" 2>/dev/null || true' EXIT
        fi
    fi
}
ensure_android_sdk

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
