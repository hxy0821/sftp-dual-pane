import QtQuick 2.11

// 路径面包屑：🏠 seg › seg › seg
//  · 每段可点击，直接跳转到该级目录；当前段高亮加粗
//  · 双击（段上或空白处）切回手动输入：Enter 提交、Esc 取消
//  · 远程面板传 hostBadge（如 uos@10.20.8.135），路径最前显示主机徽章
//  · 路径过长时内容可横向拖动，并自动滚到末尾（当前目录始终可见）
Item {
    id: root

    property var dirModel: null       // DirModel：读 currentPath、调 setDir
    property string hostBadge: ""     // 非空时显示主机徽章（仅远程面板传）
    property bool editing: false      // 是否处于手动输入模式

    implicitHeight: 30

    readonly property string currentPath: dirModel ? dirModel.currentPath : ""
    readonly property var segModel: buildSegs(currentPath)

    // 路径 → 分段数组：[{name:"🏠", path:"/"}, {name:"var", path:"/var"}, ...]
    function buildSegs(p) {
        var segs = [{ name: "🏠", path: "/" }]
        if (!p || p === "/")
            return segs
        var parts = p.split("/")
        var acc = ""
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length === 0)
                continue
            acc += "/" + parts[i]
            segs.push({ name: parts[i], path: acc })
        }
        return segs
    }

    function jumpTo(p) {
        if (dirModel && p && p !== currentPath)
            dirModel.setDir(p)
    }

    function enterEdit() {
        editing = true
        editField.text = currentPath
        editField.forceActiveFocus()
        editField.selectAll()
    }

    function commitEdit() {
        if (!editing)
            return
        editing = false
        var t = editField.text.trim()
        if (t.length > 0 && t !== currentPath)
            jumpTo(t)
    }

    function cancelEdit() {
        editing = false
    }

    // 面包屑显示模式
    Rectangle {
        id: crumbBg
        anchors.fill: parent
        radius: 6
        color: "#ffffff"
        border.width: 1
        border.color: crumbHover.hovered ? "#b9c4d2" : "#d8dee7"
        visible: !root.editing

        // 背景层：空白处双击进入编辑（段在其上层，自行处理点击）
        MouseArea {
            id: crumbHover
            anchors.fill: parent
            hoverEnabled: true
            onDoubleClicked: root.enterEdit()
        }

        // 主机徽章：绿色小圆点 + 主机名，强化“这是远端”的空间感
        Row {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            visible: root.hostBadge.length > 0

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: "#2fa356"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hostBadge
                color: "#2fa356"
                font.pixelSize: 11
                font.bold: true
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 13
                color: "#e3e7ee"
            }
        }

        Flickable {
            id: flick
            anchors.left: badge.visible ? badge.right : parent.left
            anchors.leftMargin: badge.visible ? 7 : 8
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            contentWidth: crumbRow.width
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            onContentWidthChanged: scrollToEnd()
            onWidthChanged: scrollToEnd()

            function scrollToEnd() {
                contentX = Math.max(0, contentWidth - width)
            }

            // 内容背景：空白处双击进入编辑
            MouseArea {
                width: Math.max(flick.contentWidth, flick.width)
                height: flick.height
                z: -1
                onDoubleClicked: root.enterEdit()
            }

            Row {
                id: crumbRow
                height: flick.height
                spacing: 3

                Repeater {
                    model: root.segModel

                    delegate: Row {
                        id: segDelegate
                        height: flick.height
                        spacing: 3
                        readonly property bool isLast: index === root.segModel.length - 1

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: index > 1        // 🏠 与第一级目录之间不显示分隔符
                            text: "›"
                            color: "#b6bfcc"
                            font.pixelSize: 12
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            radius: 5
                            width: segText.implicitWidth + 12
                            color: (segMa.containsMouse && !segDelegate.isLast) ? "#eef3fb" : "transparent"

                            Text {
                                id: segText
                                anchors.centerIn: parent
                                text: modelData.name
                                color: segDelegate.isLast ? "#1a4e8a" : "#3a414a"
                                font.pixelSize: 12
                                font.bold: segDelegate.isLast
                            }

                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.jumpTo(modelData.path)
                                onDoubleClicked: root.enterEdit()
                            }
                        }
                    }
                }
            }
        }
    }

    // 编辑模式：手动输入路径（与原输入框行为一致）
    UiInput {
        id: editField
        anchors.fill: parent
        visible: root.editing
        placeholderText: "路径"
        onAccepted: root.commitEdit()
        onEditingFinished: root.commitEdit()
        Keys.onEscapePressed: {
            root.cancelEdit()
            event.accepted = true
        }
    }
}
