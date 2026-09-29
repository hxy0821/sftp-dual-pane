import QtQuick 2.11
import QtQuick.Controls 2.4

// 轻量文字按钮：浅色面板用默认配色，深色面板（终端）置 dark=true
ToolButton {
    id: control

    property bool dark: false

    font.pixelSize: 13
    implicitHeight: 28
    leftPadding: 10
    rightPadding: 10

    contentItem: Text {
        text: control.text
        font: control.font
        color: control.dark ? "#c9d3df" : "#3a414a"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: 6
        color: control.pressed ? (control.dark ? "#2a303a" : "#e2e9f4")
             : control.hovered ? (control.dark ? "#262c35" : "#eef2f8")
             : "transparent"
    }
}
