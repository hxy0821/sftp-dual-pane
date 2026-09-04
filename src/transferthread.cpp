#include "transferthread.h"

#include <QDir>
#include <QFileInfo>

#include "sftpclient.h"
#include "pathutil.h"

TransferThread::TransferThread(QObject *parent) : QThread(parent) {}

TransferThread::~TransferThread()
{
    {
        QMutexLocker lock(&m_mutex);
        m_quit = true;
        m_queue.clear();
    }
    m_cond.wakeAll();
    if (isRunning())
        wait(15000);
}

void TransferThread::enqueueUpload(const QStringList &localPaths, const QString &remoteDir)
{
    {
        QMutexLocker lock(&m_mutex);
        for (const QString &p : localPaths)
            m_queue.enqueue({ true, p, remoteDir,
                              QStringLiteral("上传 %1").arg(QFileInfo(p).fileName()) });
    }
    m_cond.wakeOne();
    if (!isRunning())
        start();
}

void TransferThread::enqueueDownload(const QStringList &remotePaths, const QString &localDir)
{
    {
        QMutexLocker lock(&m_mutex);
        for (const QString &p : remotePaths)
            m_queue.enqueue({ false, p, localDir,
                              QStringLiteral("下载 %1").arg(QFileInfo(p).fileName()) });
    }
    m_cond.wakeOne();
    if (!isRunning())
        start();
}

void TransferThread::disconnectRemote()
{
    {
        QMutexLocker lock(&m_mutex);
        m_disconnectRequested = true;
        m_queue.clear();
    }
    m_cond.wakeAll();
}

void TransferThread::run()
{
    SftpClient client;
    while (true) {
        TransferTask task;
        bool haveTask = false;
        bool doClose = false;
        {
            QMutexLocker lock(&m_mutex);
            while (m_queue.isEmpty() && !m_quit && !m_disconnectRequested)
                m_cond.wait(&m_mutex);

            if (m_quit)
                break;
            if (m_disconnectRequested) {
                m_disconnectRequested = false;
                doClose = true;
            } else {
                task = m_queue.dequeue();
                haveTask = true;
            }
        }

        if (doClose) {
            client.close();
            continue;
        }
        if (!haveTask)
            continue;

        if (!client.isConnected()) {
            QString host, user, password;
            quint16 port;
            {
                QMutexLocker lock(&m_mutex);
                host = m_host;
                port = m_port;
                user = m_user;
                password = m_password;
            }
            client.setHost(host);
            client.setPort(port);
            client.setUser(user);
            client.setPassword(password);
            QString err;
            if (!client.connectInternal(15000, err)) {
                emit taskFinished(task.label, false, QStringLiteral("连接失败: ") + err);
                continue;
            }
        }
        runTask(task, client);
    }
    client.close();
    emit allFinished();
}

void TransferThread::runTask(const TransferTask &t, SftpClient &client)
{
    emit taskStarted(t.label);

    QString err;
    QVector<PlanItem> plan;
    qint64 total = 0;

    if (t.upload)
        collectLocalPlan(t.srcPath, t.dstDir, plan, total);
    else
        collectRemotePlan(client, t.srcPath, t.dstDir, plan, total, err);

    if (!err.isEmpty()) {
        emit taskFinished(t.label, false, QStringLiteral("扫描失败: ") + err);
        return;
    }

    // 先创建所有目标目录
    for (const PlanItem &p : plan) {
        if (!p.isDir)
            continue;
        if (t.upload) {
            if (!client.makeDir(p.remote, err)) {
                emit taskFinished(t.label, false, err);
                return;
            }
        } else {
            if (!QDir().mkpath(p.local)) {
                emit taskFinished(t.label, false, QStringLiteral("无法创建本地目录 ") + p.local);
                return;
            }
        }
    }

    // 再逐文件传输
    qint64 done = 0;
    int files = 0;
    for (const PlanItem &p : plan) {
        if (p.isDir)
            continue;
        qint64 r = -1;
        if (t.upload) {
            r = client.uploadFile(p.local, p.remote,
                                  [&](qint64 d, qint64) { emit progress(t.label, done + d, total); },
                                  err);
        } else {
            r = client.downloadFile(p.remote, p.local,
                                    [&](qint64 d, qint64) { emit progress(t.label, done + d, total); },
                                    err);
        }
        if (r < 0) {
            emit taskFinished(t.label, false,
                              QStringLiteral("传输失败 %1: %2")
                                  .arg(t.upload ? p.local : p.remote, err));
            return;
        }
        done += r;
        ++files;
    }

    emit taskFinished(t.label, true, QStringLiteral("%1 个文件，共 %2 字节").arg(files).arg(done));
    emit taskDone(t.upload, true);
}

void TransferThread::collectLocalPlan(const QString &localPath, const QString &remoteDir,
                                      QVector<PlanItem> &plan, qint64 &total)
{
    QFileInfo fi(localPath);
    if (!fi.exists())
        return;
    if (fi.isDir()) {
        const QString rd = joinRemotePath(remoteDir, fi.fileName());
        plan.append({ true, QString(), rd });
        QDir dir(localPath);
        const QFileInfoList list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot |
                                                     QDir::System,
                                                     QDir::Name);
        for (const QFileInfo &e : list)
            collectLocalPlan(e.absoluteFilePath(), rd, plan, total);
    } else {
        plan.append({ false, localPath, joinRemotePath(remoteDir, fi.fileName()) });
        total += fi.size();
    }
}

void TransferThread::collectRemotePlan(SftpClient &client, const QString &remotePath,
                                       const QString &localDir, QVector<PlanItem> &plan,
                                       qint64 &total, QString &err)
{
    FileEntry fi;
    if (!client.statFile(remotePath, fi, err))
        return;
    if (fi.isDir) {
        const QString ld = QDir(localDir).absoluteFilePath(fi.name);
        plan.append({ true, ld, QString() });
        QList<FileEntry> children = client.listDir(remotePath, true, err);
        if (!err.isEmpty())
            return;
        for (const FileEntry &c : children)
            collectRemotePlan(client, c.path, ld, plan, total, err);
        if (!err.isEmpty())
            return;
    } else {
        plan.append({ false, QDir(localDir).absoluteFilePath(fi.name), remotePath });
        total += fi.size;
    }
}
