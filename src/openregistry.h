#pragma once

#include <QObject>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QHash>
#include <QVariantList>
#include <QVariantMap>

// “打开文件”登记表：跟踪已打开远程文件的本地缓存副本。
// - 打开成功时 registerOpen 记录 {remotePath, localPath, 远程大小基线}；
// - QFileSystemWatcher 监视本地副本，检测到修改（防抖 800ms + 大小变化过滤）
//   后标记 dirty 并发 fileModified 信号；
// - 回传成功后 markSynced 以本地文件大小为新基线；
// - 登记表持久化到 QSettings（JSON），应用重启后恢复监视。
class OpenRegistry : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int dirtyCount READ dirtyCount NOTIFY registryChanged)

public:
    explicit OpenRegistry(QObject *parent = nullptr);

    int dirtyCount() const;

    Q_INVOKABLE void registerOpen(const QString &remotePath, const QString &localPath,
                                  qint64 remoteSize);
    Q_INVOKABLE void markSynced(const QString &remotePath);
    Q_INVOKABLE QVariantMap nextDirty() const;      // {remotePath, localPath, name, baselineSize}
    Q_INVOKABLE QVariantMap entryFor(const QString &remotePath) const;
    Q_INVOKABLE bool isDirtyRemote(const QString &remotePath) const;
    Q_INVOKABLE void forget(const QString &localPath);

signals:
    void fileModified(const QString &remotePath, const QString &localPath, const QString &name);
    void registryChanged();

private:
    void load();
    void save();
    void watch(const QString &localPath);
    void onFileChanged(const QString &path);
    int indexOfLocal(const QString &localPath) const;
    int indexOfRemote(const QString &remotePath) const;

    QVariantList m_entries;   // {remotePath, localPath, name, baselineSize, dirty}
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;        // 修改防抖（编辑器保存常连续触发）
    QStringList m_pending;    // 防抖窗口内变化的本地路径
    QHash<QString, qint64> m_lastSize;   // 上次见到的大小，过滤 touch 类无变化触发
};
