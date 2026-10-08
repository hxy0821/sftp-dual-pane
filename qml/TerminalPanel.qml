import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11

// 终端面板（spec §19-23）：仅调整布局/容器/标题栏/折叠，终端核心逻辑不变
Item {
    id: panel

    property bool sessionRunning: false               // 由上层（ShellSession）同步
    property string statusText: "未连接"
    property color statusColor: "#8a93a0"

    signal closeRequested()
    signal commandRequested(string line)              // 终端输入行/控制字符 → ShellSession

    CardShadow { anchors.fill: parent; radius: 8; strength: 0.8 }

    Rectangle {
        id: termBg
        anchors.fill: parent
        radius: 8
        color: "#171b21"
        border.width: 1
        border.color: "#2c333d"
    }

    function appendOutput(text) { appendTermOutput(text) }
    function setConnected() {
        sessionRunning = true
        statusText = "已连接"
        statusColor = "#5fc178"
        termOut.remove(0, termOut.length)
        termInputStart = 0
        termView.stickBottom = true
        termView.contentY = 0
    }
    function setClosed(reason) {
        sessionRunning = false
        statusText = "已断开"
        statusColor = "#e06c6c"
    }
    function focusTerminal() { termOut.forceActiveFocus() }

    // 本地回显模型：远程已关闭回显（PTY ECHO=0），输入由终端可编辑区
    // 原生显示/退格；仅回车时整行提交。远程输出统一插入到“当前输入行”之前
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

    // 提交当前输入行（从 termInputStart 到末尾）给远程 shell
    function submitLine() {
        if (!sessionRunning)
            return
        var line = termOut.text.substring(termInputStart)
        termOut.insert(termOut.length, "\n")
        termInputStart = termOut.length
        termOut.cursorPosition = termOut.length
        commandRequested(line + "\r")
    }

    property int termInputStart: 0

    // 展开内容
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
                color: panel.statusColor
            }
            Label {
                text: panel.statusText
                color: panel.statusColor
            }
            Item { Layout.fillWidth: true }
            UiTool { dark: true; text: "清空"; onClicked: { termOut.remove(0, termOut.length); termInputStart = 0; termView.stickBottom = true; termView.contentY = 0 } }
            UiTool { dark: true; text: "关闭"; onClicked: panel.closeRequested() }
        }

        // 输出区：TextEdit 自身不滚动（超出会画到面板外），放进 Flickable；
        // 长行自动换行显示（不横向滚动），右侧固定留滚动条槽，避免滚动条压住文字
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: "#101419"
            clip: true

            Flickable {
                id: termView
                anchors.fill: parent
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: Math.max(height, termOut.contentHeight)

                // 粘底：由“用户操作”驱动判断（拖动/滚动条/按键），不看 contentY 的
                // 每次变化——TextEdit 内部的光标跟随也会直接改 contentY，不能误判为用户上翻
                property bool stickBottom: true

                function atEnd() {
                    return contentY >= Math.max(0, contentHeight - height) - 2
                }
                function scrollToEnd() {
                    contentY = Math.max(0, contentHeight - height)
                }
                function followOutput() {
                    if (stickBottom)
                        scrollToEnd()
                }
                function scrollBy(dy) {
                    var maxY = Math.max(0, contentHeight - height)
                    contentY = Math.max(0, Math.min(maxY, contentY + dy))
                    stickBottom = atEnd()
                }

                // 拖动/惯性滚动结束后重新判断是否贴底（程序性滚动不触发）
                onMovementEnded: stickBottom = atEnd()

                Connections {
                    target: termOut
                    onContentHeightChanged: termView.followOutput()
                }
                // 延迟兜底：内部光标跟随可能晚于文本更新执行，贴底状态下再校正一次
                Timer {
                    id: followTimer
                    interval: 120
                    onTriggered: termView.followOutput()
                }

                ScrollBar.vertical: ScrollBar {
                    id: vbar
                    policy: ScrollBar.AsNeeded
                    implicitWidth: 8
                    onPressedChanged: if (!pressed) termView.stickBottom = termView.atEnd()
                    contentItem: Rectangle {
                        implicitWidth: 8
                        radius: 4
                        color: vbar.pressed ? "#4d5763" : "#3a424d"
                    }
                    background: Rectangle { color: "transparent" }
                }

                // 本地回显模型：可打印字符由 TextEdit 原生插入（本地回显），
                // 回车时整行提交；退格由 TextEdit 原生处理，但禁止越过
                // 输入行起点（termInputStart），避免删掉提示符/历史输出。
                TextEdit {
                    id: termOut
                    width: termView.width - 10   // 右侧留出滚动条槽，避免滚动条压住文字
                    color: "#c9d3df"
                    font.family: "monospace"
                    font.pixelSize: 13
                    readOnly: !panel.sessionRunning
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    onTextChanged: {
                        cursorPosition = length
                        termView.followOutput()
                        followTimer.restart()
                    }

                    Keys.onPressed: {
                        // 视图滚动键：断开连接后也能翻看历史输出
                        if (event.key === Qt.Key_PageUp) {
                            event.accepted = true
                            termView.scrollBy(-(termView.height - 30))
                            return
                        }
                        if (event.key === Qt.Key_PageDown) {
                            event.accepted = true
                            termView.scrollBy(termView.height - 30)
                            return
                        }
                        if (event.key === Qt.Key_Up) {
                            event.accepted = true
                            termView.scrollBy(-20)
                            return
                        }
                        if (event.key === Qt.Key_Down) {
                            event.accepted = true
                            termView.scrollBy(20)
                            return
                        }
                        if (!panel.sessionRunning) {
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
                            panel.submitLine()
                        } else if (event.key === Qt.Key_Backspace) {
                            // 仅当输入行为空（光标在起点）时阻止，否则交 TextEdit 原生删除
                            if (termOut.cursorPosition <= termInputStart) {
                                event.accepted = true
                            }
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right ||
                                   event.key === Qt.Key_Home || event.key === Qt.Key_End ||
                                   event.key === Qt.Key_Delete || event.key === Qt.Key_Tab) {
                            // 简化模型：固定行尾编辑，禁用方向/删除/制表符
                            event.accepted = true
                        } else if (ctrl && event.key === Qt.Key_C) {
                            // 有选中文本时交给 TextEdit 复制，无选中才发送 SIGINT
                            if (termOut.selectedText.length === 0) {
                                event.accepted = true
                                panel.commandRequested("\x03")
                            }
                        } else if (ctrl && event.key === Qt.Key_D) {
                            event.accepted = true
                            panel.commandRequested("\x04")
                        } else if (ctrl && event.key === Qt.Key_Z) {
                            event.accepted = true
                            panel.commandRequested("\x1a")
                        } else if (ctrl && event.key === Qt.Key_L) {
                            event.accepted = true
                            panel.commandRequested("\x0c")
                        }
                        // 其它可打印字符：不拦截，由 TextEdit 原生插入（本地回显）
                    }
                }
            }
        }
    }
}
