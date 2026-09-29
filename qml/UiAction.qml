import QtQuick 2.11
import QtQuick.Controls 2.4
import "utils.js" as Utils

// 轻量「图标 + 文字」按钮：图标由 Utils.drawIcon 按名称绘制，随 tint 变色
ToolButton {
    id: control

    property string iconName: ""
    property color tint: "#3a414a"
    property bool dark: false

    implicitHeight: 28
    font.pixelSize: 13
    leftPadding: 8
    rightPadding: 10
    hoverEnabled: true
    opacity: enabled ? 1.0 : 0.4

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row
            anchors.centerIn: parent
            spacing: control.text !== "" ? 5 : 0

            Canvas {
                id: ico
                width: 15
                height: 15
                anchors.verticalCenter: parent.verticalCenter
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    Utils.drawIcon(ctx, control.iconName, width, height, control.tint)
                }
                Component.onCompleted: requestPaint()
                Connections {
                    target: control
                    onTintChanged: ico.requestPaint()
                    onIconNameChanged: ico.requestPaint()
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: control.text !== ""
                text: control.text
                color: control.tint
                font: control.font
            }
        }
    }

    background: Rectangle {
        radius: 6
        color: control.pressed ? (control.dark ? "#2a303a" : "#e2e9f4")
             : control.hovered ? (control.dark ? "#262c35" : "#eef2f8")
             : "transparent"
    }
}
