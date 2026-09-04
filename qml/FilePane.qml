import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11
import "utils.js" as Utils

Rectangle {
    id: pane

    property var model: null
    property string side: "local"          // "local" | "remote"
    property string title: ""
    property var peerPane: null
    property bool remoteReady: false       // 远程面板：是否已连接
    property bool dragActive: false
    property var multiSet: []
    property string ghostText: ""

    signal dropToPeer(var paths)

    z: pane.dragActive ? 50 : 0
    color: "#ffffff"
    border.color: "#d8dbe0"

    function clearMulti() { pane.multiSet = [] }
    function toggleMulti(i) {
        var arr = pane.multiSet.slice()
        var idx = arr.indexOf(i)
        if (idx >= 0)
            arr.splice(idx, 1)
        else
            arr.push(i)
        pane.multiSet = arr
    }
    function selectedPaths() {
        var out = []
        if (pane.multiSet.length > 0) {
            for (var i = 0; i < pane.multiSet.length; i++)
                out.push(pane.model.pathAt(pane.multiSet[i]))
        } else if (listView.currentIndex >= 0) {
            out.push(pane.model.pathAt(listView.currentIndex))
        }
        return out
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Label {
                text: pane.title
                font.bold: true
                color: pane.side === "remote" ? "#0a8a86" : "#3366aa"
            }
            ToolButton {
                text: "上一级"
                onClicked: if (pane.model) pane.model.goUp()
            }
            TextField {
                id: pathField
                Layout.fillWidth: true
                selectByMouse: true
                placeholderText: "路径"
                onEditingFinished: {
                    if (pane.model && text !== pane.model.currentPath)
                        pane.model.setDir(text)
                }
            }
            ToolButton { text: "刷新"; onClicked: if (pane.model) pane.model.refresh() }
            ToolButton { text: "新建"; onClicked: mkdirDialog.openFor() }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#e2e5e9" }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: pane.model
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            MouseArea {
                id: emptyArea
                anchors.fill: parent
                z: -1
                acceptedButtons: Qt.RightButton
                onClicked: {
                    if (mouse.button === Qt.RightButton) {
                        var cp = pane.mapFromItem(listView, mouse.x, mouse.y)
                        emptyMenu.x = cp.x
                        emptyMenu.y = cp.y
                        emptyMenu.open()
                    }
                }
            }

            delegate: Rectangle {
                width: listView.width
                height: 34
                color: {
                    if (listView.currentIndex === index)
                        return "#2f6fdb"
                    if (pane.multiSet.indexOf(index) >= 0)
                        return "#cfe0f7"
                    return index % 2 === 0 ? "#ffffff" : "#f7f8fa"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                        width: 12; height: 12; radius: 2
                        color: model.isDir ? "#e8a33d" : "#9aa5b1"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: model.name
                        elide: Text.ElideMiddle
                        font.bold: model.isDir
                        color: listView.currentIndex === index ? "white"
                                                               : (model.isDir ? "#1a4e8a" : "#24292e")
                    }
                    Label {
                        visible: !model.isDir
                        text: Utils.formatBytes(model.size)
                        font.pixelSize: 12
                        color: listView.currentIndex === index ? "#dce6f5" : "#6a737d"
                    }
                }

                ToolTip.visible: ma.containsMouse
                ToolTip.delay: 600
                ToolTip.text: model.path + (model.isDir ? "" : "\n" + Utils.formatBytes(model.size) +
                                   "  " + Utils.formatTime(model.mtime))

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    preventStealing: true
                    property bool isDragging: false
                    property real startX: 0
                    property real startY: 0

                    onPressed: {
                        if (mouse.button === Qt.RightButton)
                            return
                        startX = mouse.x
                        startY = mouse.y
                        isDragging = false
                        if (mouse.modifiers & Qt.ControlModifier) {
                            pane.toggleMulti(index)
                        } else {
                            listView.currentIndex = index
                            pane.multiSet = []
                        }
                    }

                    onPositionChanged: {
                        if (!ma.pressed || !(mouse.buttons & Qt.LeftButton))
                            return
                        var dx = mouse.x - startX
                        var dy = mouse.y - startY
                        if (!isDragging && (dx * dx + dy * dy) > 144) {
                            var paths = pane.selectedPaths()
                            if (paths.length === 0)
                                return
                            isDragging = true
                            pane.dragActive = true
                            pane.ghostText = (paths.length === 1 ? paths[0].split("/").pop()
                                                                 : paths.length + " 个文件")
                            ghost.visible = true
                        }
                        if (isDragging) {
                            var p = pane.mapFromItem(ma, mouse.x, mouse.y)
                            ghost.x = p.x - ghost.width / 2
                            ghost.y = p.y - ghost.height - 10
                        }
                    }

                    onReleased: {
                        if (!isDragging)
                            return
                        isDragging = false
                        pane.dragActive = false
                        ghost.visible = false
                        if (pane.peerPane && pane.side !== pane.peerPane.side) {
                            var pp = ma.mapToItem(pane.peerPane, mouse.x, mouse.y)
                            if (pp.x >= 0 && pp.y >= 0 &&
                                pp.x <= pane.peerPane.width && pp.y <= pane.peerPane.height) {
                                pane.dropToPeer(pane.selectedPaths())
                            }
                        }
                    }

                    onDoubleClicked: {
                        if (mouse.button === Qt.LeftButton && model.isDir)
                            pane.model.enter(index)
                    }

                    onClicked: {
                        if (mouse.button === Qt.RightButton) {
                            ctxMenu.row = index
                            var cp = pane.mapFromItem(ma, mouse.x, mouse.y)
                            ctxMenu.x = cp.x
                            ctxMenu.y = cp.y
                            ctxMenu.open()
                        }
                    }
                }
            }

            Label {
                parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
                visible: listView.count === 0
                text: (pane.side === "remote" && !pane.remoteReady) ? "未连接远程主机" : "（空目录）"
                color: "#999999"
            }
        }

        RowLayout {
            Label {
                text: (listView.count || 0) + " 项"
                color: "#888888"
                font.pixelSize: 11
            }
        }
    }

    // 拖拽时的浮动提示
    Rectangle {
        id: ghost
        visible: false
        z: 999
        width: 160
        height: 32
        radius: 5
        color: "#2d7dd2"
        opacity: 0.92
        Label {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: "white"
            text: pane.ghostText
            elide: Text.ElideMiddle
        }
    }

    Connections {
        target: pane.model
        enabled: pane.model !== null
        onPathChanged: pathField.text = pane.model.currentPath
    }

    Component.onCompleted: {
        if (pane.model)
            pathField.text = pane.model.currentPath
    }

    Menu {
        id: ctxMenu
        property int row: -1

        MenuItem {
            text: pane.side === "remote" ? "下载到本地" : "上传到远程"
            enabled: pane.side === "local" ? true : pane.remoteReady
            onTriggered: {
                if (ctxMenu.row >= 0)
                    pane.dropToPeer([pane.model.pathAt(ctxMenu.row)])
            }
        }
        MenuItem {
            text: "打开"
            enabled: ctxMenu.row >= 0 && pane.model.isDirAt(ctxMenu.row)
            onTriggered: pane.model.enter(ctxMenu.row)
        }
        MenuSeparator { }
        MenuItem {
            text: "重命名"
            enabled: ctxMenu.row >= 0
            onTriggered: renameDialog.openFor(ctxMenu.row)
        }
        MenuItem {
            text: "删除"
            enabled: ctxMenu.row >= 0
            onTriggered: confirmDelete.openFor(ctxMenu.row)
        }
        MenuSeparator { }
        MenuItem { text: "新建文件夹"; onTriggered: mkdirDialog.openFor() }
        MenuItem { text: "新建文件"; onTriggered: newFileDialog.openFor() }
        MenuItem { text: "刷新"; onTriggered: if (pane.model) pane.model.refresh() }
    }

    Menu {
        id: emptyMenu
        MenuItem { text: "新建文件夹"; onTriggered: mkdirDialog.openFor() }
        MenuItem { text: "新建文件"; onTriggered: newFileDialog.openFor() }
        MenuSeparator { }
        MenuItem { text: "刷新"; onTriggered: if (pane.model) pane.model.refresh() }
    }

    Dialog {
        id: mkdirDialog
        modal: true
        title: "新建文件夹"
        standardButtons: Dialog.Ok | Dialog.Cancel
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        ColumnLayout {
            spacing: 10
            Label {
                text: "在当前目录下创建新文件夹"
                font.pixelSize: 13
                color: "#555555"
                wrapMode: Text.Wrap
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            Label {
                text: pane.model ? pane.model.currentPath : ""
                font.pixelSize: 11
                color: "#999999"
                elide: Text.ElideMiddle
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            TextField {
                id: mkdirField
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
                placeholderText: "文件夹名称"
                onAccepted: mkdirDialog.accept()
            }
        }
        onAccepted: if (pane.model) pane.model.makeDir(mkdirField.text)
        function openFor() {
            mkdirField.text = ""
            open()
            mkdirField.forceActiveFocus()
        }
    }

    Dialog {
        id: newFileDialog
        modal: true
        title: "新建文件"
        standardButtons: Dialog.Ok | Dialog.Cancel
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        ColumnLayout {
            spacing: 10
            Label {
                text: "在当前目录下创建空文件"
                font.pixelSize: 13
                color: "#555555"
                wrapMode: Text.Wrap
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            Label {
                text: pane.model ? pane.model.currentPath : ""
                font.pixelSize: 11
                color: "#999999"
                elide: Text.ElideMiddle
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            TextField {
                id: newFileField
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
                placeholderText: "文件名称"
                onAccepted: newFileDialog.accept()
            }
        }
        onAccepted: if (pane.model) pane.model.makeFile(newFileField.text)
        function openFor() {
            newFileField.text = ""
            open()
            newFileField.forceActiveFocus()
        }
    }

    Dialog {
        id: renameDialog
        modal: true
        title: "重命名"
        standardButtons: Dialog.Ok | Dialog.Cancel
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1
        ColumnLayout {
            spacing: 8
            TextField {
                id: renameField
                width: 260
                placeholderText: "新名称"
                onAccepted: renameDialog.accept()
            }
        }
        onAccepted: if (pane.model) pane.model.renameAt(renameDialog.row, renameField.text)
        function openFor(row) {
            renameDialog.row = row
            renameField.text = pane.model.nameAt(row)
            open()
            renameField.forceActiveFocus()
            renameField.selectAll()
        }
    }

    Dialog {
        id: confirmDelete
        modal: true
        title: "删除确认"
        standardButtons: Dialog.Yes | Dialog.No
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1
        property string message: ""
        Label {
            width: 300
            wrapMode: Text.Wrap
            text: confirmDelete.message
        }
        onAccepted: if (pane.model) pane.model.removeAt(confirmDelete.row)
        function openFor(row) {
            confirmDelete.row = row
            confirmDelete.message = "确定删除「" + pane.model.nameAt(row) + "」？" +
                                    (pane.model.isDirAt(row) ? "\n（目录将被递归删除）" : "")
            open()
        }
    }
}
