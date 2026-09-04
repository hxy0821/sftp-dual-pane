#include "dirmodel.h"

#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QDateTime>
#include <QVariantMap>

#include "browsethread.h"
#include "pathutil.h"

static QList<FileEntry> variantToEntries(const QVariantList &list)
{
    QList<FileEntry> out;
    out.reserve(list.size());
    for (const QVariant &v : list) {
        const QVariantMap m = v.toMap();
        FileEntry e;
        e.name = m.value(QStringLiteral("name")).toString();
        e.path = m.value(QStringLiteral("path")).toString();
        e.isDir = m.value(QStringLiteral("isDir")).toBool();
        e.size = m.value(QStringLiteral("size")).toLongLong();
        e.mtime = m.value(QStringLiteral("mtime")).toLongLong();
        out.append(e);
    }
    return out;
}

DirModel::DirModel(QObject *parent) : QAbstractListModel(parent) {}

int DirModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant DirModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const FileEntry &e = m_entries.at(index.row());
    switch (role) {
    case NameRole:  return e.name;
    case PathRole:  return e.path;
    case IsDirRole: return e.isDir;
    case SizeRole:  return e.size;
    case MtimeRole: return e.mtime;
    default:        return QVariant();
    }
}

QHash<int, QByteArray> DirModel::roleNames() const
{
    QHash<int, QByteArray> h;
    h[NameRole] = "name";
    h[PathRole] = "path";
    h[IsDirRole] = "isDir";
    h[SizeRole] = "size";
    h[MtimeRole] = "mtime";
    return h;
}

void DirModel::setRemote(bool r)
{
    if (m_remote == r)
        return;
    m_remote = r;
    emit remoteChanged();
}

void DirModel::setBrowse(BrowseThread *b)
{
    if (m_browse == b)
        return;
    if (m_browse) {
        disconnect(m_browse, nullptr, this, nullptr);
    }
    m_browse = b;
    if (m_browse) {
        connect(m_browse, &BrowseThread::listed, this, &DirModel::onListed);
        connect(m_browse, &BrowseThread::opFinished, this, &DirModel::onOpFinished);
        connect(m_browse, &BrowseThread::disconnected, this, &DirModel::onDisconnected);
    }
    emit browseChanged();
}

void DirModel::setShowHidden(bool v)
{
    if (m_showHidden == v)
        return;
    m_showHidden = v;
    emit showHiddenChanged();
    refresh();
}

void DirModel::applyEntries(const QList<FileEntry> &entries)
{
    beginResetModel();
    m_entries = entries;
    endResetModel();
    emit countChanged();
}

void DirModel::reloadLocal()
{
    QList<FileEntry> entries;
    QDir dir(m_path);
    const QFileInfoList list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot |
                                                 QDir::System,
                                                 QDir::DirsFirst | QDir::Name);
    for (const QFileInfo &fi : list) {
        if (!m_showHidden && fi.fileName().startsWith(QLatin1Char('.')))
            continue;
        FileEntry e;
        e.name = fi.fileName();
        e.path = fi.absoluteFilePath();
        e.isDir = fi.isDir();
        e.size = fi.size();
        e.mtime = fi.lastModified().toSecsSinceEpoch();
        entries.append(e);
    }
    applyEntries(entries);
}

void DirModel::onListed(const QString &path, const QVariantList &entries, const QString &err)
{
    // 忽略过期结果（用户已导航到别的目录）。
    if (path != m_path)
        return;
    if (!err.isEmpty())
        emit errorOccurred(err);
    applyEntries(variantToEntries(entries));
}

void DirModel::onOpFinished(const QString &op, bool ok, const QString &err)
{
    Q_UNUSED(op);
    if (!ok && !err.isEmpty())
        emit errorOccurred(err);
    // 远程增删改成功后刷新当前目录。
    if (ok)
        refresh();
}

void DirModel::onDisconnected()
{
    applyEntries(QList<FileEntry>());
}

