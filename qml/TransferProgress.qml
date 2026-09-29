import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11

// 传输进度条（对应 进度条UI.md 设计）：
//  - 上传流光向右滚动，下载向左滚动
//  - 暂停：动画冻结在当前位置；继续：原地恢复
//  - 失败：整体变红、停止流光；完成：变绿后自动收起
RowLayout {
    id: control

    property bool active: false        // 是否有任务在展示
    property bool uploading: true
    property bool paused: false
    property bool failed: false
    property bool aborted: false       // 被用户中断或因断开连接而终止
    property bool finished: false
    property real progress: 0          // 0.0 ~ 1.0
    property string name: ""           // 当前文件名

    signal togglePause()
    signal abortClicked()

    function beginTask(label, upload) {
        hideTimer.stop()
        name = label.replace(/^(上传|下载)\s*/, "")
        uploading = upload
        progress = 0
        paused = false
        failed = false
        aborted = false
        finished = false
        active = true
    }

    function setProgress(done, total) {
        if (total > 0)
            progress = Math.min(1, done / total)
    }

    function taskSucceeded() {
        progress = 1
        paused = false
        finished = true
        hideTimer.interval = 2500
        hideTimer.restart()
    }

    function taskFailed() {
        paused = false
        failed = true
        // 红色状态只停留 3 秒，避免一直挂在界面上影响心情
        hideTimer.interval = 3000
        hideTimer.restart()
    }

    function taskAborted() {
        paused = false
        failed = true
        aborted = true
        hideTimer.interval = 3000
        hideTimer.restart()
    }

    spacing: 10

    // 结束态自动收起：完成 2.5s，中断/失败 3s（左下角状态文字不受影响）
    Timer {
        id: hideTimer
        onTriggered: {
            control.finished = false
            control.failed = false
            control.aborted = false
            control.active = false
        }
    }

    // 状态圆标
    Rectangle {
        Layout.preferredWidth: 26
        Layout.preferredHeight: 26
        radius: 13
        color: control.failed ? "#fdeaea"
             : control.finished ? "#e6f6ec"
             : control.paused ? "#eef1f5"
             : control.uploading ? "#e8f0ff" : "#e6f6ec"

        // 圆头箭头（Canvas 手绘，替代字体字形，粗细均匀拐角圆润）
        Canvas {
            anchors.centerIn: parent
            width: 12
            height: 14
            visible: !control.paused && !control.failed && !control.finished && control.uploading
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#3a7afe"
                ctx.lineWidth = 2.4
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(6, 12.6)
                ctx.lineTo(6, 2.2)
                ctx.moveTo(2.4, 5.8)
                ctx.lineTo(6, 2.2)
                ctx.lineTo(9.6, 5.8)
                ctx.stroke()
            }
            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()
        }
        Canvas {
            anchors.centerIn: parent
            width: 12
            height: 14
            visible: !control.paused && !control.failed && !control.finished && !control.uploading
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#2fa356"
                ctx.lineWidth = 2.4
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(6, 1.4)
                ctx.lineTo(6, 11.8)
                ctx.moveTo(2.4, 8.2)
                ctx.lineTo(6, 11.8)
                ctx.lineTo(9.6, 8.2)
                ctx.stroke()
            }
            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()
        }
        Item {
            anchors.centerIn: parent
            visible: control.paused && !control.failed && !control.finished
            width: 8
            height: 10
            Rectangle { x: 0; width: 2.6; height: 10; radius: 1; color: "#8a93a0" }
            Rectangle { x: 5.4; width: 2.6; height: 10; radius: 1; color: "#8a93a0" }
        }
        Text {
            anchors.centerIn: parent
            visible: control.failed
            text: "\u00d7"
            color: "#d5494e"
            font.pixelSize: 17
            font.bold: true
        }
        Text {
            anchors.centerIn: parent
            visible: control.finished && !control.failed
            text: "\u2713"
            color: "#2fa356"
            font.pixelSize: 13
            font.bold: true
        }
    }

    Label {
        Layout.preferredWidth: 150
        text: control.aborted ? "已中断" + (control.name ? " · " + control.name : "")
             : control.failed ? "传输失败" + (control.name ? " · " + control.name : "")
             : control.finished ? "传输完成"
             : control.paused ? "已暂停 · " + control.name
             : (control.uploading ? "上传中 · " : "下载中 · ") + control.name
        color: control.failed ? "#d5494e" : control.finished ? "#2fa356" : "#2b3138"
        elide: Text.ElideRight
    }

    // 进度条 + 流光
    Rectangle {
        id: track
        Layout.fillWidth: true
        height: 10
        radius: 5
        color: control.failed ? "#f7dcdd" : "#e4e8ee"

        Rectangle {
            id: fill
            x: 0
            y: 0
            height: parent.height
            width: control.progress > 0
                   ? Math.max(parent.height, control.progress * parent.width) : 0
            radius: 5
            clip: true
            color: control.failed ? "#e5484d"
                 : control.finished ? "#2fa356" : "#3a7afe"

            // phase 在 0~1 间循环推进；暂停用 Animation.paused 冻结，恢复后原地继续
            property real phase: 0
            readonly property real span: Math.max(parent.width, 1) + 120

            function streakX(offset) {
                var t = (phase * span + offset) % span
                return (control.uploading ? t : span - t) - 60
            }

            NumberAnimation on phase {
                from: 0
                to: 1
                duration: 2200
                loops: Animation.Infinite
                running: control.active && fill.width > 0
                         && !control.failed && !control.finished
                paused: control.paused
            }

            Rectangle {
                width: 44
                height: fill.height * 2.6
                y: -(height - fill.height) / 2
                x: fill.streakX(0)
                rotation: 16
                opacity: control.failed || control.finished ? 0 : 1
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                width: 44
                height: fill.height * 2.6
                y: -(height - fill.height) / 2
                x: fill.streakX(fill.span / 2)
                rotation: 16
                opacity: control.failed || control.finished ? 0 : 1
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
    }

    Label {
        Layout.preferredWidth: 40
        text: Math.round(control.progress * 100) + "%"
        color: control.failed ? "#d5494e" : control.finished ? "#2fa356" : "#5a6472"
        font.pixelSize: 12
        horizontalAlignment: Text.AlignRight
    }

    // 暂停 / 继续按钮
    Button {
        implicitWidth: 28
        implicitHeight: 28
        enabled: control.active && !control.failed && !control.finished
        onClicked: control.togglePause()

        background: Rectangle {
            radius: 14
            color: control.pressed ? "#e2e9f4" : control.hovered ? "#f2f6fc" : "#ffffff"
            border.width: 1
            border.color: !control.enabled ? "#e4e8ee"
                        : control.hovered || control.pressed ? "#b9c4d2" : "#d8dee7"
        }
        contentItem: Item {
            Item {
                anchors.centerIn: parent
                width: 8
                height: 10
                visible: !control.paused
                opacity: control.enabled ? 1 : 0.4
                Rectangle { x: 0; width: 2.6; height: 10; radius: 1; color: "#5a6472" }
                Rectangle { x: 5.4; width: 2.6; height: 10; radius: 1; color: "#5a6472" }
            }
            Canvas {
                anchors.centerIn: parent
                width: 12
                height: 12
                visible: control.paused
                opacity: control.enabled ? 1 : 0.4
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = "#5a6472"
                    ctx.beginPath()
                    ctx.moveTo(2, 1)
                    ctx.lineTo(11, 6)
                    ctx.lineTo(2, 11)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }

    // 中断按钮
    Button {
        implicitWidth: 28
        implicitHeight: 28
        enabled: control.active && !control.failed && !control.finished
        onClicked: control.abortClicked()

        background: Rectangle {
            radius: 14
            color: control.pressed ? "#fbecec" : control.hovered ? "#fdf4f4" : "#ffffff"
            border.width: 1
            border.color: !control.enabled ? "#e4e8ee"
                        : control.hovered || control.pressed ? "#e5b1b3" : "#d8dee7"
        }
        contentItem: Item {
            opacity: control.enabled ? 1 : 0.4
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 2
                color: control.hovered || control.pressed ? "#d5494e" : "#5a6472"
            }
        }
    }
}
