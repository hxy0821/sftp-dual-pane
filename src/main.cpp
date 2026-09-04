#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QByteArray>

#include <libssh2.h>

#include "dirmodel.h"
#include "browsethread.h"
#include "sftpclient.h"
#include "settingsstore.h"
#include "shellsession.h"
#include "transferthread.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    qputenv("QT_QUICK_CONTROLS_STYLE", QByteArrayLiteral("Fusion"));

    QGuiApplication app(argc, argv);
    QCoreApplication::setOrganizationName(QStringLiteral("selftools"));
    QCoreApplication::setApplicationName(QStringLiteral("sftp-dual-pane"));

    libssh2_init(0);

    qmlRegisterType<SftpClient>("App", 1, 0, "SftpClient");
    qmlRegisterType<DirModel>("App", 1, 0, "DirModel");
    qmlRegisterType<TransferThread>("App", 1, 0, "TransferThread");
    qmlRegisterType<BrowseThread>("App", 1, 0, "BrowseThread");
    qmlRegisterType<ShellSession>("App", 1, 0, "ShellSession");

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsStore"),
                                             SettingsStore::instance());
    engine.load(QUrl(QStringLiteral("qrc:/qml/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    const int ret = app.exec();
    libssh2_exit();
    return ret;
}
