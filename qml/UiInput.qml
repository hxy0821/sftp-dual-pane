import QtQuick 2.11
import QtQuick.Controls 2.4

// 统一输入框：圆角、聚焦时蓝色描边
TextField {
    id: control

    font.pixelSize: 13
    color: "#2b3138"
    selectionColor: "#3a7afe"
    selectedTextColor: "#ffffff"
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
    selectByMouse: true

    background: Rectangle {
        implicitHeight: 30
        radius: 6
        color: "#ffffff"
        border.width: 1
        border.color: control.activeFocus ? "#3a7afe"
                    : control.hovered ? "#b9c4d2"
                    : "#d8dee7"
    }
}
