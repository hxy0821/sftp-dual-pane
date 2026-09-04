#include "settingsstore.h"

#include <QSettings>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QDir>

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

QString SettingsStore::lastRemotePath() const
{
    return QSettings().value(QStringLiteral("lastRemotePath")).toString();
}

void SettingsStore::setLastRemotePath(const QString &p)
{
    QSettings().setValue(QStringLiteral("lastRemotePath"), p);
}

QString SettingsStore::homeDir() const
{
    return QDir::homePath();
}
