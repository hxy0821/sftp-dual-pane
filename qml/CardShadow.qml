import QtQuick 2.11

// 轻量卡片阴影：三层低透明度圆角矩形叠加。
// 不用 QtGraphicalEffects——在 llvmpipe / 软件渲染后端下会失效或出现硬边。
// 用法：放在卡片背景之前、与其同尺寸（anchors.fill: cardBg）。
Item {
    id: shadow

    property real radius: 8
    property real strength: 1.0
    property color tint: "#0f1b2d"

    Rectangle {
        x: -6
        y: -3.5
        width: shadow.width + 12
        height: shadow.height + 12
        radius: shadow.radius + 6
        color: Qt.rgba(shadow.tint.r, shadow.tint.g, shadow.tint.b, 0.030 * shadow.strength)
    }
    Rectangle {
        x: -3
        y: -1.5
        width: shadow.width + 6
        height: shadow.height + 7
        radius: shadow.radius + 3
        color: Qt.rgba(shadow.tint.r, shadow.tint.g, shadow.tint.b, 0.045 * shadow.strength)
    }
    Rectangle {
        x: -1
        y: 0
        width: shadow.width + 2
        height: shadow.height + 3
        radius: shadow.radius + 1
        color: Qt.rgba(shadow.tint.r, shadow.tint.g, shadow.tint.b, 0.055 * shadow.strength)
    }
}
