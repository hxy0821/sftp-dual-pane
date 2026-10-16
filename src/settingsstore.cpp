#include "settingsstore.h"

#include <QSettings>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDir>
#include <QFileInfo>
#include <QDesktopServices>
#include <QUrl>

SettingsStore *SettingsStore::instance()
{
    static SettingsStore s;
    return &s;
}

SettingsStore::SettingsStore(QObject *parent) : QObject(parent) {}

static QVariantList loadConnections()
{
    QSettings s;
    const QString json = s.value(QStringLiteral("connections")).toString();
    if (json.isEmpty())
        return {};
    return QJsonDocument::fromJson(json.toUtf8()).toVariant().toList();
}

static void storeConnections(const QVariantList &list)
{
    QSettings s;
    s.setValue(QStringLiteral("connections"),
               QString::fromUtf8(QJsonDocument::fromVariant(list).toJson(QJsonDocument::Compact)));
}

QVariantList SettingsStore::savedNames() const
{
    QVariantList out;
    const QVariantList list = loadConnections();
    for (const QVariant &v : list)
        out << v.toMap().value(QStringLiteral("name")).toString();
    return out;
}

QVariantMap SettingsStore::connection(const QString &name) const
{
    const QVariantList list = loadConnections();
    for (const QVariant &v : list) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("name")).toString() == name)
            return m;
    }
    return QVariantMap();
}

void SettingsStore::saveConnection(const QString &name, const QVariantMap &data)
{
    QVariantList list = loadConnections();
    QVariantMap m = data;
    m.insert(QStringLiteral("name"), name);

    bool found = false;
    for (int i = 0; i < list.size(); ++i) {
        if (list.at(i).toMap().value(QStringLiteral("name")).toString() == name) {
            list[i] = m;
            found = true;
            break;
        }
    }
    if (!found)
        list << m;
    storeConnections(list);
}

void SettingsStore::removeConnection(const QString &name)
{
    QVariantList list = loadConnections();
    for (int i = 0; i < list.size(); ++i) {
        if (list.at(i).toMap().value(QStringLiteral("name")).toString() == name) {
            list.removeAt(i);
            break;
        }
    }
    storeConnections(list);
}

QString SettingsStore::lastLocalPath() const
{
    return QSettings().value(QStringLiteral("lastLocalPath")).toString();
}

void SettingsStore::setLastLocalPath(const QString &p)
{
    QSettings().setValue(QStringLiteral("lastLocalPath"), p);
}

// —— 路径书签 ——

static QString bookmarkKey(const QString &side)
{
    return side == QLatin1String("remote") ? QStringLiteral("bookmarksRemote")
                                           : QStringLiteral("bookmarksLocal");
}

static QVariantList loadBookmarks(const QString &key)
{
    QSettings s;
    const QString json = s.value(key).toString();
    if (json.isEmpty())
        return {};
    return QJsonDocument::fromJson(json.toUtf8()).toVariant().toList();
}

static void storeBookmarks(const QString &key, const QVariantList &list)
{
    QSettings s;
    s.setValue(key, QString::fromUtf8(QJsonDocument::fromVariant(list).toJson(QJsonDocument::Compact)));
}

QVariantList SettingsStore::bookmarks(const QString &side) const
{
    return loadBookmarks(bookmarkKey(side));
}

bool SettingsStore::toggleBookmark(const QString &side, const QString &path)
{
    const QString p = path.trimmed();
    if (p.isEmpty())
        return false;

    const QString key = bookmarkKey(side);
    QVariantList list = loadBookmarks(key);
    for (int i = 0; i < list.size(); ++i) {
        if (list.at(i).toMap().value(QStringLiteral("path")).toString() == p) {
            list.removeAt(i);
            storeBookmarks(key, list);
            return false;   // 已取消书签
        }
    }

    QString name = p;
    const int slash = name.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0 && slash + 1 < name.length())
        name = name.mid(slash + 1);
    if (name.isEmpty())
        name = QStringLiteral("/");

    QVariantMap m;
    m.insert(QStringLiteral("name"), name);
    m.insert(QStringLiteral("path"), p);
    list.append(m);
    storeBookmarks(key, list);
    return true;   // 已添加书签
}

QString SettingsStore::lastRemotePath() const
{
    return QSettings().value(QStringLiteral("lastRemotePath")).toString();
}

void SettingsStore::setLastRemotePath(const QString &p)
{
    QSettings().setValue(QStringLiteral("lastRemotePath"), p);
}

QString SettingsStore::lastConnection() const
{
    return QSettings().value(QStringLiteral("lastConnection")).toString();
}

void SettingsStore::setLastConnection(const QString &name)
{
    QSettings().setValue(QStringLiteral("lastConnection"), name);
}

QString SettingsStore::homeDir() const
{
    return QDir::homePath();
}

// 用系统默认应用打开本地文件（远程文件先下载到缓存再调用此接口）
bool SettingsStore::openPath(const QString &path)
{
    if (path.isEmpty() || !QFileInfo::exists(path))
        return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}
