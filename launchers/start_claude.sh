#!/bin/sh
clear
cd "$(dirname "$0")/.." || { echo "start_claude.sh: cannot cd to the workspace root" >&2; exit 1; }

# 显式声明纯净 UTF-8 环境，保障单字符多字节流传输
export LANG="zh_CN.UTF-8"
export LC_ALL="zh_CN.UTF-8"

exec claude --dangerously-skip-permissions