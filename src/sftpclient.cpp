#include "sftpclient.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>

#include <algorithm>
#include <cstring>
#include <cstdio>

#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

#include "pathutil.h"

SftpClient::SftpClient(QObject *parent) : QObject(parent) {}

SftpClient::~SftpClient()
{
    close();
}

int SftpClient::openSocket(const QString &host, quint16 port, int timeoutMs, QString &err)
{
    struct addrinfo hints;
    std::memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    char portStr[16];
    std::snprintf(portStr, sizeof(portStr), "%u", unsigned(port));

    struct addrinfo *res = nullptr;
    int rc = ::getaddrinfo(host.toUtf8().constData(), portStr, &hints, &res);
    if (rc != 0 || !res) {
        err = QStringLiteral("无法解析主机名 (%1)").arg(QString::fromUtf8(gai_strerror(rc)));
        return -1;
    }

    int sock = -1;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        sock = ::socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (sock < 0)
            continue;

        // 非阻塞 connect + select 超时，避免长时间卡死。
        int flags = ::fcntl(sock, F_GETFL, 0);
        ::fcntl(sock, F_SETFL, flags | O_NONBLOCK);
        rc = ::connect(sock, ai->ai_addr, ai->ai_addrlen);
        if (rc != 0 && errno == EINPROGRESS) {
            fd_set wfds;
            FD_ZERO(&wfds);
            FD_SET(sock, &wfds);
            struct timeval tv;
            tv.tv_sec = timeoutMs / 1000;
            tv.tv_usec = (timeoutMs % 1000) * 1000;
            rc = ::select(sock + 1, nullptr, &wfds, nullptr, &tv);
            if (rc > 0) {
                int soerr = 0;
                socklen_t len = sizeof(soerr);
                ::getsockopt(sock, SOL_SOCKET, SO_ERROR, &soerr, &len);
                if (soerr != 0) {
                    rc = -1;
                    err = QString::fromLocal8Bit(std::strerror(soerr));
                } else {
                    rc = 0; // 连接成功
                }
            } else if (rc == 0) {
                rc = -1;
                err = QStringLiteral("连接超时");
            } else {
                err = QString::fromLocal8Bit(std::strerror(errno));
            }
        } else if (rc != 0) {
            err = QString::fromLocal8Bit(std::strerror(errno));
        }

        if (rc == 0) {
            ::fcntl(sock, F_SETFL, flags); // 恢复阻塞模式
            struct timeval tv;
            tv.tv_sec = 15; tv.tv_usec = 0;
            ::setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            ::setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
            break;
        }
        ::close(sock);
        sock = -1;
        if (!err.isEmpty())
            break;
    }
    ::freeaddrinfo(res);
    return sock;
}

QString SftpClient::lastError(const QString &context)
{
    char *msg = nullptr;
    int len = 0;
    libssh2_session_last_error(m_session, &msg, &len, 0);
    const QString detail = (msg && len > 0) ? QString::fromUtf8(msg, len) : QStringLiteral("未知错误");
    if (context.isEmpty())
        return detail;
    return context + QStringLiteral(": ") + detail;
}

bool SftpClient::connectInternal(int timeoutMs, QString &err)
{
    close();

    if (m_host.trimmed().isEmpty()) {
        err = QStringLiteral("主机地址为空");
        return false;
    }

    m_sock = openSocket(m_host, m_port, timeoutMs, err);
    if (m_sock < 0) {
        err = QStringLiteral("无法连接 %1:%2 — %3").arg(m_host).arg(m_port).arg(err);
        return false;
    }

    m_session = libssh2_session_init();
    if (!m_session) {
        close();
        err = QStringLiteral("初始化 SSH 会话失败");
        return false;
    }
    libssh2_session_set_blocking(m_session, 1);

    if (libssh2_session_handshake(m_session, m_sock) != 0) {
        err = lastError(QStringLiteral("SSH 握手失败"));
        close();
        return false;
    }

    if (libssh2_userauth_password(m_session, m_user.toUtf8().constData(),
                                  m_password.toUtf8().constData()) != 0) {
        err = lastError(QStringLiteral("认证失败"));
        close();
        return false;
    }

    m_sftp = libssh2_sftp_init(m_session);
    if (!m_sftp) {
        err = lastError(QStringLiteral("初始化 SFTP 失败"));
        close();
        return false;
    }

    emit connectedChanged();
    return true;
}

