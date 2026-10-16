import QtQuick 2.11
import QtQuick.Controls 2.4
import "utils.js" as Utils

// 统一按钮：primary=蓝色主按钮；danger=红色警示（描边样式）；icon=可选前置图标（Utils.drawIcon 名称）
Button {
    id: control

    property bool primary: false
    property bool danger: false
    property string iconName: ""

    readonly property color textColor: control.primary ? "#131C31"
                                     : control.danger ? "#F87171"
                                     : "#CBD5E1"

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
                return control.pressed ? "#2563EB" : control.hovered ? "#3B82F6" : "#3B82F6"
            if (control.pressed)
                return control.danger ? "#3B1D22" : "#1E293B"
            if (control.hovered)
                return control.danger ? "#3B1D22" : "#1E293B"
            return "#131C31"
        }
        border.width: control.primary ? 0 : 1
        border.color: {
            if (control.primary)
                return "transparent"
            if (control.danger)
                return control.hovered || control.pressed ? "#4A2429" : "#3B1D22"
            return control.hovered || control.pressed ? "#334155" : "#334155"
        }
    }
}
