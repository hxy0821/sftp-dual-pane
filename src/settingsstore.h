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
    Q_INVOKABLE QString lastConnection() const;
    Q_INVOKABLE void setLastConnection(const QString &name);
    Q_INVOKABLE QString homeDir() const;
    Q_INVOKABLE bool openPath(const QString &path);

    // 路径书签：side = "local" | "remote"，返回 [{ name, path }]
    Q_INVOKABLE QVariantList bookmarks(const QString &side) const;
    // Ctrl+D 切换书签：已存在则移除，否则添加；返回 true 表示已添加
    Q_INVOKABLE bool toggleBookmark(const QString &side, const QString &path);

private:
    explicit SettingsStore(QObject *parent = nullptr);
};
