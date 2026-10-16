import QtQuick 2.11
import QtQuick.Controls 2.4

// 统一输入框：圆角、聚焦时蓝色描边
TextField {
    id: control

    font.pixelSize: 13
    color: "#E2E8F0"
    selectionColor: "#3B82F6"
    selectedTextColor: "#131C31"
    leftPadding: 10
    rightPadding: 10
    topPadding: 6
    bottomPadding: 6
    selectByMouse: true

    background: Rectangle {
        implicitHeight: 30
        radius: 6
        color: "#131C31"
        border.width: 1
        border.color: control.activeFocus ? "#3B82F6"
                    : control.hovered ? "#334155"
                    : "#334155"
    }
}
