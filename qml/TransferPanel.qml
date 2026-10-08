import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11
import "utils.js" as Utils

// 传输队列面板（spec §32）：任务列表 + 队列/已完成 Tab，只展示不含 SFTP 逻辑
// 列位置由 colPos 统一定义，表头与数据行共用同一套坐标，保证逐列对齐
Item {
    id: panel

    property alias model: listView.model
    property bool paused: false
    property int activeCount: 0
    property int doneCount: 0
    property int deadCount: 0    // 队列里已结束的记录（失败 / 已中断）

    signal pauseRequested()
    signal cancelRequested(int taskId)
    signal retryRequested(int index)
    signal deleteRequested(int index)
    signal clearFinished()
    signal clearDead()
    signal uploadBackClicked()

    property int currentTab: 0   // 0=传输队列 1=已完成

    // 共享列坐标：[方向70, 文件名fill, 大小64, 进度168, 速度72, 剩余58, 状态60, 操作100]
    readonly property var colPos: {
        var cw = width - 20               // 左右各留 10
        var x1 = 10 + 70 + 8              // 方向列之后
        var tail = 64 + 8 + 168 + 8 + 72 + 8 + 58 + 8 + 60 + 8 + 100
        var fill = cw - x1 - tail         // 文件名列宽度
        var xs = [10, x1, x1 + fill + 8]
        var acc = xs[2] + 64 + 8
        xs.push(acc); acc += 168 + 8
        xs.push(acc); acc += 72 + 8
        xs.push(acc); acc += 58 + 8
        xs.push(acc); acc += 60 + 8
        xs.push(acc)
        return xs                          // 8 个 x 坐标
    }

    CardShadow { anchors.fill: parent; radius: 8 }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 8
        color: "#ffffff"
        border.width: 1
        border.color: "#e3e7ee"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Tab 头
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                Layout.preferredWidth: queueTitle.implicitWidth + 16
                Layout.preferredHeight: 26
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: panel.currentTab === 0 ? "#e9f0ff" : "transparent"
                }
                Label {
                    id: queueTitle
                    anchors.centerIn: parent
                    text: "传输队列 (" + panel.activeCount + ")"
                    color: panel.currentTab === 0 ? "#1d5fd6" : "#5a6472"
                    font.bold: panel.currentTab === 0
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: panel.currentTab = 0 }
            }
            Item {
                Layout.preferredWidth: doneTitle.implicitWidth + 16
                Layout.preferredHeight: 26
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: panel.currentTab === 1 ? "#e9f0ff" : "transparent"
                }
                Label {
                    id: doneTitle
                    anchors.centerIn: parent
                    text: "已完成 (" + panel.doneCount + ")"
                    color: panel.currentTab === 1 ? "#1d5fd6" : "#5a6472"
                    font.bold: panel.currentTab === 1
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: panel.currentTab = 1 }
            }
            Item { Layout.fillWidth: true }
            UiButton {
                visible: openRegistry.dirtyCount > 0
                text: "上传修改(" + openRegistry.dirtyCount + ")"
                onClicked: panel.uploadBackClicked()
            }
            // 清空记录：队列页清失败/已中断，已完成页清完成记录
            UiTool {
                visible: panel.currentTab === 1 ? panel.doneCount > 0 : panel.deadCount > 0
                text: "清空记录"
                onClicked: panel.currentTab === 1 ? panel.clearFinished() : panel.clearDead()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#eef1f4" }

        // 列标题（与数据行共用 colPos，逐列同向对齐）
        Item {
            Layout.fillWidth: true
            height: 16

            Label { x: panel.colPos[0]; width: 70; horizontalAlignment: Text.AlignHCenter; text: "方向"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[1]; width: panel.colPos[2] - 8 - panel.colPos[1]; text: "文件名"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[2]; width: 64; horizontalAlignment: Text.AlignHCenter; text: "大小"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[3]; width: 126; horizontalAlignment: Text.AlignHCenter; text: "进度"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[4] - 2; width: 72; horizontalAlignment: Text.AlignHCenter; text: "速度"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[5] - 2; width: 58; horizontalAlignment: Text.AlignHCenter; text: "剩余时间"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[6]; width: 60; horizontalAlignment: Text.AlignHCenter; text: "状态"; color: "#8a93a0"; font.pixelSize: 11 }
            Label { x: panel.colPos[7]; width: 100; horizontalAlignment: Text.AlignHCenter; text: "操作"; color: "#8a93a0"; font.pixelSize: 11 }
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                id: vbar
                contentItem: Rectangle {
                    implicitWidth: 8
                    radius: 4
                    color: vbar.pressed ? "#98a2b0" : "#cbd3de"
                    visible: vbar.active
                }
            }

            delegate: TransferItem {
                width: listView.width
                height: visible ? 48 : 0
                visible: panel.currentTab === 0 ? status !== "done" : status === "done"
                taskId: model.taskId
                paused: panel.paused
                cols: panel.colPos
                onPauseClicked: panel.pauseRequested()
                onAbortClicked: panel.cancelRequested(taskId)
                onCancelQueuedClicked: panel.cancelRequested(taskId)
                onRetryClicked: panel.retryRequested(index)
                onDeleteClicked: panel.deleteRequested(index)
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: listView.count === 0

                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 36
                    height: 36
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        Utils.drawIcon(ctx, "inbox", width, height, "#c3ccd8")
                    }
                    Component.onCompleted: requestPaint()
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: panel.currentTab === 0 ? "暂无传输任务" : "暂无已完成记录"
                    color: "#9aa3b0"
                }
            }
        }
    }
}
