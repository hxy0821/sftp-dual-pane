import QtQuick 2.11
import QtQuick.Controls 2.4

// 统一复选框：圆角选中框 + 蓝色勾选态
CheckBox {
    id: control

    font.pixelSize: 13
    spacing: 6

    indicator: Rectangle {
        implicitWidth: 16
        implicitHeight: 16
        x: control.leftPadding
        y: control.height / 2 - height / 2
        radius: 4
        color: control.checked ? "#3a7afe" : "#ffffff"
        border.width: 1
        border.color: control.checked ? "#3a7afe"
                    : control.hovered ? "#b9c4d2"
                    : "#c6cfd9"

        Text {
            anchors.centerIn: parent
            visible: control.checked
            text: "\u2713"
            color: "#ffffff"
            font.pixelSize: 11
            font.bold: true
        }
    }

    contentItem: Text {
        text: control.text
        font: control.font
        color: "#3a414a"
        leftPadding: control.indicator.width + control.spacing
        verticalAlignment: Text.AlignVCenter
    }
}
