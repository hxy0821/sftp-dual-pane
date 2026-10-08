import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11
import App 1.0

// 终端面板（spec §19-23）：标题栏/状态 + 自绘终端视图（src/terminalview.cpp）
Item {
    id: panel

    property bool sessionRunning: false               // 由上层（ShellSession）同步
    property string statusText: "未连接"
    property color statusColor: "#8a93a0"

    signal closeRequested()

    CardShadow { anchors.fill: parent; radius: 8; strength: 0.8 }

    Rectangle {
        id: termBg
        anchors.fill: parent
        radius: 8
        color: "#171b21"
        border.width: 1
        border.color: "#2c333d"
    }

    function setConnected() {
        sessionRunning = true
        statusText = "已连接"
        statusColor = "#5fc178"
        termView.resetSession()
        termView.setSessionActive(true)
        termView.forceActiveFocus()
    }
    function setClosed(reason) {
        sessionRunning = false
        statusText = "已断开"
        statusColor = "#e06c6c"
        termView.setSessionActive(false)
    }
    function focusTerminal() { termView.forceActiveFocus() }

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
            UiTool { dark: true; text: "清空"; onClicked: termView.clearBuffer() }
            UiTool { dark: true; text: "关闭"; onClicked: panel.closeRequested() }
        }

        // 输出区：TerminalView 自绘（ANSI 颜色/光标/回滚/选择复制）
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: "#101419"
            clip: true

            TerminalView {
                id: termView
                objectName: "terminalView"
                anchors.fill: parent
                anchors.margins: 4
            }
        }
    }
}
