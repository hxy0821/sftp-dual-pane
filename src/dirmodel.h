#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QVariantList>

#include "fileentry.h"

class BrowseThread;

// 本地/远程统一的目录列表模型。
// 远程侧通过 BrowseThread 异步取数，避免阻塞 UI 线程。
class DirModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(bool remote READ isRemote WRITE setRemote NOTIFY remoteChanged)
    Q_PROPERTY(BrowseThread *browse READ browse WRITE setBrowse NOTIFY browseChanged)
    Q_PROPERTY(QString startPath READ startPath WRITE setStartPath)
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY pathChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IsDirRole,
        SizeRole,
        MtimeRole
    };
    Q_ENUM(Roles)

    explicit DirModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool isRemote() const { return m_remote; }
    void setRemote(bool r);
    BrowseThread *browse() const { return m_browse; }
    void setBrowse(BrowseThread *b);
    QString startPath() const { return m_startPath; }
    void setStartPath(const QString &p) { m_startPath = p; }
    QString currentPath() const { return m_path; }
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool v);
    int count() const { return m_entries.size(); }

    Q_INVOKABLE bool setDir(const QString &path);
    Q_INVOKABLE void goUp();
    Q_INVOKABLE bool enter(int row);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE QString nameAt(int row) const;
    Q_INVOKABLE bool isDirAt(int row) const;
    Q_INVOKABLE bool makeDir(const QString &name);
    Q_INVOKABLE bool makeFile(const QString &name);
    Q_INVOKABLE bool removeAt(int row);
    Q_INVOKABLE bool renameAt(int row, const QString &newName);

signals:
    void remoteChanged();
    void browseChanged();
    void pathChanged();
    void showHiddenChanged();
    void countChanged();
    void errorOccurred(const QString &message);

private slots:
    void onListed(const QString &path, const QVariantList &entries, const QString &err);
    void onOpFinished(const QString &op, bool ok, const QString &err);
    void onDisconnected();

private:
    void reloadLocal();
    void applyEntries(const QList<FileEntry> &entries);

    bool m_remote = false;
    BrowseThread *m_browse = nullptr;
    QString m_startPath;
    QString m_path;
    bool m_showHidden = false;
    QList<FileEntry> m_entries;
};
