#!/bin/bash
# 将 sftp-dual-pane 编译并打包为 UOS / Debian 可安装的 .deb
# 用法: ./packaging/package.sh [--rebuild]
set -euo pipefail

PKG="sftp-dual-pane"
VER="1.0.0"
ARCH="amd64"
MAINT="selftools <selftools@localhost>"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ---------- 1. 编译（Release） ----------
if [ "${1:-}" = "--rebuild" ] || [ ! -x build/sftp-dual-pane ]; then
    echo ">> 编译 Release 版本 ..."
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j"$(nproc)"
else
    echo ">> 复用已有构建: build/sftp-dual-pane"
fi

# ---------- 2. 暂存目录 ----------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APPDIR="$STAGE/${PKG}_${VER}_${ARCH}"

install -d "$APPDIR/DEBIAN"
install -d "$APPDIR/usr/bin"
install -d "$APPDIR/usr/share/applications"
install -d "$APPDIR/usr/share/icons/hicolor/scalable/apps"
install -d "$APPDIR/usr/share/doc/$PKG"

# ---------- 3. 可执行文件（strip 瘦身） ----------
install -m 0755 build/sftp-dual-pane "$APPDIR/usr/bin/$PKG"
strip --strip-unneeded "$APPDIR/usr/bin/$PKG" 2>/dev/null || true

# ---------- 4. 桌面入口 ----------
install -m 0644 packaging/$PKG.desktop "$APPDIR/usr/share/applications/$PKG.desktop"

# ---------- 5. 图标（SVG + 多尺寸 PNG） ----------
install -m 0644 packaging/$PKG.svg "$APPDIR/usr/share/icons/hicolor/scalable/apps/$PKG.svg"
if command -v rsvg-convert >/dev/null 2>&1; then
    for s in 16 24 32 48 64 128 256 512; do
        d="$APPDIR/usr/share/icons/hicolor/${s}x${s}/apps"
        install -d "$d"
        rsvg-convert -w "$s" -h "$s" packaging/$PKG.svg -o "$d/$PKG.png"
    done
else
    echo "!! 未找到 rsvg-convert，跳过 PNG 图标（仅保留 SVG）"
fi

# ---------- 6. 文档 ----------
install -m 0644 README.md "$APPDIR/usr/share/doc/$PKG/README.md"

# ---------- 7. 控制信息 ----------
cat > "$APPDIR/DEBIAN/control" <<EOF
Package: $PKG
Version: $VER
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: $MAINT
Depends: libc6 (>= 2.27), libstdc++6, libgcc1, libqt5core5a (>= 5.11.0), libqt5gui5 (>= 5.11.0), libqt5qml5 (>= 5.11.0), libqt5quick5 (>= 5.11.0), libqt5network5 (>= 5.11.0), libssl1.1, libgl1, libxcb1, qml-module-qtquick2, qml-module-qtquick-window2, qml-module-qtquick-controls2, qml-module-qtquick-templates2, qml-module-qtquick-layouts
Installed-Size: 0
Description: 双栏 SFTP 文件传输工具
 左本机、右远程的双栏文件管理器：拖拽即可上传/下载，
 支持保存常用连接与传输进度显示，并内置 SSH 终端。
 基于 C++ / Qt QML 与 libssh2 实现，面向 UOS 桌面环境。
EOF

# 安装体积（KB）
SZ=$(du -sk --exclude=DEBIAN "$APPDIR" | cut -f1)
sed -i "s/^Installed-Size: 0/Installed-Size: $SZ/" "$APPDIR/DEBIAN/control"

# ---------- 8. 安装/卸载钩子：刷新桌面与图标缓存 ----------
cat > "$APPDIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
cat > "$APPDIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
exit 0
EOF
chmod 0755 "$APPDIR/DEBIAN/postinst" "$APPDIR/DEBIAN/postrm"

# ---------- 9. 打包 ----------
OUT="$ROOT/dist"
install -d "$OUT"
DEB="$OUT/${PKG}_${VER}_${ARCH}.deb"
rm -f "$DEB"
dpkg-deb --build --root-owner-group "$APPDIR" "$DEB" >/dev/null

echo
echo "==================== 打包完成 ===================="
echo "包文件 : $DEB"
echo "大小   : $(du -h "$DEB" | cut -f1)"
echo "安装   : sudo dpkg -i \"$DEB\""
echo "         sudo apt-get -f install   # 自动补齐依赖"
echo "运行   : sftp-dual-pane   （或从开始菜单启动）"
echo "卸载   : sudo dpkg -r $PKG"
echo "=================================================="
