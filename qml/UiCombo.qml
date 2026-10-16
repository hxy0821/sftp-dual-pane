import QtQuick 2.11
import QtQuick.Controls 2.4

// 统一下拉框：圆角 + 自绘箭头 + 圆角弹层
ComboBox {
    id: control

    font.pixelSize: 13
    implicitHeight: 30

    contentItem: Text {
        leftPadding: 12
        rightPadding: control.indicator.width + control.spacing
        text: control.displayText
        font: control.font
        color: "#E2E8F0"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Item {
        x: control.width - width - 10
        y: (control.height - height) / 2
        width: 12
        height: 8
        opacity: control.hovered || control.popup.visible ? 0.9 : 0.55

        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#94A3B8"
                ctx.lineWidth = 1.6
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(1, 1.5)
                ctx.lineTo(width / 2, height - 1.5)
                ctx.lineTo(width - 1, 1.5)
                ctx.stroke()
            }
        }
    }

    background: Rectangle {
        radius: 6
        color: "#131C31"
        border.width: 1
        border.color: control.popup.visible ? "#3B82F6"
                    : control.hovered ? "#334155"
                    : "#334155"
    }

    delegate: ItemDelegate {
        id: item
        width: parent ? parent.width : 0
        height: 28
        highlighted: control.highlightedIndex === index

        contentItem: Text {
            leftPadding: 8
            rightPadding: 8
            // ItemDelegate.text 不会被 ComboBox 自动填充，这里按 textRole/modelData 取值
            text: control.textRole
                  ? (Array.isArray(control.model) ? modelData[control.textRole]
                                                 : model[control.textRole])
                  : modelData
            font.pixelSize: 13
            color: control.highlightedIndex === index ? "#60A5FA" : "#E2E8F0"
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 5
            color: control.highlightedIndex === index ? "#1E293B" : "transparent"
        }
    }

    popup: Popup {
        y: control.height + 4
        width: Math.max(control.width, 200)
        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4

        background: Rectangle {
            radius: 8
            color: "#131C31"
            border.width: 1
            border.color: "#1E293B"
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            spacing: 1
        }
    }
}
