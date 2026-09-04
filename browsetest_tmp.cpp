#include "browsethread.h"
#include <libssh2.h>
#include <QCoreApplication>
#include <QTimer>
#include <cstdio>

int main(int argc, char **argv){
    QCoreApplication app(argc, argv);
    libssh2_init(0);

    BrowseThread b;
    bool fired = false;
    bool ok = true;
    QString err;
    QObject::connect(&b, &BrowseThread::connectFinished,
                     [&](bool o, const QString &e){ fired = true; ok = o; err = e; });

    b.setHost("10.255.255.1");  // 不可达黑洞地址
    b.setPort(22);
    b.setUser("x");
    b.setPassword("x");
    b.connectToHost(3000);  // 3 秒超时

    QTimer t;
    int ticks = 0;
    QObject::connect(&t, &QTimer::timeout, [&](){
        ticks++;
        fprintf(stderr, "tick=%d fired=%d connected=%d\n", ticks, fired?1:0, b.isConnected()?1:0);
        if (fired || ticks >= 16) { b.disconnect(); app.quit(); }
    });
    t.start(500);
    app.exec();
    fprintf(stderr, "FINAL fired=%d ok=%d err=%s\n", fired?1:0, ok?1:0, err.toUtf8().constData());
    return 0;
}