QString SftpClient::connectToHost(int timeoutMs)
{
    QString err;
    if (!connectInternal(timeoutMs, err))
        return err;
    return QString();
}

void SftpClient::close()
{
    const bool wasConnected = (m_session != nullptr);
    if (m_channel) {
        libssh2_channel_free(m_channel);
        m_channel = nullptr;
    }
    if (m_sftp) {
        libssh2_sftp_shutdown(m_sftp);
        m_sftp = nullptr;
    }
    if (m_session) {
        libssh2_session_disconnect(m_session, "bye");
        libssh2_session_free(m_session);
        m_session = nullptr;
    }
    if (m_sock >= 0) {
        ::close(m_sock);
        m_sock = -1;
    }
    if (wasConnected)
        emit connectedChanged();
}

bool SftpClient::openShell(int cols, int rows, QString &err)
{
    if (!m_session) {
        err = QStringLiteral("未连接");
        return false;
    }

    m_channel = libssh2_channel_open_session(m_session);
    if (!m_channel) {
        err = lastError(QStringLiteral("打开 SSH 通道失败"));
        return false;
    }

    // 分配 PTY 时关闭回显（ECHO=0）：终端采用“本地回显 + 回车整行提交”
    // 模型，输入由本地 TextArea 显示，避免 readline 的退格/光标重绘序列
    // 造成乱码。RFC 4254 §8 终端模式编码：1 字节 opcode + 4 字节大端
    // uint32 值，以 TTY_OP_END(0) 结束；ECHO 的 opcode 为 53。
    static const char kPtyModes[] = {
        (char)53,          // ECHO
        0, 0, 0, 0,        // value = 0（关闭）
        (char)0            // TTY_OP_END
    };
    const char term[] = "xterm-256color";
    if (libssh2_channel_request_pty_ex(m_channel, term,
                                       (unsigned int)(sizeof(term) - 1),
                                       kPtyModes, (unsigned int)sizeof(kPtyModes),
                                       cols, rows, 0, 0) != 0) {
        err = lastError(QStringLiteral("请求 PTY 失败"));
        closeShell();
        return false;
    }

    if (libssh2_channel_shell(m_channel) != 0) {
        err = lastError(QStringLiteral("启动 shell 失败"));
        closeShell();
        return false;
    }

    // shell 交互使用非阻塞模式，避免工作线程卡死。
    setBlocking(false);
    setSocketNonBlocking(true);
    return true;
}

int SftpClient::readShell(char *buf, size_t len)
{
    if (!m_channel)
        return -1;
    const ssize_t n = libssh2_channel_read(m_channel, buf, len);
    if (n == LIBSSH2_ERROR_EAGAIN)
        return 0;
    if (n <= 0)
        return -1;
    return int(n);
}

int SftpClient::writeShell(const char *buf, size_t len)
{
    if (!m_channel)
        return -1;
    const ssize_t n = libssh2_channel_write(m_channel, buf, len);
    if (n == LIBSSH2_ERROR_EAGAIN)
        return 0;
    if (n < 0)
        return -1;
    return int(n);
}

bool SftpClient::resizeShell(int cols, int rows)
{
    if (!m_channel)
        return false;
    return libssh2_channel_request_pty_size(m_channel, cols, rows) == 0;
}

void SftpClient::closeShell()
{
    if (m_channel) {
        libssh2_channel_free(m_channel);
        m_channel = nullptr;
    }
}

void SftpClient::setBlocking(bool on)
{
    if (m_session)
        libssh2_session_set_blocking(m_session, on ? 1 : 0);
}

void SftpClient::setSocketNonBlocking(bool on)
{
    if (m_sock < 0)
        return;
    const int flags = ::fcntl(m_sock, F_GETFL, 0);
    if (flags < 0)
        return;
    if (on)
        ::fcntl(m_sock, F_SETFL, flags | O_NONBLOCK);
    else
        ::fcntl(m_sock, F_SETFL, flags & ~O_NONBLOCK);
}

