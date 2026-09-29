.pragma library

function formatBytes(n) {
    if (n === undefined || n === null || n < 0)
        return "-"
    if (n === 0)
        return "0 B"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    var v = n
    while (v >= 1024 && i < units.length - 1) {
        v /= 1024
        i++
    }
    return (i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i]
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n
}

function formatTime(ts) {
    if (!ts)
        return "-"
    var d = new Date(ts * 1000)
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) +
           " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// 按扩展名返回文件图标颜色（目录由调用方用文件夹形状表达，不经过这里）
function typeColor(name) {
    var ext = ""
    var dot = name.lastIndexOf(".")
    if (dot >= 0 && dot < name.length - 1)
        ext = name.substring(dot + 1).toLowerCase()
    if (["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "iso", "deb", "rpm"].indexOf(ext) >= 0)
        return "#a678e8"   // 压缩包 / 镜像：紫
    if (["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "ico"].indexOf(ext) >= 0)
        return "#4cb782"   // 图片：绿
    if (["mp3", "wav", "flac", "ogg", "mp4", "mkv", "avi", "mov", "webm"].indexOf(ext) >= 0)
        return "#ef8f5a"   // 音视频：橙
    if (ext === "pdf")
        return "#e5645c"   // PDF：红
    if (["doc", "docx", "ppt", "pptx", "xls", "xlsx", "md", "txt", "log", "json", "xml", "csv"].indexOf(ext) >= 0)
        return "#5b8def"   // 文档：蓝
    return "#a9b4c2"       // 其它：灰
}
