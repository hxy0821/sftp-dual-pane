#include "openregistry.h"

#include <QSettings>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFileInfo>

OpenRegistry::OpenRegistry(QObject *parent)
    : QObject(parent)
{
    load();

    m_debounce.setSingleShot(true);
    m_debounce.setInterval(800);
    connect(&m_debounce, &QTimer::timeout, this, [this]() {
        const QStringList paths = m_pending;
        m_pending.clear();
        for (const QString &p : paths)
            onFileChanged(p);
    });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        if (!m_pending.contains(path))
            m_pending.append(path);
        m_debounce.start();
        // 替换式保存（vim/VSCode 先删后建）会让 watcher 自动移除路径，重新挂上
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);
    });
}

int OpenRegistry::dirtyCount() const
{
    int n = 0;
    for (const QVariant &v : m_entries)
        if (v.toMap().value(QStringLiteral("dirty")).toBool())
            ++n;
    return n;
}

void OpenRegistry::registerOpen(const QString &remotePath, const QString &localPath,
                                qint64 remoteSize)
{
    const QString name = remotePath.section(QLatin1Char('/'), -1, -1);
    QVariantMap e;
    e.insert(QStringLiteral("remotePath"), remotePath);
    e.insert(QStringLiteral("localPath"), localPath);
    e.insert(QStringLiteral("name"), name);
    e.insert(QStringLiteral("baselineSize"), remoteSize);
    e.insert(QStringLiteral("dirty"), false);

    const int idx = indexOfLocal(localPath);
    if (idx >= 0)
        m_entries[idx] = e;
    else
        m_entries.append(e);

    m_lastSize.insert(localPath, QFileInfo(localPath).size());
    watch(localPath);
    save();
    emit registryChanged();
}

void OpenRegistry::markSynced(const QString &remotePath)
{
    const int idx = indexOfRemote(remotePath);
    if (idx < 0)
        return;
    QVariantMap e = m_entries.at(idx).toMap();
    const QString localPath = e.value(QStringLiteral("localPath")).toString();
    const qint64 sz = QFileInfo(localPath).size();
    e.insert(QStringLiteral("baselineSize"), sz);   // 上传后远程大小 == 本地大小
    e.insert(QStringLiteral("dirty"), false);
    m_entries[idx] = e;
    m_lastSize.insert(localPath, sz);
    save();
    emit registryChanged();
}

QVariantMap OpenRegistry::nextDirty() const
{
    for (const QVariant &v : m_entries) {
        const QVariantMap e = v.toMap();
        if (e.value(QStringLiteral("dirty")).toBool())
            return e;
    }
    return QVariantMap();
}

QVariantMap OpenRegistry::entryFor(const QString &remotePath) const
{
    const int idx = indexOfRemote(remotePath);
    return idx >= 0 ? m_entries.at(idx).toMap() : QVariantMap();
}

bool OpenRegistry::isDirtyRemote(const QString &remotePath) const
{
    const int idx = indexOfRemote(remotePath);
    return idx >= 0 && m_entries.at(idx).toMap().value(QStringLiteral("dirty")).toBool();
}

void OpenRegistry::forget(const QString &localPath)
{
    const int idx = indexOfLocal(localPath);
    if (idx < 0)
        return;
    m_entries.removeAt(idx);
    m_lastSize.remove(localPath);
    if (m_watcher.files().contains(localPath))
        m_watcher.removePath(localPath);
    save();
    emit registryChanged();
}

void OpenRegistry::load()
{
    m_entries.clear();
    const QString json = QSettings().value(QStringLiteral("openRegistry")).toString();
    if (json.isEmpty())
        return;
    const QVariantList list = QJsonDocument::fromJson(json.toUtf8()).toVariant().toList();
    for (const QVariant &v : list) {
        QVariantMap e = v.toMap();
        const QString localPath = e.value(QStringLiteral("localPath")).toString();
        if (localPath.isEmpty() || !QFileInfo(localPath).isFile())
            continue;   // 缓存副本已被手动清理
        m_entries.append(e);
        watch(localPath);
        m_lastSize.insert(localPath, QFileInfo(localPath).size());
    }
}

void OpenRegistry::save()
{
    const QString json = QString::fromUtf8(
        QJsonDocument::fromVariant(m_entries).toJson(QJsonDocument::Compact));
    QSettings().setValue(QStringLiteral("openRegistry"), json);
}

void OpenRegistry::watch(const QString &localPath)
{
    if (!QFileInfo::exists(localPath))
        return;
    if (m_watcher.files().contains(localPath))
        m_watcher.removePath(localPath);
    m_watcher.addPath(localPath);
}

void OpenRegistry::onFileChanged(const QString &path)
{
    const int idx = indexOfLocal(path);
    if (idx < 0) {
        // 登记项不存在（缓存副本被删除），清理监视
        if (m_watcher.files().contains(path))
            m_watcher.removePath(path);
        return;
    }
    if (!QFileInfo(path).isFile()) {
        forget(path);
        return;
    }

    QVariantMap e = m_entries.at(idx).toMap();
    const qint64 cur = QFileInfo(path).size();
    const qint64 seen = m_lastSize.value(path, -1);
    m_lastSize.insert(path, cur);

    if (seen >= 0 && cur != seen && !e.value(QStringLiteral("dirty")).toBool()) {
        e.insert(QStringLiteral("dirty"), true);
        m_entries[idx] = e;
        save();
        emit registryChanged();
        emit fileModified(e.value(QStringLiteral("remotePath")).toString(), path,
                          e.value(QStringLiteral("name")).toString());
    }
}

int OpenRegistry::indexOfLocal(const QString &localPath) const
{
    for (int i = 0; i < m_entries.size(); ++i)
        if (m_entries.at(i).toMap().value(QStringLiteral("localPath")).toString() == localPath)
            return i;
    return -1;
}

int OpenRegistry::indexOfRemote(const QString &remotePath) const
{
    for (int i = 0; i < m_entries.size(); ++i)
        if (m_entries.at(i).toMap().value(QStringLiteral("remotePath")).toString() == remotePath)
            return i;
    return -1;
}