bool DirModel::setDir(const QString &path)
{
    QString p = path.trimmed();
    if (p.isEmpty())
        return false;

    QString next = p;
    if (next != QLatin1String("/"))
        next = QDir::cleanPath(next);

    m_path = next;
    emit pathChanged();

    if (m_remote) {
        if (m_browse)
            m_browse->listDir(m_path, m_showHidden);
        else
            applyEntries(QList<FileEntry>());
    } else {
        reloadLocal();
    }
    return true;
}

void DirModel::goUp()
{
    if (m_path == QLatin1String("/"))
        return;
    QString p = QDir::cleanPath(m_path + QStringLiteral("/.."));
    if (p.isEmpty())
        p = QStringLiteral("/");
    setDir(p);
}

bool DirModel::enter(int row)
{
    if (row < 0 || row >= m_entries.size())
        return false;
    if (!m_entries.at(row).isDir)
        return false;
    return setDir(m_entries.at(row).path);
}

void DirModel::refresh()
{
    if (m_remote) {
        if (m_browse)
            m_browse->listDir(m_path, m_showHidden);
        else
            applyEntries(QList<FileEntry>());
    } else {
        reloadLocal();
    }
    emit pathChanged();
}

QString DirModel::pathAt(int row) const
{
    if (row < 0 || row >= m_entries.size())
        return QString();
    return m_entries.at(row).path;
}

QString DirModel::nameAt(int row) const
{
    if (row < 0 || row >= m_entries.size())
        return QString();
    return m_entries.at(row).name;
}

bool DirModel::isDirAt(int row) const
{
    if (row < 0 || row >= m_entries.size())
        return false;
    return m_entries.at(row).isDir;
}

bool DirModel::makeDir(const QString &name)
{
    const QString n = name.trimmed();
    if (n.isEmpty())
        return false;

    if (m_remote) {
        if (!m_browse)
            return false;
        m_browse->makeDir(joinRemotePath(m_path, n));
        return true;
    }

    bool ok = QDir(m_path).mkpath(n);
    if (!ok)
        emit errorOccurred(QStringLiteral("创建失败（可能权限不足）"));
    else
        refresh();
    return ok;
}

bool DirModel::makeFile(const QString &name)
{
    const QString n = name.trimmed();
    if (n.isEmpty())
        return false;

    if (m_remote) {
        if (!m_browse)
            return false;
        m_browse->makeFile(joinRemotePath(m_path, n));
        return true;
    }

    const QString np = QDir(m_path).absoluteFilePath(n);
    QFile f(np);
    bool ok = false;
    QString err;
    if (f.exists()) {
        err = QStringLiteral("文件已存在");
    } else if (f.open(QIODevice::WriteOnly)) {
        f.close();
        ok = true;
    } else {
        err = QStringLiteral("创建失败（可能权限不足）");
    }
    if (!ok) {
        emit errorOccurred(err);
        return false;
    }
    refresh();
    return true;
}

bool DirModel::removeAt(int row)
{
    if (row < 0 || row >= m_entries.size())
        return false;
    const FileEntry e = m_entries.at(row);

    if (m_remote) {
        if (!m_browse)
            return false;
        m_browse->removeEntry(e.path);
        return true;
    }

    QFileInfo fi(e.path);
    const bool ok = fi.isDir() ? QDir(e.path).removeRecursively() : QFile::remove(e.path);
    if (!ok) {
        emit errorOccurred(QStringLiteral("删除失败（可能权限不足）"));
        return false;
    }
    refresh();
    return true;
}

bool DirModel::renameAt(int row, const QString &newName)
{
    const QString n = newName.trimmed();
    if (row < 0 || row >= m_entries.size() || n.isEmpty())
        return false;
    const FileEntry e = m_entries.at(row);

    if (m_remote) {
        if (!m_browse)
            return false;
        m_browse->renameEntry(e.path, joinRemotePath(QDir::cleanPath(m_path), n));
        return true;
    }

    const QString np = QDir(m_path).absoluteFilePath(n);
    const bool ok = QFile::rename(e.path, np);
    if (!ok) {
        emit errorOccurred(QStringLiteral("重命名失败（可能权限不足或目标已存在）"));
        return false;
    }
    refresh();
    return true;
}
