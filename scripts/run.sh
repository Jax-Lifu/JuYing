#!/usr/bin/env bash
# ============================================================================
# 聚映 (JuYing) Linux / macOS / Git Bash 一键编译、设备选择、安装与启动脚本
# 位置: scripts/run.sh（可在项目根目录或 scripts 目录下任意位置直接调用）
#
# 用法:
#   ./scripts/run.sh                        编译 Debug，单设备直装 / 多设备交互选择
#   ./scripts/run.sh --all                  编译 Debug，安装并打开所有在线设备
#   ./scripts/run.sh --release              编译 Release，单设备直装 / 多设备交互选择
#   ./scripts/run.sh --release --all        编译 Release，安装并打开所有在线设备
#   ./scripts/run.sh --device qytech6666    指定设备序列号安装
#   ./scripts/run.sh --skip-build --all     跳过编译，直接安装最新通用双架构 APK 到所有设备
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
    if [[ -z "${ANDROID_HOME:-}" || ! -d "${ANDROID_HOME:-}" ]]; then
        for candidate in "$HOME/Android/Sdk" "/root/Android/Sdk" "/opt/android-sdk" "/usr/lib/android-sdk"; do
            if [[ -d "$candidate" ]]; then
                export ANDROID_HOME="$candidate"
                export ANDROID_SDK_ROOT="$candidate"
                break
            fi
        done
    fi

    if [[ -f "$PROJECT_ROOT/local.properties" ]]; then
        local sdk_dir
        sdk_dir=$(grep -E '^\s*sdk\.dir\s*=' "$PROJECT_ROOT/local.properties" | cut -d'=' -f2- | tr -d '\r' | sed 's/\\:/:/g; s/\\\\/\//g')
        if [[ ! -d "$sdk_dir" ]]; then
            mv "$PROJECT_ROOT/local.properties" "$PROJECT_ROOT/local.properties.win_tmp"
            trap 'mv -f "$PROJECT_ROOT/local.properties.win_tmp" "$PROJECT_ROOT/local.properties" 2>/dev/null || true' EXIT
        fi
    fi
}
ensure_android_sdk

APP_PACKAGE="com.flytech.juying"
MAIN_ACTIVITY="com.flytech.juying/.MainActivity"
BUILD_TYPE="debug"
GRADLE_TASK=":app:assembleDebug"
INSTALL_ALL=0
SKIP_BUILD=0
TARGET_SERIAL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release|-release|release|-r)
            BUILD_TYPE="release"
            GRADLE_TASK=":app:assembleRelease"
            shift
            ;;
        --all|-all|all|-a)
            INSTALL_ALL=1
            shift
            ;;
        --skip-build|-skipbuild)
            SKIP_BUILD=1
            shift
            ;;
        --device|-device|-s)
            TARGET_SERIAL="${2:-}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# 1. 查找 adb
find_adb() {
    if [[ -f "$PROJECT_ROOT/local.properties" ]]; then
        local sdk_dir
        sdk_dir="$(grep -E '^sdk\.dir=' "$PROJECT_ROOT/local.properties" | head -n1 | cut -d'=' -f2- | sed 's/\\:/:/g; s/\\\\/\//g' | tr -d '\r')"
        if [[ -n "$sdk_dir" ]]; then
            if [[ -x "$sdk_dir/platform-tools/adb" ]]; then
                echo "$sdk_dir/platform-tools/adb"
                return 0
            elif [[ -f "$sdk_dir/platform-tools/adb.exe" ]]; then
                echo "$sdk_dir/platform-tools/adb.exe"
                return 0
            fi
        fi
    fi
    for env_dir in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
        if [[ -n "$env_dir" ]]; then
            if [[ -x "$env_dir/platform-tools/adb" ]]; then
                echo "$env_dir/platform-tools/adb"
                return 0
            elif [[ -f "$env_dir/platform-tools/adb.exe" ]]; then
                echo "$env_dir/platform-tools/adb.exe"
                return 0
            fi
        fi
    done
    if command -v adb >/dev/null 2>&1; then
        command -v adb
        return 0
    fi
    echo "错误: 未找到 adb，请检查 local.properties 中的 sdk.dir 或 ANDROID_HOME 环境变量。" >&2
    exit 1
}

ADB_BIN="$(find_adb)"

# 2. 执行 Gradle 编译
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo ""
    echo "[1/3] 正在编译 JuYing ($BUILD_TYPE) -> $GRADLE_TASK ..."
    if [[ -f "$PROJECT_ROOT/gradlew" && "$(uname -s)" != MINGW* && "$(uname -s)" != CYGWIN* && "$(uname -s)" != MSYS* ]]; then
        chmod +x "$PROJECT_ROOT/gradlew"
        "$PROJECT_ROOT/gradlew" "$GRADLE_TASK"
    else
        "$PROJECT_ROOT/gradlew.bat" "$GRADLE_TASK"
    fi
else
    echo ""
    echo "[1/3] 已跳过编译 (--skip-build)，直接查找最新通用双架构 APK..."
fi

APK_DIR="$PROJECT_ROOT/app/build/outputs/apk/$BUILD_TYPE"
APK_FILE="$(ls -t "$APK_DIR"/JuYing_"$BUILD_TYPE"_*_universal.apk 2>/dev/null | head -n1 || true)"
if [[ -z "$APK_FILE" || ! -f "$APK_FILE" ]]; then
    echo "错误: 未在 $APK_DIR 下找到通用双架构 APK（*_universal.apk），请先不带 --skip-build 运行以编译通用包。" >&2
    exit 1
