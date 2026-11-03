#!/usr/bin/env bash
# ============================================================================
# 聚映 (JuYing) Linux / WSL 开发环境一键初始化脚本
# 作用: 自动安装/配置 uv、Python 3.11，并通过 uv sync 建立项目隔离虚拟环境 (.venv)
# 用法: ./scripts/setup_env.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "============================================================"
echo "        聚映 (JuYing) Linux / WSL 开发环境初始化 (uv)        "
echo "============================================================"

# 1. 检查或安装 uv
if ! command -v uv >/dev/null 2>&1; then
    if [[ -x "$HOME/.local/bin/uv" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    elif [[ -x "$HOME/.cargo/bin/uv" ]]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
fi

if ! command -v uv >/dev/null 2>&1; then
    echo ""
    echo "[1/3] 未检测到 uv，正在通过官方安装脚本自动安装..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    if ! command -v uv >/dev/null 2>&1; then
        echo "错误: 自动安装 uv 失败，请访问 https://docs.astral.sh/uv/ 手动安装后重试。" >&2
        exit 1
    fi
    echo "  -> uv 安装成功！"
else
    echo ""
    echo "[1/3] 检测到 uv 已安装: $(which uv)"
fi

# 2. 确保 Python 3.11 运行时存在
echo ""
echo "[2/3] 检查 Python 3.11 运行时..."
uv python install 3.11
echo "  -> Python 3.11 运行时就绪！"

# 3. 通过 uv sync 同步并锁定 .venv
echo ""
echo "[3/3] 正在通过 uv sync 锁定并同步本地环境与依赖..."
uv sync

VENV_PYTHON="$PROJECT_ROOT/.venv/bin/python"
if [[ -x "$VENV_PYTHON" ]]; then
    PY_VER="$("$VENV_PYTHON" --version 2>&1)"
    echo ""
    echo "============================================================"
    echo "  环境初始化完成！"
    echo "  项目虚拟环境路径: $PROJECT_ROOT/.venv"
    echo "  解释器版本: $PY_VER"
    echo "  已安装本地依赖: requests, beautifulsoup4, lxml"
    echo "  后续构建无需任何额外配置，脚本与 Gradle 会自动优先使用此环境。"
    echo "============================================================"
else
    echo "警告: .venv/bin/python 未找到，请检查 uv sync 输出。" >&2
fi
