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
    bool upload = true;   // true: 本地 -> 远程；false: 远程 -> 本地
    QString srcPath;      // 源路径（单个文件或目录）
    QString dstDir;       // 目标目录
    QString label;        // 显示名
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
    Q_INVOKABLE void enqueueDownload(const QStringList &remotePaths, const QString &localDir);
    Q_INVOKABLE void disconnectRemote();

signals:
    void taskStarted(const QString &label);
    void progress(const QString &label, qint64 done, qint64 total);
    void taskFinished(const QString &label, bool ok, const QString &message);
    void taskDone(bool upload, bool ok);
    void allFinished();

protected:
    void run() override;

private:
    struct PlanItem {
        bool isDir;
        QString local;
        QString remote;
    };

    void runTask(const TransferTask &t, SftpClient &client);
    void collectLocalPlan(const QString &localPath, const QString &remoteDir,
                          QVector<PlanItem> &plan, qint64 &total);
    void collectRemotePlan(SftpClient &client, const QString &remotePath, const QString &localDir,
                           QVector<PlanItem> &plan, qint64 &total, QString &err);

    QMutex m_mutex;
    QWaitCondition m_cond;
    QQueue<TransferTask> m_queue;
    bool m_quit = false;
    bool m_disconnectRequested = false;

    QString m_host;
    quint16 m_port = 22;
    QString m_user;
    QString m_password;
};