QList<FileEntry> SftpClient::listDir(const QString &path, bool showHidden, QString &err)
{
    QList<FileEntry> out;
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return out;
    }

    LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_opendir(m_sftp, path.toUtf8().constData());
    if (!h) {
        err = lastError(QStringLiteral("打开目录失败 %1").arg(path));
        return out;
    }

    char buf[4096];
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    while (true) {
        const int rc = libssh2_sftp_readdir(h, buf, sizeof(buf), &attrs);
        if (rc <= 0) {
            if (rc < 0)
                err = lastError(QStringLiteral("读取目录失败"));
            break;
        }
        QString name = QString::fromUtf8(buf, rc);
        if (name == QLatin1String(".") || name == QLatin1String(".."))
            continue;
        if (!showHidden && name.startsWith(QLatin1Char('.')))
            continue;

        FileEntry e;
        e.name = name;
        e.path = joinRemotePath(path, name);
        e.isDir = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && LIBSSH2_SFTP_S_ISDIR(attrs.permissions);
        e.size = (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? qint64(attrs.filesize) : 0;
        e.mtime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? qint64(attrs.mtime) : 0;
        out.append(e);
    }
    libssh2_sftp_closedir(h);

    std::stable_sort(out.begin(), out.end(), [](const FileEntry &a, const FileEntry &b) {
        if (a.isDir != b.isDir)
            return a.isDir;
        return QString::localeAwareCompare(a.name, b.name) < 0;
    });
    return out;
}

bool SftpClient::statFile(const QString &path, FileEntry &out, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return false;
    }
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    if (libssh2_sftp_stat(m_sftp, path.toUtf8().constData(), &attrs) != 0) {
        err = lastError(QStringLiteral("stat 失败 %1").arg(path));
        return false;
    }
    out.name = QFileInfo(path).fileName();
    out.path = path;
    out.isDir = (attrs.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && LIBSSH2_SFTP_S_ISDIR(attrs.permissions);
    out.size = (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE) ? qint64(attrs.filesize) : 0;
    out.mtime = (attrs.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) ? qint64(attrs.mtime) : 0;
    return true;
}

bool SftpClient::makeDir(const QString &path, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return false;
    }
    return mkdirRecursive(path, err);
}

bool SftpClient::mkdirRecursive(const QString &remotePath, QString &err)
{
    const QString clean = QDir::cleanPath(remotePath);
    if (clean.isEmpty() || clean == QLatin1String("/"))
        return true;

    QString cur;
    const QStringList parts = clean.split(QLatin1Char('/'), QString::SkipEmptyParts);
    for (const QString &p : parts) {
        cur = cur.isEmpty() ? (QLatin1Char('/') + p) : (cur + QLatin1Char('/') + p);
        if (libssh2_sftp_mkdir(m_sftp, cur.toUtf8().constData(), 0755) != 0) {
            LIBSSH2_SFTP_ATTRIBUTES a;
            if (libssh2_sftp_stat(m_sftp, cur.toUtf8().constData(), &a) == 0 &&
                (a.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) && LIBSSH2_SFTP_S_ISDIR(a.permissions)) {
                continue; // 已存在且是目录，忽略
            }
            err = lastError(QStringLiteral("创建目录失败 %1").arg(cur));
            return false;
        }
    }
    return true;
}

bool SftpClient::createFile(const QString &path, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return false;
    }
    LIBSSH2_SFTP_ATTRIBUTES a;
    if (libssh2_sftp_stat(m_sftp, path.toUtf8().constData(), &a) == 0) {
        err = QStringLiteral("目标已存在：%1").arg(path);
        return false;
    }
    LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_open(
        m_sftp, path.toUtf8().constData(),
        LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC, 0644);
    if (!h) {
        err = lastError(QStringLiteral("新建文件失败 %1").arg(path));
        return false;
    }
    libssh2_sftp_close(h);
    return true;
}

bool SftpClient::removeEntry(const QString &path, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return false;
    }
    FileEntry fi;
    if (!statFile(path, fi, err))
        return false;
    if (fi.isDir) {
        QList<FileEntry> children = listDir(path, true, err);
        if (!err.isEmpty())
            return false;
        for (const FileEntry &c : children) {
            if (!removeEntry(c.path, err))
                return false;
        }
        if (libssh2_sftp_rmdir(m_sftp, path.toUtf8().constData()) != 0) {
            err = lastError(QStringLiteral("删除目录失败 %1").arg(path));
            return false;
        }
        return true;
    }
    if (libssh2_sftp_unlink(m_sftp, path.toUtf8().constData()) != 0) {
        err = lastError(QStringLiteral("删除文件失败 %1").arg(path));
        return false;
    }
    return true;
}

