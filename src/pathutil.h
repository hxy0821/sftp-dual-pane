#pragma once

#include <QDir>
#include <QString>

// 远程路径拼接（兼容根目录 "/"）。
inline QString joinRemotePath(const QString &base, const QString &name)
{
    if (base == QLatin1String("/"))
        return QLatin1Char('/') + name;
    if (base.endsWith(QLatin1Char('/')))
        return base + name;
    return base + QLatin1Char('/') + name;
}

// 本地路径规整。
inline QString cleanLocalPath(const QString &p)
{
    return QDir::cleanPath(p);
}
