#include "shellsession.h"

#include "sftpclient.h"

#include <QElapsedTimer>
#include <unistd.h>

// 去掉常见的 ANSI 转义序列（颜色、光标移动等），保留文本。
// 状态机按字节处理，未识别完的序列留到下一批数据。
static QByteArray &stripAnsiState(QByteArray &pending, const QByteArray &in, QByteArray &out)
{
    pending += in;
    out.clear();
    out.reserve(pending.size());

    int i = 0;
    const int n = pending.size();
    while (i < n) {
        const unsigned char c = (unsigned char)pending.at(i);
        if (c == 0x1b) { // ESC
            // 需要至少一个后续字节才能判断
            if (i + 1 >= n)
                break;
            const unsigned char c2 = (unsigned char)pending.at(i + 1);
            if (c2 == '[') { // CSI
                int j = i + 2;
                bool done = false;
                while (j < n) {
                    const unsigned char d = (unsigned char)pending.at(j);
                    if (d >= 0x40 && d <= 0x7e) { // 终止字节
                        j++;
                        done = true;
                        break;
                    }
                    j++;
                }
                if (!done)
                    break; // 序列未结束，等下批
                i = j;
                continue;
            }
            if (c2 == ']') { // OSC，直到 BEL 或 ESC 反斜杠
                int j = i + 2;
                bool done = false;
                while (j < n) {
                    const unsigned char d = (unsigned char)pending.at(j);
                    if (d == 0x07) { // BEL
                        j++;
                        done = true;
                        break;
                    }
                    if (d == 0x1b && j + 1 < n && pending.at(j + 1) == '\\') {
                        j += 2;
                        done = true;
                        break;
                    }
                    j++;
                }
                if (!done)
                    break;
                i = j;
                continue;
            }
            // 其它两字节转义（如 ESC ( B）
            i += 2;
            continue;
        }
        out.append((char)c);
        i++;
    }
    pending.remove(0, i);
    return out;
}

ShellSession::ShellSession(QObject *parent) : QThread(parent) {}

ShellSession::~ShellSession()
{
    {
        QMutexLocker l(&m_mutex);
        m_quit = true;
    }
    if (isRunning())
        wait(3000);
}

void ShellSession::startSession()
{
    if (isRunning())
        return;
    {
        QMutexLocker l(&m_mutex);
        m_quit = false;
        m_input.clear();
        m_resizePending = false;
    }
    m_running.store(true);
    emit runningChanged();
    start();
}

void ShellSession::sendInput(const QString &text)
{
    if (text.isEmpty())
        return;
    QMutexLocker l(&m_mutex);
    m_input.enqueue(text.toUtf8());
}

void ShellSession::resizeTerminal(int cols, int rows)
{
    if (cols <= 0 || rows <= 0)
        return;
    QMutexLocker l(&m_mutex);
    m_cols = cols;
    m_rows = rows;
    m_resizePending = true;
}

void ShellSession::closeSession()
{
    QMutexLocker l(&m_mutex);
    m_quit = true;
}

void ShellSession::run()
{
    SftpClient client;
    {
        QMutexLocker l(&m_mutex);
        client.setHost(m_host);
        client.setPort(m_port);
        client.setUser(m_user);
        client.setPassword(m_password);
    }

    QString err;
    if (!client.connectInternal(15000, err)) {
        m_running.store(false);
        emit runningChanged();
        emit sessionClosed(QStringLiteral("连接失败: ") + err);
        return;
    }
    int cols = 80, rows = 24;
    {
        QMutexLocker l(&m_mutex);
        cols = m_cols;
        rows = m_rows;
    }
    if (!client.openShell(cols, rows, err)) {
        m_running.store(false);
        emit runningChanged();
        emit sessionClosed(QStringLiteral("打开终端失败: ") + err);
        client.close();
        return;
    }

    emit sessionStarted();

    char buf[4096];
    QByteArray pending;
    QByteArray clean;
    QByteArray toWrite;
    int writeOff = 0;
    int idleLoops = 0;

    while (true) {
        bool quit = false;
        {
            QMutexLocker l(&m_mutex);
            quit = m_quit;
        }
        if (quit)
            break;

        // 读取输出（非阻塞，持续读到 EAGAIN）
        bool gotData = false;
        while (true) {
            const int r = client.readShell(buf, sizeof(buf));
            if (r > 0) {
                gotData = true;
                stripAnsiState(pending, QByteArray(buf, r), clean);
                if (!clean.isEmpty())
                    emit outputReceived(QString::fromUtf8(clean));
                continue;
            }
            if (r == 0)
                break; // EAGAIN，暂时无数据
            // r < 0：通道关闭
            client.closeShell();
            client.close();
            m_running.store(false);
            emit runningChanged();
            emit sessionClosed(QStringLiteral("终端已关闭"));
            return;
        }

        // 处理 resize
        {
            QMutexLocker l(&m_mutex);
            if (m_resizePending) {
                m_resizePending = false;
                client.resizeShell(m_cols, m_rows);
            }
        }

        // 发送输入
        if (writeOff >= toWrite.size()) {
            writeOff = 0;
            toWrite.clear();
            QMutexLocker l(&m_mutex);
            if (!m_input.isEmpty())
                toWrite = m_input.dequeue();
        }
        if (!toWrite.isEmpty()) {
            const int w = client.writeShell(toWrite.constData() + writeOff,
                                            size_t(toWrite.size() - writeOff));
            if (w > 0)
                writeOff += w;
            else if (w < 0) {
                // 写失败，丢弃本段
                toWrite.clear();
                writeOff = 0;
            }
        }

        if (gotData)
            idleLoops = 0;
        else
            ++idleLoops;
        // 空转时退避，降低 CPU 占用；有数据时保持低延迟。
        ::usleep(idleLoops > 40 ? 20000 : 2000);
    }

    client.closeShell();
    client.close();
    m_running.store(false);
    emit runningChanged();
    emit sessionClosed(QStringLiteral("终端已关闭"));
}
