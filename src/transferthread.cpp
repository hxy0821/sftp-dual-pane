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

void TransferThread::enqueueDownload(const QStringList &remotePaths, const QString &localDir,
                                     bool openAfter)
{
    {
        QMutexLocker lock(&m_mutex);
        const QString verb = openAfter ? QStringLiteral("打开") : QStringLiteral("下载");
        for (const QString &p : remotePaths)
            m_queue.enqueue({ false, p, localDir,
                              QStringLiteral("%1 %2").arg(verb, QFileInfo(p).fileName()),
                              openAfter });
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
        m_abortRequested = true;   // 断开连接时同时中断在途传输
        m_queue.clear();
    }
    m_cond.wakeAll();
}

void TransferThread::abortTransfer()
{
    QMutexLocker lock(&m_mutex);
    m_abortRequested = true;
    m_paused = false;          // 暂停中也允许中断
    m_queue.clear();
    m_cond.wakeAll();
}

bool TransferThread::abortRequested()
{
    QMutexLocker lock(&m_mutex);
    return m_abortRequested;
}

void TransferThread::pauseTransfer()
{
    QMutexLocker lock(&m_mutex);
    m_paused = true;
}

void TransferThread::resumeTransfer()
{
    QMutexLocker lock(&m_mutex);
    m_paused = false;
    m_cond.wakeAll();
}

// 在分块回调处调用：暂停期间阻塞传输线程，断开/退出时自动放行
void TransferThread::waitIfPaused()
{
    QMutexLocker lock(&m_mutex);
    while (m_paused && !m_quit && !m_disconnectRequested)
        m_cond.wait(&m_mutex);
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
                m_abortRequested = false;   // 新任务开始，清除上一次的中断标记
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
    emit taskStarted(t.label, t.upload);

    QString err;
    QVector<PlanItem> plan;
    qint64 total = 0;

    // “打开”任务会把文件下到较深的缓存目录，先确保目标目录存在
    if (!t.upload)
        QDir().mkpath(t.dstDir);

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
        if (abortRequested()) {
            emit taskFinished(t.label, false, QStringLiteral("传输已中断"));
            return;
        }
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
    auto chunkCb = [&](qint64 d, qint64) -> bool {
        waitIfPaused();
        if (abortRequested())
            return false;   // 让 SftpClient 中断当前文件的读写
        emit progress(t.label, done + d, total);
        return true;
    };
    for (const PlanItem &p : plan) {
        if (p.isDir)
            continue;
        waitIfPaused();
        if (abortRequested()) {
            emit taskFinished(t.label, false, QStringLiteral("传输已中断"));
            return;
        }
        qint64 r = -1;
        if (t.upload) {
            r = client.uploadFile(p.local, p.remote, chunkCb, err);
        } else {
            r = client.downloadFile(p.remote, p.local, chunkCb, err);
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

    // “打开”任务：下载完成后通知 QML 调本地应用
    if (t.openAfter) {
        for (const PlanItem &p : plan) {
            if (!p.isDir) {
                emit openReady(p.local, p.remote, p.size, true, QString());
                return;
            }
        }
    }
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
        plan.append({ false, QDir(localDir).absoluteFilePath(fi.name), remotePath, fi.size });
        total += fi.size;
    }
}
