#!/bin/bash
set -e
cd "$(dirname "$0")"

mkdir -p build
cmake -B build -DCMAKE_BUILD_TYPE=Release "$@"
cmake --build build -j"$(nproc)"

echo
echo "构建完成。可执行文件: build/sftp-dual-pane"
echo "运行: ./build/sftp-dual-pane"
