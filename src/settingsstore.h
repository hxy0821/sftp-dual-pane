#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

// 连接配置与路径记忆的持久化（QSettings + JSON）。
class SettingsStore : public QObject
{
    Q_OBJECT
public:
    static SettingsStore *instance();

    Q_INVOKABLE QVariantList savedNames() const;
    Q_INVOKABLE QVariantMap connection(const QString &name) const;
    Q_INVOKABLE void saveConnection(const QString &name, const QVariantMap &data);
    Q_INVOKABLE void removeConnection(const QString &name);

    Q_INVOKABLE QString lastLocalPath() const;
    Q_INVOKABLE void setLastLocalPath(const QString &p);
    Q_INVOKABLE QString lastRemotePath() const;
    Q_INVOKABLE void setLastRemotePath(const QString &p);
    Q_INVOKABLE QString homeDir() const;

private:
    explicit SettingsStore(QObject *parent = nullptr);
};
