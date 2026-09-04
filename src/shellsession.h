#pragma once

#include <QThread>
#include <QMutex>
#include <QQueue>
#include <QString>
#include <QByteArray>
#include <atomic>

// 交互式 SSH 终端会话：后台线程维护一条 shell 通道，持续读取输出、
// 发送输入。输出经过去 ANSI 后以 UTF-8 文本增量下发到 UI。
class ShellSession : public QThread
{
    Q_OBJECT
    Q_PROPERTY(QString host READ host WRITE setHost)
    Q_PROPERTY(quint16 port READ port WRITE setPort)
    Q_PROPERTY(QString user READ user WRITE setUser)
    Q_PROPERTY(QString password READ password WRITE setPassword)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    explicit ShellSession(QObject *parent = nullptr);
    ~ShellSession() override;

    QString host() const { return m_host; }
    void setHost(const QString &h) { QMutexLocker l(&m_mutex); m_host = h; }
    quint16 port() const { return m_port; }
    void setPort(quint16 p) { QMutexLocker l(&m_mutex); m_port = p; }
    QString user() const { return m_user; }
    void setUser(const QString &u) { QMutexLocker l(&m_mutex); m_user = u; }
    QString password() const { return m_password; }
    void setPassword(const QString &p) { QMutexLocker l(&m_mutex); m_password = p; }
    bool running() const { return m_running.load(); }

    // 从 UI 线程调用（线程安全入队）。
    Q_INVOKABLE void startSession();
    Q_INVOKABLE void sendInput(const QString &text);
    Q_INVOKABLE void resizeTerminal(int cols, int rows);
    Q_INVOKABLE void closeSession();

signals:
    void outputReceived(const QString &text);
    void sessionStarted();
    void sessionClosed(const QString &reason);
    void runningChanged();

protected:
    void run() override;

private:
    QString m_host;
    quint16 m_port = 22;
    QString m_user;
    QString m_password;

    QMutex m_mutex;
    QQueue<QByteArray> m_input;
    bool m_quit = false;
    bool m_resizePending = false;
    int m_cols = 80;
    int m_rows = 24;
    std::atomic<bool> m_running{false};
};
