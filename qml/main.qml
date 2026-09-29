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
    minimumWidth: 1220
    minimumHeight: 620
    title: "双栏文件传输 - SFTP"
    color: "#eef1f5"
    font.pixelSize: 13

    property bool remoteReady: browse.connected
    property bool connecting: false
    property string statusMsg: ""
    property color statusMsgColor: "#7b8494"
    property string termStatusText: "未连接"
    property string termStatusColor: "#8a93a0"
    property int termInputStart: 0
    // 当前表单实际载入的已保存连接名；为空表示表单是手动输入的新连接。
    // 下拉框的高亮始终跟随它，保证“看到的名字”和“表单里的值”一致
    property string loadedConnection: ""
    property string remoteStart: {
        var p = settingsStore.lastRemotePath()
        return (p && p.length) ? p : "/"
    }

    // 底部单行状态消息：✘ 开头显示红色，✔ 开头显示绿色
    function log(msg) {
        statusMsg = msg
        if (msg.indexOf("✘") === 0)
            statusMsgColor = "#d5494e"
        else if (msg.indexOf("✔") === 0)
            statusMsgColor = "#2fa356"
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
        transfer.disconnectRemote()
        if (shell.running)
            shell.closeSession()
        browse.disconnect()
        log("已断开连接")
        // 断开连接会中断在途传输，进度条立即置红提示
        if (progressArea.active && !progressArea.finished) {
            progressArea.taskAborted()
            log("✘ 连接已断开，传输已中断")
        }
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

    // ---------- 终端 ----------
    function openTerminal() {
        if (!browse.connected) {
            log("✘ 未连接远程主机，无法打开终端")
            return
        }
        termPanel.visible = true
        if (!shell.running) {
            shell.host = browse.host
            shell.port = browse.port
            shell.user = browse.user
            shell.password = browse.password
            shell.startSession()
        }
        termOut.forceActiveFocus()
    }
    function closeTerminal() {
        if (shell.running)
            shell.closeSession()
        termPanel.visible = false
    }
    function toggleTerminal() {
        if (termPanel.visible)
            closeTerminal()
        else
            openTerminal()
    }

    // 本地回显模型：远程已关闭回显（PTY ECHO=0），输入由可编辑的 TextArea
    // 原生显示/退格；仅回车时整行提交。远程输出统一插入到“当前输入行”之前
    // （termInputStart 处），把用户正在敲的内容推到末尾。
    function appendTermOutput(t) {
        var i = 0
        while (i < t.length) {
            var c = t.charCodeAt(i)
            if (c === 8) { // \b：删除输出区最后一个字符
                if (termInputStart > 0) {
                    termOut.remove(termInputStart - 1, termInputStart)
                    termInputStart--
                }
                i++
            } else if (c === 13) { // \r
                if (i + 1 < t.length && t.charCodeAt(i + 1) === 10) { // \r\n
                    termOut.insert(termInputStart, "\n")
                    termInputStart++
                    i += 2
                } else {
                    i++ // 孤立的 \r：行重绘，忽略
                }
            } else if (c === 10) { // \n
                termOut.insert(termInputStart, "\n")
                termInputStart++
                i++
            } else {
                var start = i
                while (i < t.length) {
                    var cc = t.charCodeAt(i)
                    if (cc === 8 || cc === 13 || cc === 10)
                        break
                    i++
                }
                var s = t.substring(start, i)
                termOut.insert(termInputStart, s)
                termInputStart += s.length
            }
        }
        if (termOut.length > 100000) {
            var cut = termOut.length - 100000
            termOut.remove(0, cut)
            termInputStart -= cut
            if (termInputStart < 0)
                termInputStart = 0
        }
        termOut.cursorPosition = termOut.length
    }

    // 提交当前输入行（从 termInputStart 到末尾）给远程 shell。
    function submitLine() {
        if (!shell.running) {
            log("✘ 终端未连接，无法执行命令")
            return
        }
        var line = termOut.text.substring(termInputStart)
        termOut.insert(termOut.length, "\n")
        termInputStart = termOut.length
        termOut.cursorPosition = termOut.length
        shell.sendInput(line + "\r")
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
            if (progressArea.active && !progressArea.finished) {
                progressArea.taskAborted()
                log("✘ 连接已断开，传输已中断")
            } else {
                log("远程连接已断开")
            }
        }
    }

    ShellSession {
        id: shell
        onOutputReceived: {
            appendTermOutput(text)
        }
        onSessionStarted: {
            termStatusText = "已连接"
            termStatusColor = "#5fc178"
            log("终端已连接")
            // 新会话：清空终端并重置输入行起点
            termOut.remove(0, termOut.length)
            termInputStart = 0
        }
        onSessionClosed: {
            termStatusText = "已断开"
            termStatusColor = "#e06c6c"
            log("终端已关闭: " + reason)
        }
    }

    TransferThread {
        id: transfer
        onTaskStarted: {
            progressArea.beginTask(label, upload)
            log(label)
        }
        onProgress: progressArea.setProgress(done, total)
        onTaskFinished: {
            if (ok) {
                progressArea.taskSucceeded()
                log("✔ " + label + " — " + message)
            } else {
                if (message.indexOf("已中断") >= 0)
                    progressArea.taskAborted()
                else
                    progressArea.taskFailed()
                log("✘ " + label + " — " + message)
            }
        }
        onTaskDone: {
            if (ok) {
                if (upload)
                    remoteModel.refresh()
                else
                    localModel.refresh()
            }
        }
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
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
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
                    displayText: currentIndex < 0 ? "已保存连接" : currentText
                    onActivated: applySaved(index, true)
                    popup.onClosed: savedCombo.focus = false
                }
                UiTool { text: "保存"; onClicked: saveDialog.openForSave() }
                UiTool {
                    text: "删除"
                    onClicked: {
                        if (savedCombo.currentIndex >= 0) {
                            var name = savedCombo.model[savedCombo.currentIndex]
                            settingsStore.removeConnection(name)
                            if (loadedConnection === name)
                                loadedConnection = ""
                            refreshSaved()
                        }
                    }
                }
                UiTool {
                    text: "新建连接"
                    onClicked: {
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
            }
        }
    }

    // ---------- 底部：传输进度 + 终端 ----------
    footer: Item {
        implicitHeight: footerCol.implicitHeight + footerCol.anchors.topMargin + footerCol.anchors.bottomMargin
        ColumnLayout {
            id: footerCol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TransferProgress {
                    id: progressArea
                    Layout.fillWidth: true
                    visible: active
                    onTogglePause: {
                        if (paused) {
                            paused = false
                            transfer.resumeTransfer()
                        } else {
                            paused = true
                            transfer.pauseTransfer()
                        }
                    }
                    onAbortClicked: {
                        progressArea.taskAborted()
                        transfer.abortTransfer()
                    }
                }
                Item { Layout.fillWidth: true; visible: !progressArea.visible }

                UiButton {
                    text: termPanel.visible ? "关闭终端" : "终端"
                    onClicked: toggleTerminal()
                }
            }

            Label {
                visible: statusMsg !== ""
                text: statusMsg
                color: statusMsgColor
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // 终端面板
            Rectangle {
                id: termPanel
                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                radius: 8
                color: "#171b21"
                border.width: 1
                border.color: "#2c333d"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label {
                            text: "终端"
                            color: "#d9e1ea"
                            font.bold: true
                        }
                        Rectangle {
                            width: 8
                            height: 8
                            radius: 4
                            color: termStatusColor
                        }
                        Label {
                            text: termStatusText
                            color: termStatusColor
                        }
                        Label {
                            text: "· 直接敲键盘输入命令，回车执行"
                            color: "#78828e"
                            font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                        UiTool { dark: true; text: "清空"; onClicked: { termOut.remove(0, termOut.length); termInputStart = 0 } }
                        UiTool { dark: true; text: "关闭"; onClicked: closeTerminal() }
                    }

                    TextArea {
                        id: termOut
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readOnly: !shell.running
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        color: "#c9d3df"
                        background: Rectangle {
                            radius: 6
                            color: "#101419"
                        }
                        font.family: "monospace"
                        font.pixelSize: 13
                        onTextChanged: cursorPosition = length

                        // 本地回显模型：可打印字符由 TextArea 原生插入（本地回显），
                        // 回车时整行提交；退格由 TextArea 原生处理，但禁止越过
                        // 输入行起点（termInputStart），避免删掉提示符/历史输出。
                        Keys.onPressed: {
                            if (!shell.running) {
                                event.accepted = true
                                return
                            }
                            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                            if ((event.modifiers & Qt.AltModifier) !== 0) {
                                event.accepted = true
                                return
                            }
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                event.accepted = true
                                submitLine()
                            } else if (event.key === Qt.Key_Backspace) {
                                // 仅当输入行为空（光标在起点）时阻止，否则交 TextArea 原生删除
                                if (termOut.cursorPosition <= termInputStart) {
                                    event.accepted = true
                                }
                            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right ||
                                       event.key === Qt.Key_Home || event.key === Qt.Key_End ||
                                       event.key === Qt.Key_Up || event.key === Qt.Key_Down ||
                                       event.key === Qt.Key_Delete || event.key === Qt.Key_Tab) {
                                // 简化模型：固定行尾编辑，禁用方向/删除/制表符
                                event.accepted = true
                            } else if (ctrl && event.key === Qt.Key_C) {
                                event.accepted = true
                                shell.sendInput("\x03")
                            } else if (ctrl && event.key === Qt.Key_D) {
                                event.accepted = true
                                shell.sendInput("\x04")
                            } else if (ctrl && event.key === Qt.Key_Z) {
                                event.accepted = true
                                shell.sendInput("\x1a")
                            } else if (ctrl && event.key === Qt.Key_L) {
                                event.accepted = true
                                shell.sendInput("\x0c")
                            }
                            // 其它可打印字符：不拦截，由 TextArea 原生插入（本地回显）
                        }
                    }
                }
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
        header: Label {
            text: saveDialog.title
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