bool SftpClient::renameEntry(const QString &oldPath, const QString &newPath, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return false;
    }
    const QByteArray o = oldPath.toUtf8();
    const QByteArray n = newPath.toUtf8();
    if (libssh2_sftp_rename_ex(m_sftp, o.constData(), (unsigned int)o.size(),
                               n.constData(), (unsigned int)n.size(),
                               LIBSSH2_SFTP_RENAME_OVERWRITE | LIBSSH2_SFTP_RENAME_ATOMIC |
                                   LIBSSH2_SFTP_RENAME_NATIVE) != 0) {
        err = lastError(QStringLiteral("重命名失败 %1").arg(oldPath));
        return false;
    }
    return true;
}

qint64 SftpClient::downloadFile(const QString &remotePath, const QString &localPath,
                                const std::function<void(qint64, qint64)> &progress, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return -1;
    }

    LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_open(m_sftp, remotePath.toUtf8().constData(),
                                               LIBSSH2_FXF_READ, 0);
    if (!h) {
        err = lastError(QStringLiteral("打开远程文件失败 %1").arg(remotePath));
        return -1;
    }

    qint64 total = 0;
    LIBSSH2_SFTP_ATTRIBUTES attrs;
    if (libssh2_sftp_fstat(h, &attrs) == 0 && (attrs.flags & LIBSSH2_SFTP_ATTR_SIZE))
        total = qint64(attrs.filesize);

    QFile f(localPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        err = QStringLiteral("无法写入本地文件 %1 (%2)").arg(localPath, f.errorString());
        libssh2_sftp_close(h);
        return -1;
    }

    char buf[128 * 1024];
    qint64 done = 0;
    while (true) {
        const ssize_t n = libssh2_sftp_read(h, buf, sizeof(buf));
        if (n < 0) {
            err = lastError(QStringLiteral("读取远程数据失败 %1").arg(remotePath));
            f.close();
            libssh2_sftp_close(h);
            return -1;
        }
        if (n == 0)
            break;
        if (f.write(buf, n) != n) {
            err = QStringLiteral("本地写入失败 (%1)").arg(f.errorString());
            f.close();
            libssh2_sftp_close(h);
            return -1;
        }
        done += n;
        if (progress)
            progress(done, total);
    }
    f.close();
    libssh2_sftp_close(h);
    return done;
}

qint64 SftpClient::uploadFile(const QString &localPath, const QString &remotePath,
                              const std::function<void(qint64, qint64)> &progress, QString &err)
{
    if (!m_sftp) {
        err = QStringLiteral("未连接");
        return -1;
    }

    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly)) {
        err = QStringLiteral("无法读取本地文件 %1 (%2)").arg(localPath, f.errorString());
        return -1;
    }

    const long mode = LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP |
                      LIBSSH2_SFTP_S_IROTH;
    LIBSSH2_SFTP_HANDLE *h = libssh2_sftp_open(m_sftp, remotePath.toUtf8().constData(),
                                               LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT |
                                                   LIBSSH2_FXF_TRUNC,
                                               mode);
    if (!h) {
        err = lastError(QStringLiteral("创建远程文件失败 %1").arg(remotePath));
        return -1;
    }

    const qint64 total = f.size();
    char buf[128 * 1024];
    qint64 done = 0;
    while (!f.atEnd()) {
        const qint64 r = f.read(buf, sizeof(buf));
        if (r <= 0) {
            err = QStringLiteral("读取本地文件失败 (%1)").arg(f.errorString());
            f.close();
            libssh2_sftp_close(h);
            return -1;
        }
        char *p = buf;
        qint64 left = r;
        while (left > 0) {
            const ssize_t w = libssh2_sftp_write(h, p, size_t(left));
            if (w < 0) {
                err = lastError(QStringLiteral("写入远程数据失败 %1").arg(remotePath));
                f.close();
                libssh2_sftp_close(h);
                return -1;
            }
            p += w;
            left -= w;
            done += w;
            if (progress)
                progress(done, total);
        }
    }
    f.close();
    libssh2_sftp_close(h);
    return done;
}
