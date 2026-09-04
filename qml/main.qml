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
    minimumWidth: 980
    minimumHeight: 600
    title: "双栏文件传输 - SFTP"

    property bool remoteReady: browse.connected
    property bool connecting: false
    property string logText: ""
    property string termStatusText: "未连接"
    property string termStatusColor: "#808080"
    property string remoteStart: {
        var p = settingsStore.lastRemotePath()
        return (p && p.length) ? p : "/"
    }

    function log(msg) {
        var t = new Date()
        var stamp = Utils.pad2(t.getHours()) + ":" + Utils.pad2(t.getMinutes()) + ":" + Utils.pad2(t.getSeconds())
        var line = "[" + stamp + "] " + msg
        logText = logText ? (logText + "\n" + line) : line
        if (logText.length > 8000)
            logText = logText.substring(logText.length - 8000)
    }

    function refreshSaved() {
        savedCombo.model = settingsStore.savedNames()
    }

    function doConnect() {
        var h = hostField.text.trim()
        if (!h) { log("✘ 请输入主机 IP / 主机名"); return }
        browse.host = h
        browse.port = parseInt(portField.text) || 22
        browse.user = userField.text.trim()
        browse.password = passField.text
        log("正在连接 " + browse.user + "@" + browse.host + ":" + browse.port + " …")
        connectButton.enabled = false
        browse.connectToHost(10000)
    }

    function doDisconnect() {
        transfer.disconnectRemote()
        if (shell.running)
            shell.closeSession()
        browse.disconnect()
        log("已断开连接")
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
        termInput.forceActiveFocus()
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

    // ---------- 后端对象 ----------
    BrowseThread {
        id: browse
        onConnectFinished: {
            connectButton.enabled = true
            if (ok) {
                log("✔ 已连接 " + browse.user + "@" + browse.host + ":" + browse.port)
                remoteModel.setDir(root.remoteStart)
            } else {
                log("✘ 连接失败: " + err)
            }
        }
        onDisconnected: {
            log("远程连接已断开")
        }
    }

    ShellSession {
        id: shell
        onOutputReceived: {
            termOut.insert(termOut.length, text)
            if (termOut.length > 100000)
                termOut.remove(0, termOut.length - 100000)
            termOut.cursorPosition = termOut.length
        }
        onSessionStarted: {
            termStatusText = "已连接"
            termStatusColor = "#7fae5a"
            log("终端已连接")
        }
        onSessionClosed: {
            termStatusText = "已断开"
            termStatusColor = "#c06060"
            log("终端已关闭: " + reason)
        }
    }

    TransferThread {
        id: transfer
        onTaskStarted: {
            progressLabel.text = label
        }
        onTaskFinished: {
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
        onAllFinished: {
            progressLabel.text = "空闲"
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

        // 连接栏
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ComboBox {
                id: savedCombo
                Layout.preferredWidth: 170
                displayText: currentIndex < 0 ? "已保存连接" : currentText
                onActivated: {
                    var m = settingsStore.connection(savedCombo.model[index])
                    if (!m || !m.host)
                        return
                    hostField.text = m.host
                    portField.text = m.port ? m.port.toString() : "22"
                    userField.text = m.user ? m.user : ""
                    passField.text = m.password ? m.password : ""
                    // 已连接其它主机时，先断开再连所选设备，实现一键切换
                    if (browse.connected)
                        doDisconnect()
                    doConnect()
                }
                popup.onClosed: savedCombo.focus = false
            }
            ToolButton { text: "保存"; onClicked: saveDialog.openForSave() }
            ToolButton {
                text: "删除"
                onClicked: {
                    if (savedCombo.currentIndex >= 0) {
                        settingsStore.removeConnection(savedCombo.model[savedCombo.currentIndex])
                        refreshSaved()
                    }
                }
            }
            ToolButton {
                text: "新建连接"
                onClicked: {
                    if (browse.connected)
                        doDisconnect()
                    hostField.text = ""
                    portField.text = "22"
                    userField.text = ""
                    passField.text = ""
                    savedCombo.currentIndex = -1
                    hostField.forceActiveFocus()
                }
            }

            ToolSeparator { }

            Label { text: "主机" }
            TextField {
                id: hostField
                Layout.preferredWidth: 150
                placeholderText: "IP 或主机名"
                selectByMouse: true
            }
            Label { text: "端口" }
            TextField {
                id: portField
                Layout.preferredWidth: 60
                text: "22"
                selectByMouse: true
            }
            Label { text: "用户" }
            TextField {
                id: userField
                Layout.preferredWidth: 110
                placeholderText: "用户名"
                selectByMouse: true
            }
            Label { text: "密码" }
            TextField {
                id: passField
                Layout.preferredWidth: 130
                echoMode: TextInput.Password
                placeholderText: "密码"
                selectByMouse: true
            }
            Button {
                id: connectButton
                text: browse.connected ? "断开" : "连接"
                highlighted: true
                onClicked: browse.connected ? doDisconnect() : doConnect()
            }
            CheckBox {
                id: hiddenBox
                text: "隐藏文件"
                onToggled: {
                    localModel.showHidden = checked
                    remoteModel.showHidden = checked
                }
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

    // ---------- 底部：进度 + 日志 + 终端 ----------
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
                Label {
                    id: progressLabel
                    text: "空闲"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Button {
                    text: termPanel.visible ? "关闭终端" : "终端"
                    onClicked: toggleTerminal()
                }
                Button {
                    text: logArea.visible ? "隐藏日志" : "日志"
                    onClicked: logArea.visible = !logArea.visible
                }
            }

            Rectangle {
                id: logResizeHandle
                visible: logArea.visible
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                color: "#c0c4ca"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SplitVCursor
                    property real startY: 0
                    property real startH: 0
                    onPressed: {
                        startH = logArea.height
                        startY = mapToItem(null, mouse.x, mouse.y).y
                    }
                    onPositionChanged: {
                        if (!pressed)
                            return
                        var cy = mapToItem(null, mouse.x, mouse.y).y
                        var nh = startH - (cy - startY)
                        logArea.Layout.preferredHeight = Math.max(40, Math.min(nh, 500))
                    }
                }
            }

            TextArea {
                id: logArea
                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                readOnly: true
                selectByMouse: true
                wrapMode: TextArea.Wrap
                text: root.logText
                color: "#d4d4d4"
                background: Rectangle { color: "#1e1e1e" }
                onTextChanged: cursorPosition = length
            }

            // 终端面板
            Rectangle {
                id: termPanel
                visible: false
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                color: "#141414"
                border.color: "#3a3a3a"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Label {
                            text: "终端"
                            color: "#d4d4d4"
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
                        Item { Layout.fillWidth: true }
                        ToolButton { text: "清空"; onClicked: termOut.remove(0, termOut.length) }
                        ToolButton { text: "关闭"; onClicked: closeTerminal() }
                    }

                    TextArea {
                        id: termOut
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        color: "#d4d4d4"
                        background: Rectangle { color: "#101010" }
                        font.family: "monospace"
                        font.pixelSize: 13
                        onTextChanged: cursorPosition = length
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "$"; color: "#7fae5a"; font.family: "monospace" }
                        TextField {
                            id: termInput
                            Layout.fillWidth: true
                            placeholderText: "输入命令，回车执行"
                            selectByMouse: true
                            font.family: "monospace"
                            onAccepted: {
                                if (shell.running) {
                                    shell.sendInput(text + "\r")
                                    termInput.text = ""
                                }
                            }
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
        standardButtons: Dialog.Save | Dialog.Cancel
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        ColumnLayout {
            spacing: 8
            TextField {
                id: saveNameField
                width: 240
                placeholderText: "连接名称（如：测试机）"
            }
            CheckBox {
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
