#pragma once

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QQueue>
#include <QString>
#include <QStringList>
#include <QVector>

class SftpClient;

struct TransferTask {
    int id = 0;           // 任务唯一身份：取消/进度/完成均按 id 匹配
    bool upload = true;   // true: 本地 -> 远程；false: 远程 -> 本地
    QString srcPath;      // 源路径（单个文件或目录）
    QString dstDir;       // 目标目录
    QString label;        // 显示名
    bool openAfter = false; // 下载完成后用本地默认应用打开（“打开”功能）
};

// 后台传输线程：常驻运行，队列消费，自动建立/复用一条 SSH 连接。
class TransferThread : public QThread
{
    Q_OBJECT
    Q_PROPERTY(QString host READ host WRITE setHost)
    Q_PROPERTY(quint16 port READ port WRITE setPort)
    Q_PROPERTY(QString user READ user WRITE setUser)
    Q_PROPERTY(QString password READ password WRITE setPassword)

public:
    explicit TransferThread(QObject *parent = nullptr);
    ~TransferThread() override;

    QString host() const { return m_host; }
    void setHost(const QString &h) { QMutexLocker l(&m_mutex); m_host = h; }
    quint16 port() const { return m_port; }
    void setPort(quint16 p) { QMutexLocker l(&m_mutex); m_port = p; }
    QString user() const { return m_user; }
    void setUser(const QString &u) { QMutexLocker l(&m_mutex); m_user = u; }
    QString password() const { return m_password; }
    void setPassword(const QString &p) { QMutexLocker l(&m_mutex); m_password = p; }

    Q_INVOKABLE void enqueueUpload(const QStringList &localPaths, const QString &remoteDir);
    // openAfter: 下载完成后 emit openReady，由 QML 调本地应用打开
    Q_INVOKABLE void enqueueDownload(const QStringList &remotePaths, const QString &localDir,
                                     bool openAfter = false);
    Q_INVOKABLE void disconnectRemote();
    Q_INVOKABLE void pauseTransfer();
    Q_INVOKABLE void resumeTransfer();
    Q_INVOKABLE void abortTask(int id);   // 取消单个任务：运行中的中断，等待中的移出队列
    Q_INVOKABLE void abortAll();          // 全局中断：中断当前任务并清空等待队列

signals:
    void taskQueued(int taskId, const QString &label, bool upload, const QString &srcPath, const QString &dstDir);
    void queueCleared();
    void taskCancelled(int taskId, const QString &label);
    void taskStarted(int taskId, const QString &label, bool upload);
    void progress(int taskId, const QString &label, qint64 done, qint64 total);
    void taskFinished(int taskId, const QString &label, bool ok, const QString &message);
    void taskDone(bool upload, bool ok);
    void allFinished();
    void openReady(const QString &localPath, const QString &remotePath, qint64 remoteSize,
                   bool ok, const QString &err);

protected:
    void run() override;

private:
    struct PlanItem {
        bool isDir;
        QString local;
        QString remote;
        qint64 size = 0;
    };

    void runTask(const TransferTask &t, SftpClient &client);
    void collectLocalPlan(const QString &localPath, const QString &remoteDir,
                          QVector<PlanItem> &plan, qint64 &total);
    void collectRemotePlan(SftpClient &client, const QString &remotePath, const QString &localDir,
                           QVector<PlanItem> &plan, qint64 &total, QString &err);
    void waitIfPaused();
    bool abortRequested(int id);

    QMutex m_mutex;
    QWaitCondition m_cond;
    QQueue<TransferTask> m_queue;
    int m_nextTaskId = 1;       // 任务 id 分配器（单调递增，永不复用）
    int m_runningTaskId = 0;    // 当前运行任务 id；0 表示无
    int m_abortTaskId = 0;      // 需要中断的任务 id；0 表示无
    bool m_quit = false;
    bool m_disconnectRequested = false;
    bool m_paused = false;

    QString m_host;
    quint16 m_port = 22;
    QString m_user;
    QString m_password;
};
