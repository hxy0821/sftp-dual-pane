#pragma once

#include <QString>

// 统一的文件/目录条目，本地与远程共用。
struct FileEntry {
    QString name;
    QString path;
    bool isDir = false;
    qint64 size = 0;
    qint64 mtime = 0;
};
