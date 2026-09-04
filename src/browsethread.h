#pragma once

#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QQueue>
#include <QString>
#include <QVariantList>
#include <atomic>

// 后台浏览线程：拥有独立的 SSH 会话，处理连接 / 列目录 / 增删改，
// 避免任何网络操作阻塞 UI 线程。结果通过信号回到 UI。
class BrowseThread : public QThread
{
    Q_OBJECT
    Q_PROPERTY(QString host READ host WRITE setHost)
    Q_PROPERTY(quint16 port READ port WRITE setPort)
    Q_PROPERTY(QString user READ user WRITE setUser)
    Q_PROPERTY(QString password READ password WRITE setPassword)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit BrowseThread(QObject *parent = nullptr);
    ~BrowseThread() override;

    QString host() const { return m_host; }
    void setHost(const QString &h) { m_host = h; }
    quint16 port() const { return m_port; }
    void setPort(quint16 p) { m_port = p; }
    QString user() const { return m_user; }
    void setUser(const QString &u) { m_user = u; }
    QString password() const { return m_password; }
    void setPassword(const QString &p) { m_password = p; }
    bool isConnected() const { return m_connected.load(); }

    // 从 UI 线程调用，均为异步（结果走信号）。
    Q_INVOKABLE void connectToHost(int timeoutMs = 10000);
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE void listDir(const QString &path, bool showHidden);
    Q_INVOKABLE void makeDir(const QString &path);
    Q_INVOKABLE void makeFile(const QString &path);
    Q_INVOKABLE void removeEntry(const QString &path);
    Q_INVOKABLE void renameEntry(const QString &oldPath, const QString &newPath);

signals:
    void connectFinished(bool ok, const QString &err);
    void listed(const QString &path, const QVariantList &entries, const QString &err);
    void opFinished(const QString &op, bool ok, const QString &err);
    void disconnected();
    void connectedChanged();

protected:
    void run() override;

private:
    enum Op { OpConnect, OpList, OpMkdir, OpMkfile, OpRemove, OpRename, OpDisconnect, OpQuit };
    struct Cmd {
        Op op;
        QString a, b;
        bool flag = false;
        int timeoutMs = 10000;
        QString host, user, password;
        quint16 port = 22;
    };

    void enqueue(const Cmd &c);

    QString m_host;
    quint16 m_port = 22;
    QString m_user;
    QString m_password;
    std::atomic<bool> m_connected{false};

    QMutex m_mutex;
    QWaitCondition m_cond;
    QQueue<Cmd> m_queue;
};
