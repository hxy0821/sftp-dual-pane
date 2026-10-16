import QtQuick 2.11
import QtQuick.Controls 2.4
import "utils.js" as Utils

// 统一按钮：primary=蓝色主按钮；danger=红色警示（描边样式）；icon=可选前置图标（Utils.drawIcon 名称）
Button {
    id: control

    property bool primary: false
    property bool danger: false
    property string iconName: ""

    readonly property color textColor: control.primary ? "#ffffff"
                                     : control.danger ? "#d5494e"
                                     : "#3a414a"

    font.pixelSize: 13
    implicitHeight: 30
    leftPadding: 16
    rightPadding: 16

    contentItem: Item {
        implicitWidth: btnRow.implicitWidth
        implicitHeight: btnRow.implicitHeight

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: control.iconName !== "" ? 6 : 0

            Canvas {
                id: btnIcon
                width: control.iconName !== "" ? 14 : 0
                height: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: control.iconName !== ""
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (control.iconName !== "")
                        Utils.drawIcon(ctx, control.iconName, width, height, control.textColor)
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: control
                    onIconNameChanged: btnIcon.requestPaint()
                    onTextColorChanged: btnIcon.requestPaint()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                font: control.font
                color: control.textColor
            }
        }
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