fi
echo "      产物文件: $(basename "$APK_FILE")"

# 3. 扫描在线设备
echo ""
echo "[2/3] 正在扫描已连接的 ADB 设备..."
SERIALS=()
MODELS=()
AVERS=()

while IFS=$' \t\r' read -r s status _; do
    if [[ "${status:-}" == "device" && -n "${s:-}" ]]; then
        m="$("$ADB_BIN" -s "$s" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r' || echo "Unknown")"
        v="$("$ADB_BIN" -s "$s" shell getprop ro.build.version.release </dev/null 2>/dev/null | tr -d '\r' || echo "?")"
        SERIALS+=("$s")
        MODELS+=("${m:-Unknown}")
        AVERS+=("Android ${v:-?}")
    fi
done < <("$ADB_BIN" devices | tail -n +2)

DEV_COUNT="${#SERIALS[@]}"
if [[ "$DEV_COUNT" -eq 0 ]]; then
    echo "错误: 未检测到任何在线的 Android 设备（请确认 adb devices 状态为 device）。" >&2
    exit 1
fi

# 4. 选择目标设备
TARGET_INDICES=()
if [[ -n "$TARGET_SERIAL" ]]; then
    for i in "${!SERIALS[@]}"; do
        if [[ "${SERIALS[$i]}" == "$TARGET_SERIAL" ]]; then
            TARGET_INDICES+=("$i")
        fi
    done
    if [[ "${#TARGET_INDICES[@]}" -eq 0 ]]; then
        echo "错误: 未找到序列号为 '$TARGET_SERIAL' 的在线设备。" >&2
        exit 1
    fi
    echo "      已指定设备: $TARGET_SERIAL"
elif [[ "$INSTALL_ALL" -eq 1 ]]; then
    for i in "${!SERIALS[@]}"; do
        TARGET_INDICES+=("$i")
    done
    echo "      已开启全部安装 (--all)，共 $DEV_COUNT 台在线设备。"
elif [[ "$DEV_COUNT" -eq 1 ]]; then
    TARGET_INDICES=(0)
    echo "      仅检测到 1 台设备，自动选择: ${SERIALS[0]} (${MODELS[0]}, ${AVERS[0]})"
else
    echo "      检测到 $DEV_COUNT 台在线设备："
    for i in "${!SERIALS[@]}"; do
        idx=$((i + 1))
        printf "        [%d] %-18s | %-12s | %s\n" "$idx" "${SERIALS[$i]}" "${MODELS[$i]}" "${AVERS[$i]}"
    done
    echo "        [A] 全部设备安装并启动 (All)"

    while [[ "${#TARGET_INDICES[@]}" -eq 0 ]]; do
        read -r -p $'\n请选择设备编号 (输入单个如 1，多个用逗号/空格分隔如 1,2，或输入 A 全部安装): ' choice
        choice="$(echo "$choice" | tr -d '\r')"
        if [[ "$choice" =~ ^([aA]|[aA][lL][lL]|0|\*)$ ]]; then
            for i in "${!SERIALS[@]}"; do
                TARGET_INDICES+=("$i")
            done
            break
        fi
        IFS=', ' read -r -a parts <<< "$choice"
        valid=1
        for p in "${parts[@]}"; do
            [[ -z "$p" ]] && continue
            if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= DEV_COUNT )); then
                TARGET_INDICES+=("$((p - 1))")
            else
                valid=0
                break
            fi
        done
        if [[ "$valid" -eq 0 || "${#TARGET_INDICES[@]}" -eq 0 ]]; then
            TARGET_INDICES=()
            echo "输入无效，请输入 1~$DEV_COUNT 的数字或 A。"
        fi
    done
fi

# 5. 安装并启动
echo ""
echo "[3/3] 开始安装并打开应用 ($(basename "$APK_FILE"))..."
INSTALL_FAILED=0
for i in "${TARGET_INDICES[@]}"; do
    s="${SERIALS[$i]}"
    m="${MODELS[$i]}"
    echo ""
    echo "  --> 目标设备: $s ($m, ${AVERS[$i]})"
    install_status=0
    install_out="$("$ADB_BIN" -s "$s" install -r "$APK_FILE" </dev/null 2>&1)" || install_status=$?
    if [[ "$install_status" -ne 0 || "$install_out" != *"Success"* ]]; then
        INSTALL_FAILED=1
        echo "      [失败] 安装到 $s 失败:"
        echo "$install_out"
        echo "      已保留旧应用和数据，请检查签名、版本号或设备空间后重试。"
        continue
    fi
    echo "      [成功] APK 安装完成，正在启动 $MAIN_ACTIVITY ..."
    "$ADB_BIN" -s "$s" shell am force-stop "$APP_PACKAGE" </dev/null >/dev/null 2>&1 || true
    start_out="$("$ADB_BIN" -s "$s" shell am start -W -n "$MAIN_ACTIVITY" </dev/null 2>&1 | tr -d '\r' || true)"
    total_time="$(echo "$start_out" | grep -E '^TotalTime:' | head -n1 || true)"
    echo "      [已启动] $MAIN_ACTIVITY ($total_time)"
done

echo ""
echo "全部任务执行完毕！"
exit "$INSTALL_FAILED"
