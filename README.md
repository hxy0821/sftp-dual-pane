# 双栏文件传输（SFTP Dual-Pane）

自用轻量级 SFTP 文件传输工具，基于 **C++ + Qt Quick(QML) + libssh2**，在 UOS V20 上运行。

## 功能

- 左侧：本机文件浏览
- 右侧：远程 Linux 主机文件浏览（SFTP/SSH）
- IP / 用户名 / 密码连接（端口默认 22）
- 拖拽传输：左 → 右上传，右 → 左下载
- 目录递归上传/下载，多选拖拽
- 右键菜单：上传/下载、打开、重命名、删除、新建文件夹、刷新
- 传输进度条与速度、日志面板
- 保存常用连接、记住上次左右路径、显示隐藏文件

## 目录结构

```
sftp-dual-pane/
├── CMakeLists.txt
├── build.sh
├── resources.qrc
├── thirdparty/libssh2/     # vendored libssh2 源码（首次构建时已下载）
├── src/
│   ├── main.cpp
│   ├── sftpclient.h/.cpp        # libssh2 封装
│   ├── dirmodel.h/.cpp          # 本地/远程统一目录模型
│   ├── transferthread.h/.cpp    # 后台传输线程
│   ├── settingsstore.h/.cpp     # 连接与路径持久化
│   ├── fileentry.h
│   └── pathutil.h
└── qml/
    ├── main.qml
    ├── FilePane.qml
    └── utils.js
```

## 构建

依赖：Qt 5.11+（Core/Gui/Quick/Qml/Network）、CMake ≥ 3.16、g++、OpenSSL 头文件。

libssh2 以源码形式随项目编译，无需系统安装。

```bash
./build.sh
# 或手动：
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
```

可执行文件：`build/sftp-dual-pane`

## 运行

```bash
./build/sftp-dual-pane
```

目标机器需开启 sshd（UOS/Linux 默认一般已开启）：

```bash
# 目标机器上确认
systemctl status ssh   # 或 sshd
```

## 使用说明

1. 顶部输入 主机 / 端口 / 用户 / 密码，点「连接」。
2. 左侧双击进入本机目录，右侧双击进入远程目录。
3. 拖拽文件/文件夹到另一侧即传输（可 Ctrl 多选后拖拽）。
4. 底部「日志」按钮查看传输记录。

## 已知限制（MVP）

- 仅支持密码登录（私钥登录留待后续）。
- 目录浏览为同步操作，慢网络下界面可能短暂卡顿。
- 密码保存为明文（仅存于本机用户配置目录 `~/.config/selftools/`）。

## 后续可做

- SSH 私钥登录
- 断点续传 / 传输队列可视化
- 远程目录异步加载
- 远程内部拖拽移动
- 传输冲突策略（覆盖/跳过/重命名）
