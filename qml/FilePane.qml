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
    signal openFile(int index)   // 双击/菜单打开文件（本地直接打开，远程先下载到缓存）

    z: pane.dragActive ? 50 : 0
    color: "#ffffff"
    radius: 8
    border.width: 1
    border.color: "#e3e7ee"

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
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                radius: 4
                color: pane.side === "remote" ? "#2fa356" : "#3a7afe"
            }
            Label {
                text: pane.title
                font.bold: true
                color: "#2b3138"
            }
            UiTool {
                text: "上一级"
                onClicked: if (pane.model) pane.model.goUp()
            }
            UiInput {
                id: pathField
                Layout.fillWidth: true
                placeholderText: "路径"
                onEditingFinished: {
                    if (pane.model && text !== pane.model.currentPath)
                        pane.model.setDir(text)
                }
            }
            UiTool { text: "刷新"; onClicked: if (pane.model) pane.model.refresh() }
            UiTool { text: "新建"; onClicked: mkdirDialog.openFor() }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#eef1f4" }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: pane.model
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                id: vbar
                contentItem: Rectangle {
                    implicitWidth: 8
                    radius: 4
                    color: vbar.pressed ? "#98a2b0" : "#cbd3de"
                    visible: vbar.active
                }
            }

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
                height: 32
                radius: 6
                color: {
                    if (listView.currentIndex === index)
                        return "#e9f0ff"
                    if (pane.multiSet.indexOf(index) >= 0)
                        return "#f0f5ff"
                    if (ma.containsMouse)
                        return "#f3f6fb"
                    return index % 2 === 0 ? "#ffffff" : "#fafbfd"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    // 图标：文件夹用两块矩形拼形状，文件按扩展名配色
                    Item {
                        Layout.preferredWidth: 16
                        Layout.preferredHeight: 16

                        Item {
                            visible: model.isDir
                            anchors.fill: parent

                            Rectangle {
                                x: 0
                                y: 0
                                width: 9
                                height: 5
                                radius: 1
                                color: "#e9a52f"
                            }
                            Rectangle {
                                y: 3
                                width: 16
                                height: 12
                                radius: 3
                                color: "#f7b955"
                            }
                        }
                        Rectangle {
                            visible: !model.isDir
                            anchors.centerIn: parent
                            width: 12
                            height: 13
                            radius: 3
                            color: Utils.typeColor(model.name)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: model.name
                        elide: Text.ElideMiddle
                        font.bold: model.isDir
                        color: listView.currentIndex === index ? "#1d5fd6"
                             : model.isDir ? "#1a4e8a" : "#2b3138"
                    }
                    Label {
                        visible: !model.isDir
                        text: Utils.formatBytes(model.size)
                        font.pixelSize: 12
                        color: listView.currentIndex === index ? "#5a83d8" : "#8a93a0"
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
                        if (mouse.button !== Qt.LeftButton)
                            return
                        if (model.isDir)
                            pane.model.enter(index)
                        else
                            pane.openFile(index)
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
                color: "#9aa3b0"
            }
        }

        RowLayout {
            Label {
                text: (listView.count || 0) + " 项"
                color: "#8a93a0"
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
        radius: 8
        color: "#3a7afe"
        opacity: 0.94
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
        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4
        background: Rectangle {
            radius: 8
            color: "#ffffff"
            border.width: 1
            border.color: "#dfe4ec"
        }

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
            enabled: ctxMenu.row >= 0
            onTriggered: {
                if (pane.model.isDirAt(ctxMenu.row))
                    pane.model.enter(ctxMenu.row)
                else
                    pane.openFile(ctxMenu.row)
            }
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
        topPadding: 4
        bottomPadding: 4
        leftPadding: 4
        rightPadding: 4
        background: Rectangle {
            radius: 8
            color: "#ffffff"
            border.width: 1
            border.color: "#dfe4ec"
        }
        MenuItem { text: "新建文件夹"; onTriggered: mkdirDialog.openFor() }
        MenuItem { text: "新建文件"; onTriggered: newFileDialog.openFor() }
        MenuSeparator { }
        MenuItem { text: "刷新"; onTriggered: if (pane.model) pane.model.refresh() }
    }

    Dialog {
        id: mkdirDialog
        modal: true
        title: "新建文件夹"
        padding: 14
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Label {
            text: mkdirDialog.title
            font.pixelSize: 14
            font.bold: true
            color: "#2b3138"
            leftPadding: 14
            topPadding: 12
            bottomPadding: 4
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: mkdirDialog.reject() }
            UiButton { primary: true; text: "创建"; onClicked: mkdirDialog.accept() }
        }

        ColumnLayout {
            spacing: 10
            Label {
                text: "在当前目录下创建新文件夹"
                font.pixelSize: 13
                color: "#5a6472"
                wrapMode: Text.Wrap
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            Label {
                text: pane.model ? pane.model.currentPath : ""
                font.pixelSize: 11
                color: "#9aa3b0"
                elide: Text.ElideMiddle
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            UiInput {
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
        padding: 14
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Label {
            text: newFileDialog.title
            font.pixelSize: 14
            font.bold: true
            color: "#2b3138"
            leftPadding: 14
            topPadding: 12
            bottomPadding: 4
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: newFileDialog.reject() }
            UiButton { primary: true; text: "创建"; onClicked: newFileDialog.accept() }
        }

        ColumnLayout {
            spacing: 10
            Label {
                text: "在当前目录下创建空文件"
                font.pixelSize: 13
                color: "#5a6472"
                wrapMode: Text.Wrap
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            Label {
                text: pane.model ? pane.model.currentPath : ""
                font.pixelSize: 11
                color: "#9aa3b0"
                elide: Text.ElideMiddle
                Layout.preferredWidth: 340
                Layout.maximumWidth: 340
            }
            UiInput {
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
        padding: 14
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Label {
            text: renameDialog.title
            font.pixelSize: 14
            font.bold: true
            color: "#2b3138"
            leftPadding: 14
            topPadding: 12
            bottomPadding: 4
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: renameDialog.reject() }
            UiButton { primary: true; text: "重命名"; onClicked: renameDialog.accept() }
        }

        ColumnLayout {
            spacing: 8
            UiInput {
                id: renameField
                Layout.preferredWidth: 280
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
        padding: 14
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1
        property string message: ""

        background: Rectangle {
            radius: 10
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }
        header: Label {
            text: confirmDelete.title
            font.pixelSize: 14
            font.bold: true
            color: "#2b3138"
            leftPadding: 14
            topPadding: 12
            bottomPadding: 4
        }
        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            UiButton { text: "取消"; onClicked: confirmDelete.reject() }
            UiButton { danger: true; text: "删除"; onClicked: confirmDelete.accept() }
        }

        Label {
            width: 300
            wrapMode: Text.Wrap
            color: "#3a414a"
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
