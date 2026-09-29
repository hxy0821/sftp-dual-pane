import QtQuick 2.11
import QtQuick.Controls 2.4
import "utils.js" as Utils

// 传输队列单行（spec §32：只展示任务状态，不含 SFTP 逻辑）
// 模型角色：taskId/label/name/upload/srcPath/dstDir/size/done/speed/eta/status/lastTs
// 列位置由上层传入的 cols 数组决定（与表头共用同一套坐标，保证逐列对齐）
Item {
    id: row

    property bool paused: false            // 全局暂停态（由上层传入，仅影响 running 行显示）
    property int taskId: 0                 // 任务唯一 id（取消按 id 精确匹配）
    property var cols: [10, 88, 900, 972, 1148, 1228, 1294, 1362]   // 默认列坐标（会被上层覆盖）

    signal pauseClicked()
    signal abortClicked(int taskId)
    signal cancelQueuedClicked(int taskId)
    signal retryClicked()
    signal deleteClicked()

    width: 400
    height: 48

    function cx(i) { return cols.length > i ? cols[i] : 0 }

    // 状态文案与配色
    readonly property string statusText: {
        if (status === "queued") return "等待中"
        if (status === "running") return paused ? "已暂停" : "传输中"
        if (status === "failed") return "传输失败"
        if (status === "cancelled") return "已中断"
        if (status === "done") return "已完成"
        return ""
    }
    readonly property color statusColor: {
        if (status === "running") return paused ? "#d99a2b" : "#3a7afe"
        if (status === "failed") return "#d5494e"
        if (status === "done") return "#2fa356"
        if (status === "cancelled") return "#8a93a0"
        return "#8a93a0"
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.bottomMargin: 3
        radius: 6
        color: rowMa.containsMouse ? "#f3f6fb" : "transparent"

        // 方向：图标 + 文字（列 0，宽 70）
        Row {
            x: row.cx(0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: status === "failed" ? "#fdeaea"
                     : status === "done" ? "#e6f6ec"
                     : status === "cancelled" ? "#eef1f5"
                     : upload ? "#e8f0ff" : "#e6f6ec"

                Text {
                    anchors.centerIn: parent
                    text: status === "failed" ? "\u00d7"
                         : status === "done" ? "\u2713"
                         : status === "cancelled" ? "\u2013"
                         : upload ? "\u2191" : "\u2193"
                    color: status === "failed" ? "#d5494e"
                         : status === "done" ? "#2fa356"
                         : status === "cancelled" ? "#8a93a0"
                         : upload ? "#3a7afe" : "#2fa356"
                    font.pixelSize: 14
                    font.bold: true
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: upload ? "上传" : "下载"
                color: "#5a6472"
                font.pixelSize: 12
            }
        }

        // 文件名（列 1，填满剩余宽度）
        Label {
            x: row.cx(1)
            width: row.cx(2) - 8 - x
            anchors.verticalCenter: parent.verticalCenter
            text: name
            elide: Text.ElideMiddle
            color: "#2b3138"
            font.pixelSize: 13
            ToolTip.visible: nameMa.containsMouse
            ToolTip.delay: 500
            ToolTip.text: name
            MouseArea { id: nameMa; anchors.fill: parent; hoverEnabled: true }
        }

        // 大小（列 2，右对齐）
        Label {
            x: row.cx(2)
            width: 64
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: size > 0 ? Utils.formatBytes(size) : "—"
            color: "#8a93a0"
            font.pixelSize: 12
        }

        // 进度：条 + 百分比（列 3，宽 168）
        Item {
            x: row.cx(3)
            width: 168
            anchors.verticalCenter: parent.verticalCenter
            height: 26

            TransferProgress {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: 42
                anchors.verticalCenter: parent.verticalCenter
                height: 10
                progress: size > 0 ? Math.min(1, done / size) : 0
                uploading: upload
                running: status === "running"
                paused: row.paused && status === "running"
                failed: status === "failed"
                cancelled: status === "cancelled"
                finished: status === "done"
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                horizontalAlignment: Text.AlignRight
                text: status === "done" ? "100%" : (size > 0 ? Math.round(done / size * 100) + "%" : "—")
                color: status === "failed" ? "#d5494e"
                     : status === "done" ? "#2fa356" : "#5a6472"
                font.pixelSize: 12
            }
        }

        // 速度（列 4，右对齐）
        Label {
            x: row.cx(4)
            width: 72
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: status === "running" ? Utils.formatBytes(speed) + "/s" : "—"
            color: "#5a6472"
            font.pixelSize: 12
        }

        // 剩余时间（列 5，右对齐）
        Label {
            x: row.cx(5)
            width: 58
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (status !== "running" || eta < 0)
                    return "—"
                var m = Math.floor(eta / 60)
                var s = Math.floor(eta % 60)
                return (m > 0 ? m + "分" : "") + s + "秒"
            }
            color: "#5a6472"
            font.pixelSize: 12
        }

        // 状态（列 6，左对齐）
        Label {
            x: row.cx(6)
            width: 60
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: statusText
            color: statusColor
            font.pixelSize: 12
        }

        // 操作（列 7，按钮组在操作列内水平居中）
        Item {
            x: row.cx(7)
            width: 100
            anchors.verticalCenter: parent.verticalCenter
            height: 26

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                UiTool {
                    visible: status === "running"
                    text: row.paused ? "继续" : "暂停"
                    onClicked: row.pauseClicked()
                }
                UiTool {
                    visible: status === "running"
                    text: "取消"
                    onClicked: row.abortClicked(row.taskId)
                }
                UiTool {
                    visible: status === "queued"
                    text: "取消"
                    onClicked: row.cancelQueuedClicked(row.taskId)
                }
                UiTool {
                    visible: status === "failed"
                    text: "重试"
                    onClicked: row.retryClicked()
                }
                UiTool {
                    visible: status === "cancelled"
                    text: "删除"
                    onClicked: row.deleteClicked()
                }
            }
        }
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
