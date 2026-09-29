import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11
import App 1.0
import "utils.js" as Utils

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 800
    // 连接栏完整宽度约 1215px（含边距），最小窗口宽度不能低于它，否则控件被裁剪
    minimumWidth: 1360
    minimumHeight: 620
    title: "双栏文件传输 - SFTP"
    color: "#eef1f5"
    font.pixelSize: 13

    property bool remoteReady: browse.connected
    property bool connecting: false
    property string statusMsg: ""
    property color statusMsgColor: "#7b8494"

    // ---------- 传输队列（spec §13/§33） ----------
    property int bottomPage: 0        // 底部面板切换：0=传输队列 1=终端
    ListModel { id: transferListModel }
    property bool transferPaused: false
    property int activeCount: 0      // 队列 + 运行中 + 失败
    property int doneCount: 0
    property real upSpeed: 0
    property real downSpeed: 0

    function findTaskRow(label, statusList) {
        for (var i = 0; i < transferListModel.count; i++) {
            var it = transferListModel.get(i)
            if (it.label === label && statusList.indexOf(it.status) >= 0)
                return i
        }
        return -1
    }
    // 当前表单实际载入的已保存连接名；为空表示表单是手动输入的新连接。
    // 下拉框的高亮始终跟随它，保证“看到的名字”和“表单里的值”一致
    property string loadedConnection: ""
    property string remoteStart: {
        var p = settingsStore.lastRemotePath()
        return (p && p.length) ? p : "/"
    }

    // 底部单行状态消息：✘ 开头显示红色，✔ 开头显示绿色，⚠ 开头显示橙色
    function log(msg) {
        statusMsg = msg
        if (msg.indexOf("✘") === 0)
            statusMsgColor = "#d5494e"
        else if (msg.indexOf("✔") === 0)
            statusMsgColor = "#2fa356"
        else if (msg.indexOf("⚠") === 0)
            statusMsgColor = "#d99a2b"
        else
            statusMsgColor = "#7b8494"
    }

    function refreshSaved() {
        savedCombo.model = settingsStore.savedNames()
        // ComboBox 换模型后会把 currentIndex 归 0，这里按当前载入的连接重新对齐，
        // 避免出现“下拉框显示着某个连接、表单里却是空/别的值”的错位观感
        var idx = savedCombo.model.indexOf(loadedConnection)
        savedCombo.currentIndex = idx
    }

    function clearLoaded() {
        loadedConnection = ""
        savedCombo.currentIndex = -1
    }

    // 把已保存连接载入表单；autoConnect 为 true 时顺带一键连接
    function applySaved(index, autoConnect) {
        var name = savedCombo.model[index]
        var m = settingsStore.connection(name)
        if (!m || !m.host)
            return
        hostField.text = m.host
        portField.text = m.port ? m.port.toString() : "22"
        userField.text = m.user ? m.user : ""
        passField.text = m.password ? m.password : ""
        loadedConnection = name
        savedCombo.currentIndex = index
        settingsStore.setLastConnection(name)
        if (autoConnect) {
            // 已连接其它主机时，先断开再连所选设备，实现一键切换
            if (browse.connected)
                doDisconnect()
            doConnect()
        }
    }

    function doConnect() {
        var h = hostField.text.trim()
        if (!h) { log("✘ 请输入主机 IP / 主机名"); return }
        if (connecting) { log("正在连接中，请稍候…"); return }
        browse.host = h
        browse.port = parseInt(portField.text) || 22
        browse.user = userField.text.trim()
        browse.password = passField.text
        log("正在连接 " + browse.user + "@" + browse.host + ":" + browse.port + " …")
        connecting = true
        browse.connectToHost(6000)
    }

    function doDisconnect() {
        connecting = false
        transferPaused = false
        transfer.disconnectRemote()
        if (shell.running)
            shell.closeSession()
        browse.disconnect()
        log("已断开连接，在途传输已中断")
    }

    function startTransfer(src, dst, paths) {
        if (!paths || paths.length === 0)
            return
        transfer.host = browse.host
        transfer.port = browse.port
        transfer.user = browse.user
        transfer.password = browse.password
        if (dst === "remote") {
            if (!browse.connected) { log("✘ 未连接远程主机，无法上传"); return }
            transfer.enqueueUpload(paths, remoteModel.currentPath)
            log("↑ 开始上传 " + paths.length + " 项 → " + remoteModel.currentPath)
        } else {
            transfer.enqueueDownload(paths, localModel.currentPath)
            log("↓ 开始下载 " + paths.length + " 项 → " + localModel.currentPath)
        }
    }

    // ---------- 传输队列操作 ----------
    function retryTransfer(index) {
        var it = transferListModel.get(index)
        if (!it || it.status !== "failed")
            return
        transferListModel.remove(index)
        if (activeCount > 0)
            activeCount--
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法重试")
            return
        }
        transfer.host = browse.host
        transfer.port = browse.port
        transfer.user = browse.user
        transfer.password = browse.password
        if (it.upload)
            transfer.enqueueUpload([it.srcPath], it.dstDir)
        else
            transfer.enqueueDownload([it.srcPath], it.dstDir)
    }

    function deleteTransfer(index) {
        var it = transferListModel.get(index)
        if (!it || it.status !== "cancelled")
            return
        transferListModel.remove(index)
        if (activeCount > 0)
            activeCount--
    }

    function clearFinishedTasks() {
        for (var i = transferListModel.count - 1; i >= 0; i--) {
            if (transferListModel.get(i).status === "done")
                transferListModel.remove(i)
        }
        doneCount = 0
    }

    // ---------- 打开文件 ----------
    function openLocalPath(path) {
        if (!settingsStore.openPath(path))
            log("✘ 无法打开 " + path)
    }

    // 远程文件：下载到本地缓存目录后用默认应用打开（单向预览，不回传）
    function openRemotePath(model, index) {
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法打开远程文件")
            return
        }
        var size = model.sizeAt(index)
        if (size > 100 * 1024 * 1024) {
            log("✘ 文件超过 100MB，不支持直接打开，请下载后查看")
            return
        }
        var p = model.pathAt(index)
        var rel = p.replace(/^\/+/, "")
        if (rel.length === 0 || rel.indexOf("..") >= 0) {
            log("✘ 路径无法用于本地缓存: " + p)
            return
        }
        var base = settingsStore.homeDir() + "/.cache/sftp-dual-pane/open"
        var slash = rel.lastIndexOf("/")
        var dir = slash > 0 ? base + "/" + rel.substring(0, slash) : base
        // 传输线程持有独立连接，打开前必须同步连接凭据（否则“主机地址为空”）
        transfer.host = browse.host
        transfer.port = browse.port
        transfer.user = browse.user
        transfer.password = browse.password
        transfer.enqueueDownload([p], dir, true)
    }

    // ---------- 终端 ----------
    function openTerminal() {
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法打开终端")
            return
        }
        bottomPage = 1
        if (!shell.running) {
            shell.host = browse.host
            shell.port = browse.port
            shell.user = browse.user
            shell.password = browse.password
            shell.startSession()
        }
        terminalPanel.focusTerminal()
    }
    function closeTerminal() {
        if (shell.running)
            shell.closeSession()
        bottomPage = 0
    }
    function toggleTerminal() {
        if (bottomPage === 1)
            bottomPage = 0   // 切回传输文件页，终端会话保持存活
        else
            openTerminal()
    }

    // ---------- 后端对象 ----------
    BrowseThread {
        id: browse
        onConnectFinished: {
            connecting = false
            if (ok) {
                log("✔ 已连接 " + browse.user + "@" + browse.host + ":" + browse.port)
                remoteModel.setDir(root.remoteStart)
            } else {
                log("✘ 连接失败: " + err)
            }
        }
        onDisconnected: {
            connecting = false
            log("远程连接已断开，在途传输已中断")
        }
        onStatResult: {
            if (!pendingBack || path !== pendingBack.remotePath)
                return
            if (err.length > 0) {
                log("✘ 无法读取远程文件状态: " + err)
                pendingBack = null
                return
            }
            if (size !== pendingBack.baselineSize) {
                // 远程文件在打开后被其它途径修改过，需确认才能覆盖
                backConflictDialog.openFor(pendingBack, size)
            } else {
                doUploadBack(pendingBack)
            }
        }
    }

    ShellSession {
        id: shell
        onOutputReceived: terminalPanel.appendOutput(text)
        onSessionStarted: {
            terminalPanel.setConnected()
            log("终端已连接")
        }
        onSessionClosed: {
            terminalPanel.setClosed(reason)
            log("终端已关闭: " + reason)
        }
    }

    TransferThread {
        id: transfer
        onTaskQueued: {
            transferListModel.append({
                label: label,
                name: label.replace(/^(上传|下载|打开)\s*/, ""),
                upload: upload,
                srcPath: srcPath,
                dstDir: dstDir,
                size: 0, done: 0, speed: 0, eta: -1, lastTs: 0,
                status: "queued"
            })
            activeCount++
        }
        onQueueCleared: {
            for (var i = transferListModel.count - 1; i >= 0; i--) {
                if (transferListModel.get(i).status === "queued")
                    transferListModel.remove(i)
            }
            var n = 0
            for (var j = 0; j < transferListModel.count; j++) {
                if (transferListModel.get(j).status !== "done")
                    n++
            }
            activeCount = n
        }
        onTaskCancelled: {
            var i = findTaskRow(label, ["queued"])
            if (i >= 0) {
                transferListModel.remove(i)
                if (activeCount > 0)
                    activeCount--
            }
        }
        onTaskStarted: {
            // 新任务开始：清除上一次遗留的暂停态（UI 与传输线程同步恢复）
            if (transferPaused) {
                transferPaused = false
                transfer.resumeTransfer()
            }
            var i = findTaskRow(label, ["queued"])
            if (i >= 0) {
                transferListModel.setProperty(i, "status", "running")
            } else {
                transferListModel.append({
                    label: label,
                    name: label.replace(/^(上传|下载|打开)\s*/, ""),
                    upload: upload,
                    srcPath: "", dstDir: "",
                    size: 0, done: 0, speed: 0, eta: -1, lastTs: 0,
                    status: "running"
                })
                activeCount++
            }
            log(label)
        }
        onProgress: {
            var i = findTaskRow(label, ["running"])
            if (i < 0)
                return
            var it = transferListModel.get(i)
            var now = Date.now()
            var sp = it.speed
            if (now - it.lastTs > 200 && done > it.done) {
                var inst = (done - it.done) * 1000.0 / (now - it.lastTs)
                sp = sp > 0 ? sp * 0.7 + inst * 0.3 : inst
                transferListModel.setProperty(i, "lastTs", now)
                var remaining = Math.max(0, total - done)
                transferListModel.setProperty(i, "eta", sp > 0 ? remaining / sp : -1)
                if (it.upload)
                    upSpeed = sp
                else
                    downSpeed = sp
            }
            transferListModel.setProperty(i, "done", done)
            if (total > 0)
                transferListModel.setProperty(i, "size", total)
            transferListModel.setProperty(i, "speed", sp)
        }
        onTaskFinished: {
            var i = findTaskRow(label, ["running", "queued"])
            if (i >= 0) {
                var cancelled = message.indexOf("已中断") >= 0
                transferListModel.setProperty(i, "status",
                                              ok ? "done" : (cancelled ? "cancelled" : "failed"))
                transferListModel.setProperty(i, "speed", 0)
                transferListModel.setProperty(i, "eta", -1)
            }
            upSpeed = 0
            downSpeed = 0
            if (ok) {
                if (activeCount > 0)
                    activeCount--
                doneCount++
                // 回传任务成功：更新登记基线，继续处理其余待回传文件
                if (uploadBackActive && pendingBack
                        && label === "上传 " + pendingBack.name) {
                    uploadBackActive = false
                    openRegistry.markSynced(pendingBack.remotePath)
                    pendingBack = null
                    if (openRegistry.dirtyCount > 0)
                        startUploadBack()
                }
            } else {
                if (uploadBackActive) {
                    uploadBackActive = false
                    pendingBack = null
                }
            }
            log((ok ? "✔ " : "✘ ") + label + " — " + message)
        }
        onTaskDone: {
            if (ok) {
                if (upload)
                    remoteModel.refresh()
                else
                    localModel.refresh()
            }
        }
        onOpenReady: {
            if (!ok) {
                log("✘ 打开失败: " + err)
                return
            }
            // 登记到回传注册表：监视本地副本，检测编辑后提示上传
            openRegistry.registerOpen(remotePath, localPath, remoteSize)
            if (settingsStore.openPath(localPath))
                log("✔ 已用本地应用打开 " + localPath)
            else
                log("✘ 无法打开 " + localPath)
        }
    }

    // ---------- 编辑回传 ----------
    property var pendingBack: null   // 当前正在走回传流程的登记项
    property bool uploadBackActive: false

    function startUploadBack() {
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法回传")
            return
        }
        var e = openRegistry.nextDirty()
        if (e.remotePath === undefined) {
            log("没有待回传的本地修改")
            return
        }
        pendingBack = e
        browse.statFile(e.remotePath)   // 先查远程状态做冲突检测
    }

    function uploadOneBack(remotePath) {
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法回传")
            return
        }
        var e = openRegistry.entryFor(remotePath)
        if (e.remotePath === undefined)
            return
        pendingBack = e
        browse.statFile(e.remotePath)
    }

    function doUploadBack(e) {
        var slash = e.remotePath.lastIndexOf("/")
        var parentDir = slash > 0 ? e.remotePath.substring(0, slash) : "/"
        transfer.host = browse.host
        transfer.port = browse.port
        transfer.user = browse.user
        transfer.password = browse.password
        uploadBackActive = true
        transfer.enqueueUpload([e.localPath], parentDir)
    }

    DirModel {
        id: localModel
        remote: false
        startPath: settingsStore.lastLocalPath()
        onErrorOccurred: log("✘ 本地: " + message)
    }

    DirModel {
        id: remoteModel
        remote: true
        browse: browse
        startPath: settingsStore.lastRemotePath()
        onErrorOccurred: log("✘ 远程: " + message)
    }

    // ---------- 主体布局 ----------
    // 左侧导航（spec §7：模块入口，不引入多页面）
    Rectangle {
        id: sideNav
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        width: 132
        radius: 8
        color: "#ffffff"
        border.width: 1
        border.color: "#e3e7ee"

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            // 传输文件（默认页：底部显示传输队列）
            Rectangle {
                id: navFile
                width: parent.width
                height: 38
                radius: 6
                readonly property bool active: bottomPage === 0
    onActiveChanged: fileIco.requestPaint()
                color: navFile.active ? "#e9f0ff" : (navMa1.containsMouse ? "#f2f6fc" : "transparent")
                Rectangle { width: 3; height: 20; radius: 1.5; color: navFile.active ? "#3a7afe" : "transparent"
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    spacing: 8
                    Canvas {
                        id: fileIco
                        width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = navFile.active ? "#3a7afe" : "#5a6472"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            ctx.moveTo(4.5, 12); ctx.lineTo(4.5, 4)
                            ctx.moveTo(2.2, 6.5); ctx.lineTo(4.5, 4); ctx.lineTo(6.8, 6.5)
                            ctx.moveTo(11.5, 4); ctx.lineTo(11.5, 12)
                            ctx.moveTo(9.2, 9.5); ctx.lineTo(11.5, 12); ctx.lineTo(13.8, 9.5)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: "传输文件"; color: navFile.active ? "#1d5fd6" : "#3a414a"
                            font.bold: navFile.active }
                    Item { width: 4; height: 1 }
                    Rectangle {
                        visible: activeCount > 0
                        width: Math.max(18, countLbl.implicitWidth + 8)
                        height: 15
                        radius: 7.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#3a7afe"
                        Label { id: countLbl; anchors.centerIn: parent
                                text: activeCount; color: "#ffffff"; font.pixelSize: 10 }
                    }
                }
                MouseArea {
                    id: navMa1
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: bottomPage = 0
                }
            }

            // 终端（底部显示终端面板）
            Rectangle {
                id: navTerm
                width: parent.width
                height: 38
                radius: 6
                readonly property bool active: bottomPage === 1
    onActiveChanged: termIco.requestPaint()
                color: navTerm.active ? "#e9f0ff" : (navMa2.containsMouse ? "#f2f6fc" : "transparent")
                Rectangle { width: 3; height: 20; radius: 1.5; color: navTerm.active ? "#3a7afe" : "transparent"
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    spacing: 8
                    Canvas {
                        id: termIco
                        width: 16; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = navTerm.active ? "#3a7afe" : "#5a6472"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.moveTo(3, 4); ctx.lineTo(8, 8); ctx.lineTo(3, 12)
                            ctx.moveTo(10, 12.5); ctx.lineTo(14, 12.5)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: "终端"; color: navTerm.active ? "#1d5fd6" : "#3a414a"
                            font.bold: navTerm.active }
                }
                MouseArea {
                    id: navMa2
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: toggleTerminal()
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.rightMargin: 8
        anchors.bottomMargin: 8
        anchors.leftMargin: 148
        spacing: 8

        // 连接栏（卡片）
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: connRow.implicitHeight + 16
            radius: 8
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"

            RowLayout {
                id: connRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                UiCombo {
                    id: savedCombo
                    Layout.preferredWidth: 190
                    displayText: {
                        if (currentIndex < 0)
                            return "已保存连接"
                        var m = settingsStore.connection(savedCombo.model[currentIndex])
                        return currentText + (m && m.user ? " (" + m.user + ")" : "")
                    }
                    onActivated: applySaved(index, true)
                    popup.onClosed: savedCombo.focus = false
                }
                ToolSeparator {
                    contentItem: Rectangle {
                        implicitWidth: 1
                        implicitHeight: 20
                        color: "#dde2e9"
                    }
                }

                Label { text: "主机"; color: "#5a6472" }
                UiInput {
                    id: hostField
                    Layout.preferredWidth: 150
                    placeholderText: "IP 或主机名"
                    onTextEdited: clearLoaded()
                }
                Label { text: "端口"; color: "#5a6472" }
                UiInput {
                    id: portField
                    Layout.preferredWidth: 60
                    text: "22"
                    onTextEdited: clearLoaded()
                }
                Label { text: "用户"; color: "#5a6472" }
                UiInput {
                    id: userField
                    Layout.preferredWidth: 110
                    placeholderText: "用户名"
                    onTextEdited: clearLoaded()
                }
                Label { text: "密码"; color: "#5a6472" }
                UiInput {
                    id: passField
                    Layout.preferredWidth: 130
                    echoMode: TextInput.Password
                    placeholderText: "密码"
                    onTextEdited: clearLoaded()
                }
                UiButton {
                    id: connectButton
                    Layout.preferredWidth: 84
                    text: connecting ? "连接中…" : (browse.connected ? "断开" : "连接")
                    primary: !browse.connected
                    danger: browse.connected
                    onClicked: {
                        if (connecting) { log("正在连接中，请稍候…"); return }
                        browse.connected ? doDisconnect() : doConnect()
                    }
                }
                Item { Layout.preferredWidth: 2 }
                UiCheck {
                    id: hiddenBox
                    text: "隐藏文件"
                    onToggled: {
                        localModel.showHidden = checked
                        remoteModel.showHidden = checked
                    }
                }
                Item { Layout.fillWidth: true }
                UiTool {
                    id: connManageBtn
                    text: "管理"
                    onClicked: connMenu.popup(connManageBtn, 0, connManageBtn.height + 4)
                }
                // 吸收窗口多余宽度，防止 RowLayout 把空隙摊进各控件之间
                Item { Layout.fillWidth: true }
            }
        }

        // 双栏
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            FilePane {
                id: localPane
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: localModel
                side: "local"
                title: "本机 (Local)"
                peerPane: remotePane
                onDropToPeer: startTransfer("local", "remote", paths)
                onOpenFile: openLocalPath(localPane.model.pathAt(index))
            }

            Rectangle { Layout.fillHeight: true; width: 1; color: "#d8dbe0" }

            FilePane {
                id: remotePane
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: remoteModel
                side: "remote"
                title: "远程 (Remote)"
                peerPane: localPane
                remoteReady: browse.connected
                onDropToPeer: startTransfer("remote", "local", paths)
                onOpenFile: openRemotePath(remotePane.model, index)
                onUploadBack: uploadOneBack(remotePane.model.pathAt(index))
            }
        }
    }

    // ---------- 底部：传输队列 + 终端 并排 + 状态栏（spec §6/§20/§24） ----------
    footer: Item {
        readonly property int bottomH: Math.max(200, Math.min(300, Math.round(root.height * 0.28)))
        implicitHeight: bottomH + 48

        ColumnLayout {
            id: bottomCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            TransferPanel {
                id: transferPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: bottomPage === 0
                model: transferListModel
                paused: root.transferPaused
                activeCount: root.activeCount
                doneCount: root.doneCount
                onPauseRequested: {
                    if (transferPaused) {
                        transferPaused = false
                        transfer.resumeTransfer()
                    } else {
                        transferPaused = true
                        transfer.pauseTransfer()
                    }
                }
                onAbortRequested: {
                    transferPaused = false
                    transfer.abortTransfer()
                }
                onCancelQueuedRequested: transfer.cancelQueued(label)
                onRetryRequested: retryTransfer(index)
                onDeleteRequested: deleteTransfer(index)
                onClearFinished: clearFinishedTasks()
                onUploadBackClicked: startUploadBack()
            }

            TerminalPanel {
                id: terminalPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: bottomPage === 1
                onCloseRequested: closeTerminal()
                onCommandRequested: shell.sendInput(line)
            }

            // 状态栏
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 26
                radius: 6
                color: "#ffffff"
                border.width: 1
                border.color: "#e3e7ee"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 8
                        Layout.preferredHeight: 8
                        radius: 4
                        color: browse.connected ? "#2fa356" : "#9aa3b0"
                    }
                    Label {
                        text: browse.connected
                              ? "已连接 " + browse.host + (browse.user.length ? " (" + browse.user + ")" : "")
                              : "未连接"
                        color: "#3a414a"
                        font.pixelSize: 12
                    }
                    Label {
                        visible: statusMsg !== ""
                        text: statusMsg
                        color: statusMsgColor
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Item { Layout.fillWidth: true; visible: statusMsg === "" }
                    Label {
                        text: activeCount > 0
                              ? activeCount + " 个传输任务 · 上传 " + Utils.formatBytes(upSpeed) + "/s · 下载 " + Utils.formatBytes(downSpeed) + "/s"
                              : "空闲"
                        color: "#7b8494"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // ---------- 回传冲突确认 ----------    // ---------- 回传冲突确认 ----------
    Dialog {
        id: backConflictDialog
        modal: true
        title: "远程文件已变更"
        padding: 14
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        property var entry: null
        property int remoteSize: 0

        function openFor(e, size) {
            entry = e
            remoteSize = size
            open()
        }

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Label {
            text: backConflictDialog.title
            font.pixelSize: 14
            font.bold: true
            color: "#2b3138"
            leftPadding: 14
            topPadding: 12
            bottomPadding: 4
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: backConflictDialog.close() }
            UiButton { primary: true; text: "仍要覆盖"; onClicked: {
                if (backConflictDialog.entry)
                    doUploadBack(backConflictDialog.entry)
                backConflictDialog.close()
            } }
        }
        Label {
            width: 340
            wrapMode: Text.Wrap
            color: "#3a414a"
            text: "远程文件「" + (backConflictDialog.entry ? backConflictDialog.entry.name : "") +
                  "」在打开后被其它途径修改过（当前 " +
                  Utils.formatBytes(backConflictDialog.remoteSize) + "，打开时 " +
                  Utils.formatBytes(backConflictDialog.entry ? backConflictDialog.entry.baselineSize : 0) +
                  "）。仍要用本地副本覆盖远程文件吗？"
        }
    }

    // ---------- 连接管理菜单（spec §8：低优先级操作收进二级菜单） ----------
    Menu {
        id: connMenu
        implicitWidth: 170
        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4
        background: Rectangle {
            radius: 8
            color: "#ffffff"
            border.width: 1
            border.color: "#dfe4ec"
        }
        MenuItem {
            text: "保存当前连接"
            onTriggered: saveDialog.openForSave()
        }
        MenuItem {
            text: "删除当前连接"
            enabled: savedCombo.currentIndex >= 0
            onTriggered: {
                var name = savedCombo.model[savedCombo.currentIndex]
                settingsStore.removeConnection(name)
                if (loadedConnection === name)
                    loadedConnection = ""
                refreshSaved()
                log("已删除连接 " + name)
            }
        }
        MenuItem {
            text: "新建连接"
            onTriggered: {
                if (browse.connected)
                    doDisconnect()
                hostField.text = ""
                portField.text = "22"
                userField.text = ""
                passField.text = ""
                clearLoaded()
                hostField.forceActiveFocus()
            }
        }
    }

    // ---------- 保存连接对话框 ----------
    Dialog {
        id: saveDialog
        modal: true
        title: "保存连接"
        padding: 14
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Item {
            implicitHeight: 48
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                spacing: 10
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                color: "#e8f0ff"
                Canvas {
                    anchors.centerIn: parent
                    width: 15; height: 15
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = "#3a7afe"
                        ctx.lineWidth = 1.8
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(2, 8.5); ctx.lineTo(2, 13.5); ctx.lineTo(13, 13.5); ctx.lineTo(13, 8.5)
                        ctx.moveTo(7.5, 1.5); ctx.lineTo(7.5, 9.5)
                        ctx.moveTo(4.5, 7); ctx.lineTo(7.5, 10); ctx.lineTo(10.5, 7)
                        ctx.stroke()
                    }
                    Component.onCompleted: requestPaint()
                }
            }
            Label {
                text: saveDialog.title
                font.pixelSize: 14
                font.bold: true
                color: "#2b3138"
                Layout.fillWidth: true
            }
        }
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: saveDialog.reject() }
            UiButton { primary: true; text: "保存"; onClicked: saveDialog.accept() }
        }

        ColumnLayout {
            spacing: 8
            UiInput {
                id: saveNameField
                Layout.preferredWidth: 260
                placeholderText: "连接名称（如：测试机）"
                onAccepted: saveDialog.accept()
            }
            UiCheck {
                id: savePassBox
                text: "记住密码（明文存于本机配置，仅自用）"
                checked: true
            }
        }
        onAccepted: {
            var name = saveNameField.text.trim()
            if (!name)
                name = hostField.text.trim()
            settingsStore.saveConnection(name, {
                name: name,
                host: hostField.text.trim(),
                port: portField.text,
                user: userField.text.trim(),
                password: savePassBox.checked ? passField.text : "",
                savePassword: savePassBox.checked
            })
            // 让下拉框立即选中刚保存的这条，并记为下次启动的默认连接
            loadedConnection = name
            settingsStore.setLastConnection(name)
            refreshSaved()
            log("已保存连接 " + name)
        }
        function openForSave() {
            saveNameField.text = hostField.text.trim()
            open()
            saveNameField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        refreshSaved()
        // 启动时自动载入上次使用的连接（没有记录就用第一条），把表单填好。
        // 这样下拉框里显示的名字直接点“连接”就能用，不用再去列表重选一遍
        var last = settingsStore.lastConnection()
        var idx = last && last.length ? savedCombo.model.indexOf(last) : -1
        if (idx < 0 && savedCombo.count > 0)
            idx = 0
        if (idx >= 0)
            applySaved(idx, false)
        var lp = settingsStore.lastLocalPath()
        localModel.setDir(lp && lp.length ? lp : settingsStore.homeDir())
        log("就绪。在左侧拖拽到右侧=上传，右侧拖到左侧=下载。")
    }

    Component.onDestruction: {
        if (localModel)
            settingsStore.setLastLocalPath(localModel.currentPath)
        if (remoteModel)
            settingsStore.setLastRemotePath(remoteModel.currentPath)
    }
}
