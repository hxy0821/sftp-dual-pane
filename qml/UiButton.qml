import QtQuick 2.11
import QtQuick.Controls 2.4

// 统一按钮：primary=蓝色主按钮；danger=红色警示（描边样式）
Button {
    id: control

    property bool primary: false
    property bool danger: false

    font.pixelSize: 13
    implicitHeight: 30
    leftPadding: 16
    rightPadding: 16

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.primary ? "#ffffff"
             : control.danger ? "#d5494e"
             : "#3a414a"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 6
        color: {
            if (control.primary)
                return control.pressed ? "#2e63d6" : control.hovered ? "#5589ff" : "#3a7afe"
            if (control.pressed)
                return control.danger ? "#fbecec" : "#e2e9f4"
            if (control.hovered)
                return control.danger ? "#fdf4f4" : "#f2f6fc"
            return "#ffffff"
        }
        border.width: control.primary ? 0 : 1
        border.color: {
            if (control.primary)
                return "transparent"
            if (control.danger)
                return control.hovered || control.pressed ? "#e5b1b3" : "#eccdce"
            return control.hovered || control.pressed ? "#b9c4d2" : "#d8dee7"
        }
    }
}
