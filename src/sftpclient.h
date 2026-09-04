#pragma once

#include <QObject>
#include <QList>
#include <QString>
#include <functional>

#include <libssh2.h>
#include <libssh2_sftp.h>

#include "fileentry.h"

// SFTP 客户端：基于 libssh2，负责连接、认证、目录浏览、文件读写、增删改。
class SftpClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(quint16 port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString user READ user WRITE setUser NOTIFY userChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit SftpClient(QObject *parent = nullptr);
    ~SftpClient() override;

    QString host() const { return m_host; }
    void setHost(const QString &h) { if (h != m_host) { m_host = h; emit hostChanged(); } }
    quint16 port() const { return m_port; }
    void setPort(quint16 p) { if (p != m_port) { m_port = p; emit portChanged(); } }
    QString user() const { return m_user; }
    void setUser(const QString &u) { if (u != m_user) { m_user = u; emit userChanged(); } }
    QString password() const { return m_password; }
    void setPassword(const QString &p) { if (p != m_password) { m_password = p; emit passwordChanged(); } }
    bool isConnected() const { return m_session != nullptr; }

    // QML 便捷入口：成功返回空字符串，失败返回错误描述。
    Q_INVOKABLE QString connectToHost(int timeoutMs = 10000);
    Q_INVOKABLE void close();

    // 交互式 shell（供 ShellSession 工作线程调用，非 UI 线程）。
    bool openShell(int cols, int rows, QString &err);
    // 返回 >0 数据字节；0 表示无数据（EAGAIN）；<0 表示通道已关闭/出错。
    int readShell(char *buf, size_t len);
    int writeShell(const char *buf, size_t len);
    bool resizeShell(int cols, int rows);
    void closeShell();
    void setBlocking(bool on);
    void setSocketNonBlocking(bool on);

    // 内部使用：返回是否成功，错误写入 err。
    bool connectInternal(int timeoutMs, QString &err);

    QList<FileEntry> listDir(const QString &path, bool showHidden, QString &err);
    bool makeDir(const QString &path, QString &err);
    bool createFile(const QString &path, QString &err);
    bool removeEntry(const QString &path, QString &err);
    bool renameEntry(const QString &oldPath, const QString &newPath, QString &err);
    bool statFile(const QString &path, FileEntry &out, QString &err);

    qint64 downloadFile(const QString &remotePath, const QString &localPath,
                        const std::function<void(qint64, qint64)> &progress, QString &err);
    qint64 uploadFile(const QString &localPath, const QString &remotePath,
                      const std::function<void(qint64, qint64)> &progress, QString &err);

signals:
    void hostChanged();
    void portChanged();
    void userChanged();
    void passwordChanged();
    void connectedChanged();

private:
    int openSocket(const QString &host, quint16 port, int timeoutMs, QString &err);
    QString lastError(const QString &context);
    bool mkdirRecursive(const QString &remotePath, QString &err);

    LIBSSH2_SESSION *m_session = nullptr;
    LIBSSH2_SFTP *m_sftp = nullptr;
    LIBSSH2_CHANNEL *m_channel = nullptr;
    int m_sock = -1;

    QString m_host;
    quint16 m_port = 22;
    QString m_user;
    QString m_password;
};
