#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QByteArray>
#include <QIcon>

#include <libssh2.h>

#include "dirmodel.h"
#include "browsethread.h"
#include "sftpclient.h"
#include "settingsstore.h"
#include "openregistry.h"
#include "shellsession.h"
#include "transferthread.h"
#include "terminalview.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    qputenv("QT_QUICK_CONTROLS_STYLE", QByteArrayLiteral("Fusion"));

    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("selftools"));
    QCoreApplication::setApplicationName(QStringLiteral("sftp-dual-pane"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/packaging/sftp-dual-pane.svg")));

    libssh2_init(0);

    qmlRegisterType<SftpClient>("App", 1, 0, "SftpClient");
    qmlRegisterType<DirModel>("App", 1, 0, "DirModel");
    qmlRegisterType<TransferThread>("App", 1, 0, "TransferThread");
    qmlRegisterType<BrowseThread>("App", 1, 0, "BrowseThread");
    qmlRegisterType<ShellSession>("App", 1, 0, "ShellSession");
    qmlRegisterType<TerminalView>("App", 1, 0, "TerminalView");

    QQmlApplicationEngine engine;
    OpenRegistry openRegistry;
    engine.rootContext()->setContextProperty(QStringLiteral("openRegistry"), &openRegistry);
    engine.rootContext()->setContextProperty(QStringLiteral("settingsStore"),
                                             SettingsStore::instance());
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    // 终端视图与 ShellSession 直连：输出/输入走原始字节，不经 QML 字符串转换
    if (QObject *root = engine.rootObjects().first()) {
        auto *view = root->findChild<TerminalView *>(QStringLiteral("terminalView"));
        auto *shell = root->findChild<ShellSession *>(QStringLiteral("shell"));
        if (view && shell) {
            QObject::connect(shell, &ShellSession::outputReceived,
                             view, &TerminalView::processOutput);
            QObject::connect(view, &TerminalView::dataToSend,
                             shell, &ShellSession::sendInputBytes);
            QObject::connect(view, &TerminalView::terminalResized,
                             shell, &ShellSession::resizeTerminal);
            view->reportTerminalSize();
        } else {
            qWarning("终端数据管道未接通：terminalView/shell 未找到");
        }
    }

    const int ret = app.exec();
    libssh2_exit();
    return ret;
}
