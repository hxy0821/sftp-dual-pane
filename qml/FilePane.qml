import QtQuick 2.11
import QtQuick.Controls 2.4
import QtQuick.Layouts 1.11
import "utils.js" as Utils

Item {
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
    signal uploadBack(int index) // 右键“上传本地修改”（仅远程面板、有未回传修改时可见）
    signal transferSelected(bool toPeer) // 头部“上传选中/下载选中”按钮

    readonly property int selectedCount: {
        if (pane.multiSet.length > 0)
            return pane.multiSet.length
        return listView.currentIndex >= 0 ? 1 : 0
    }

    z: pane.dragActive ? 50 : 0

    // 卡片：阴影 + 白底（阴影为纯 QML 多层叠加，避免图形特效在后端差异下的异常）
    CardShadow { anchors.fill: parent; radius: 8 }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: 8
        color: "#ffffff"
        border.width: 1
        border.color: "#e3e7ee"
    }

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

        // 头部第一行：面板标识 + 路径
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // 圆角色块 + 方向箭头（本机=蓝↑ 上传 / 远程=绿↓ 下载）
            Rectangle {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: 6
                color: pane.side === "remote" ? "#e6f6ec" : "#e8f0ff"

                Canvas {
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = pane.side === "remote" ? "#2fa356" : "#3a7afe"
                        ctx.lineWidth = 1.7
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        if (pane.side === "remote") {
                            ctx.moveTo(6.5, 1.4); ctx.lineTo(6.5, 8.2)
                            ctx.moveTo(3.4, 5.1); ctx.lineTo(6.5, 8.2); ctx.lineTo(9.6, 5.1)
                        } else {
                            ctx.moveTo(6.5, 11.6); ctx.lineTo(6.5, 4.8)
                            ctx.moveTo(3.4, 7.9); ctx.lineTo(6.5, 4.8); ctx.lineTo(9.6, 7.9)
                        }
                        ctx.moveTo(2.2, 11.8); ctx.lineTo(10.8, 11.8)
                        ctx.stroke()
                    }
                    Component.onCompleted: requestPaint()
                }
            }
            Label {
                text: pane.title
                font.bold: true
                color: "#2b3138"
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
        }

        // 头部第二行：操作按钮（本机=上传选中 / 远程=下载选中）
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            UiAction {
                text: "上一级"
                iconName: "up"
                onClicked: if (pane.model) pane.model.goUp()
            }
            UiAction {
                text: "刷新"
                iconName: "refresh"
                onClicked: if (pane.model) pane.model.refresh()
            }
            UiAction {
                text: "新建"
                iconName: "newfolder"
                onClicked: mkdirDialog.openFor()
            }
            Item { Layout.fillWidth: true }
            UiAction {
                visible: pane.side === "local"
                text: "上传选中"
                iconName: "upload"
                enabled: pane.selectedCount > 0 && pane.remoteReady
                tint: enabled ? "#1d5fd6" : "#8a93a0"
                onClicked: pane.transferSelected(true)
            }
            UiAction {
                visible: pane.side === "remote"
                text: "下载选中"
                iconName: "download"
                enabled: pane.selectedCount > 0 && pane.remoteReady
                tint: enabled ? "#1d5fd6" : "#8a93a0"
                onClicked: pane.transferSelected(false)
            }
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
                            width: 13
                            height: 14
                            radius: 3
                            color: Utils.typeColor(model.name)

                            Text {
                                anchors.centerIn: parent
                                text: Utils.typeTag(model.name)
                                color: "#ffffff"
                                font.pixelSize: 7
                                font.bold: true
                            }
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

            Column {
                parent: listView
                anchors.centerIn: parent
                spacing: 12
                visible: listView.count === 0

                Canvas {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 40
                    height: 40
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        Utils.drawIcon(ctx,
                                       (pane.side === "remote" && !pane.remoteReady) ? "ban" : "folderopen",
                                       width, height, "#c3ccd8")
                    }
                    Component.onCompleted: requestPaint()
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (pane.side === "remote" && !pane.remoteReady) ? "未连接远程主机" : "（空目录）"
                    color: "#9aa3b0"
                }
            }
        }

        // 栏底统计：共 N 项 | 选中 M 项
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "共 " + (listView.count || 0) + " 项"
                color: "#8a93a0"
                font.pixelSize: 11
            }
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 9
                color: "#e3e7ee"
            }
            Label {
                text: "选中 " + pane.selectedCount + " 项"
                color: pane.selectedCount > 0 ? "#1d5fd6" : "#8a93a0"
                font.pixelSize: 11
            }
            Item { Layout.fillWidth: true }
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
        implicitWidth: 180
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
        MenuItem {
            text: "上传本地修改"
            visible: pane.side === "remote"
            height: visible ? implicitHeight : 0
            enabled: ctxMenu.row >= 0 && !pane.model.isDirAt(ctxMenu.row)
                     && openRegistry.isDirtyRemote(pane.model.pathAt(ctxMenu.row))
            onTriggered: if (ctxMenu.row >= 0) pane.uploadBack(ctxMenu.row)
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
        implicitWidth: 150
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
        padding: 16
        width: 420
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2

        background: Rectangle {
            radius: 12
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }

        header: Item {
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: "#e8f0ff"

                    Canvas {
                        anchors.centerIn: parent
                        width: 18; height: 14
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = "#3a7afe"
                            ctx.beginPath()
                            ctx.moveTo(1, 3); ctx.lineTo(6.5, 3); ctx.lineTo(8.5, 5.2); ctx.lineTo(1, 5.2)
                            ctx.closePath(); ctx.fill()
                            ctx.beginPath()
                            ctx.moveTo(1, 5.2); ctx.lineTo(17, 5.2)
                            ctx.quadraticCurveTo(18, 5.2, 18, 6.2); ctx.lineTo(18, 11.5)
                            ctx.quadraticCurveTo(18, 13.5, 16, 13.5); ctx.lineTo(3, 13.5)
                            ctx.quadraticCurveTo(1, 13.5, 1, 11.5)
                            ctx.closePath(); ctx.fill()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label { text: "新建文件夹"; font.pixelSize: 15; font.bold: true; color: "#2b3138" }
                    Label { text: "在当前目录下创建"; font.pixelSize: 12; color: "#8a93a0" }
                }
                Item { Layout.fillWidth: true }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "位置"; font.pixelSize: 11; color: "#9aa3b0" }
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    color: "#f5f7fa"
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: pane.model ? pane.model.currentPath : ""
                        font.pixelSize: 11
                        color: "#5a6472"
                        elide: Text.ElideMiddle
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "名称"; font.pixelSize: 11; color: "#9aa3b0" }
                UiInput {
                    id: mkdirField
                    Layout.fillWidth: true
                    placeholderText: "输入文件夹名称"
                    onAccepted: mkdirDialog.accept()
                }
            }
        }

        footer: Item {
            implicitHeight: 46
            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Item { Layout.fillWidth: true }
                UiButton { text: "取消"; onClicked: mkdirDialog.reject() }
                UiButton {
                    primary: true
                    text: "创建"
                    enabled: mkdirField.text.trim().length > 0
                    onClicked: mkdirDialog.accept()
                }
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
        padding: 16
        width: 420
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2

        background: Rectangle {
            radius: 12
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }

        header: Item {
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: "#e8f0ff"

                    Canvas {
                        anchors.centerIn: parent
                        width: 14; height: 16
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = "#5b8def"
                            ctx.beginPath()
                            ctx.moveTo(2, 2)
                            ctx.quadraticCurveTo(2, 1, 3, 1); ctx.lineTo(9, 1); ctx.lineTo(12, 4)
                            ctx.lineTo(12, 14)
                            ctx.quadraticCurveTo(12, 15, 11, 15); ctx.lineTo(3, 15)
                            ctx.quadraticCurveTo(2, 15, 2, 14)
                            ctx.closePath(); ctx.fill()
                            ctx.fillStyle = "#c7d8f7"
                            ctx.beginPath()
                            ctx.moveTo(9, 1); ctx.lineTo(12, 4); ctx.lineTo(9, 4)
                            ctx.closePath(); ctx.fill()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label { text: "新建文件"; font.pixelSize: 15; font.bold: true; color: "#2b3138" }
                    Label { text: "在当前目录下创建空文件"; font.pixelSize: 12; color: "#8a93a0" }
                }
                Item { Layout.fillWidth: true }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "位置"; font.pixelSize: 11; color: "#9aa3b0" }
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    color: "#f5f7fa"
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: pane.model ? pane.model.currentPath : ""
                        font.pixelSize: 11
                        color: "#5a6472"
                        elide: Text.ElideMiddle
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "名称"; font.pixelSize: 11; color: "#9aa3b0" }
                UiInput {
                    id: newFileField
                    Layout.fillWidth: true
                    placeholderText: "输入文件名称"
                    onAccepted: newFileDialog.accept()
                }
            }
        }

        footer: Item {
            implicitHeight: 46
            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Item { Layout.fillWidth: true }
                UiButton { text: "取消"; onClicked: newFileDialog.reject() }
                UiButton {
                    primary: true
                    text: "创建"
                    enabled: newFileField.text.trim().length > 0
                    onClicked: newFileDialog.accept()
                }
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
        padding: 16
        width: 420
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1

        background: Rectangle {
            radius: 12
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }

        header: Item {
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: "#e8f0ff"

                    Canvas {
                        anchors.centerIn: parent
                        width: 15; height: 15
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.strokeStyle = "#3a7afe"
                            ctx.lineWidth = 2.2
                            ctx.lineCap = "round"
                            ctx.beginPath(); ctx.moveTo(11.5, 3.5); ctx.lineTo(4.5, 10.5); ctx.stroke()
                            ctx.fillStyle = "#3a7afe"
                            ctx.beginPath()
                            ctx.moveTo(2.2, 13.8); ctx.lineTo(3.4, 10.4); ctx.lineTo(5.6, 12.6)
                            ctx.closePath(); ctx.fill()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label { text: "重命名"; font.pixelSize: 15; font.bold: true; color: "#2b3138" }
                    Label { text: "仅修改名称，内容不变"; font.pixelSize: 12; color: "#8a93a0" }
                }
                Item { Layout.fillWidth: true }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "名称"; font.pixelSize: 11; color: "#9aa3b0" }
                UiInput {
                    id: renameField
                    Layout.fillWidth: true
                    placeholderText: "新名称"
                    onAccepted: renameDialog.accept()
                }
            }
        }

        footer: Item {
            implicitHeight: 46
            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Item { Layout.fillWidth: true }
                UiButton { text: "取消"; onClicked: renameDialog.reject() }
                UiButton { primary: true; text: "重命名"; onClicked: renameDialog.accept() }
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
        padding: 16
        width: 420
        parent: pane
        x: (pane.width - width) / 2
        y: (pane.height - height) / 2
        property int row: -1
        property string itemPath: ""
        property string message: ""

        background: Rectangle {
            radius: 12
            color: "#ffffff"
            border.width: 1
            border.color: "#e3e7ee"
        }

        header: Item {
            implicitHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 20
                    color: "#fdeaea"
                    Text {
                        anchors.centerIn: parent
                        text: "\u00d7"
                        color: "#d5494e"
                        font.pixelSize: 22
                        font.bold: true
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label { text: "删除确认"; font.pixelSize: 15; font.bold: true; color: "#2b3138" }
                    Label { text: "此操作不可撤销"; font.pixelSize: 12; color: "#8a93a0" }
                }
                Item { Layout.fillWidth: true }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "位置"; font.pixelSize: 11; color: "#9aa3b0" }
                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 6
                    color: "#f5f7fa"
                    Label {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: Text.AlignVCenter
                        text: confirmDelete.itemPath
                        font.pixelSize: 11
                        color: "#5a6472"
                        elide: Text.ElideMiddle
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "操作"; font.pixelSize: 11; color: "#9aa3b0" }
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 388   // 固定内容宽度，避免 wrap 文本与 Dialog contentHeight 互相触发绑定环
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    color: "#3a414a"
                    text: confirmDelete.message
                }
            }
        }

        footer: Item {
            implicitHeight: 46
            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Item { Layout.fillWidth: true }
                UiButton { text: "取消"; onClicked: confirmDelete.reject() }
                UiButton { danger: true; text: "删除"; onClicked: confirmDelete.accept() }
            }
        }

        onAccepted: if (pane.model) pane.model.removeAt(confirmDelete.row)
        function openFor(row) {
            confirmDelete.row = row
            confirmDelete.itemPath = pane.model.pathAt(row)
            confirmDelete.message = "确定删除「" + pane.model.nameAt(row) + "」？" +
                                    (pane.model.isDirAt(row) ? "\n（目录将被递归删除）" : "")
            open()
        }
    }
}
