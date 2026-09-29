import QtQuick 2.11

// 传输进度条（spec §31：只负责进度/方向/流光/状态色，不含业务逻辑）
// - uploading: 流光方向（上传向右 / 下载向左）
// - running:   是否正在传输（控制流光动画）
// - paused:    动画冻结在当前位置，恢复后原地继续
// - failed/cancelled/finished: 红 / 灰 / 绿 状态色并停止流光
Rectangle {
    id: control

    property real progress: 0          // 0.0 ~ 1.0
    property bool uploading: true
    property bool running: false
    property bool paused: false
    property bool failed: false
    property bool cancelled: false
    property bool finished: false

    radius: 5
    clip: true
    color: failed ? "#f7dcdd" : "#e4e8ee"

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
             : control.cancelled ? "#a9b4c2"
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
            running: control.running && fill.width > 0
            paused: control.paused
        }

        Rectangle {
            width: 44
            height: fill.height * 2.6
            y: -(height - fill.height) / 2
            x: fill.streakX(0)
            rotation: 16
            opacity: control.failed || control.finished || control.cancelled ? 0 : 1
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
            opacity: control.failed || control.finished || control.cancelled ? 0 : 1
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.55) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
}
