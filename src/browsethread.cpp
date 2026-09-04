#include "browsethread.h"

#include <QVariantMap>

#include "sftpclient.h"
#include "fileentry.h"

static QVariantList entriesToVariant(const QList<FileEntry> &list)
{
    QVariantList out;
    out.reserve(list.size());
    for (const FileEntry &e : list) {
        QVariantMap m;
        m.insert(QStringLiteral("name"), e.name);
        m.insert(QStringLiteral("path"), e.path);
        m.insert(QStringLiteral("isDir"), e.isDir);
        m.insert(QStringLiteral("size"), QVariant::fromValue<qint64>(e.size));
        m.insert(QStringLiteral("mtime"), QVariant::fromValue<qint64>(e.mtime));
        out.append(m);
    }
    return out;
}

BrowseThread::BrowseThread(QObject *parent) : QThread(parent) {}

BrowseThread::~BrowseThread()
{
    enqueue({ OpQuit, {}, {} });
    if (isRunning())
        wait(5000);
}

void BrowseThread::enqueue(const Cmd &c)
{
    {
        QMutexLocker l(&m_mutex);
        m_queue.enqueue(c);
    }
    m_cond.wakeOne();
    if (!isRunning() && c.op != OpQuit)
        start();
}

void BrowseThread::connectToHost(int timeoutMs)
{
    Cmd c;
    c.op = OpConnect;
    c.timeoutMs = timeoutMs;
    c.host = m_host;
    c.port = m_port;
    c.user = m_user;
    c.password = m_password;
    enqueue(c);
}

void BrowseThread::disconnect()
{
    enqueue({ OpDisconnect, {}, {} });
}

void BrowseThread::listDir(const QString &path, bool showHidden)
{
    enqueue({ OpList, path, {}, showHidden });
}

void BrowseThread::makeDir(const QString &path)
{
    enqueue({ OpMkdir, path, {} });
}

void BrowseThread::makeFile(const QString &path)
{
    enqueue({ OpMkfile, path, {} });
}

void BrowseThread::removeEntry(const QString &path)
{
    enqueue({ OpRemove, path, {} });
}

void BrowseThread::renameEntry(const QString &oldPath, const QString &newPath)
{
    enqueue({ OpRename, oldPath, newPath });
}

void BrowseThread::run()
{
    SftpClient client;

    while (true) {
        Cmd c;
        {
            QMutexLocker l(&m_mutex);
            while (m_queue.isEmpty())
                m_cond.wait(&m_mutex);
            c = m_queue.dequeue();
        }

        if (c.op == OpQuit)
            break;

        QString err;
        switch (c.op) {
        case OpConnect: {
            client.setHost(c.host);
            client.setPort(c.port);
            client.setUser(c.user);
            client.setPassword(c.password);
            const bool ok = client.connectInternal(c.timeoutMs, err);
            if (m_connected != ok) {
                m_connected = ok;
                emit connectedChanged();
            }
            emit connectFinished(ok, err);
            break;
        }
        case OpList: {
            QVariantList entries;
            if (client.isConnected())
                entries = entriesToVariant(client.listDir(c.a, c.flag, err));
            else
                err = QStringLiteral("未连接");
            emit listed(c.a, entries, err);
            break;
        }
        case OpMkdir: {
            const bool ok = client.makeDir(c.a, err);
            emit opFinished(QStringLiteral("mkdir"), ok, err);
            break;
        }
        case OpMkfile: {
            const bool ok = client.createFile(c.a, err);
            emit opFinished(QStringLiteral("mkfile"), ok, err);
            break;
        }
        case OpRemove: {
            const bool ok = client.removeEntry(c.a, err);
            emit opFinished(QStringLiteral("remove"), ok, err);
            break;
        }
        case OpRename: {
            const bool ok = client.renameEntry(c.a, c.b, err);
            emit opFinished(QStringLiteral("rename"), ok, err);
            break;
        }
        case OpDisconnect: {
            client.close();
            if (m_connected) {
                m_connected = false;
                emit connectedChanged();
            }
            emit disconnected();
            break;
        }
        default:
            break;
        }
    }

    client.close();
}
