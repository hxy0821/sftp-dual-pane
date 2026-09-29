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

// 文件图标角标：扩展名前两个字母（无扩展名返回空串）
function typeTag(name) {
    var dot = name.lastIndexOf(".")
    if (dot < 0 || dot >= name.length - 1)
        return ""
    return name.substring(dot + 1, dot + 3).toUpperCase()
}

// Canvas 图标绘制：按 16x16 网格设计，按画布尺寸等比缩放；
// 供自绘按钮 / 空状态使用（ctx 为 Canvas 的 2d 上下文）
function drawIcon(ctx, name, w, h, color) {
    var u = Math.min(w, h) / 16
    ctx.save()
    ctx.translate((w - 16 * u) / 2, (h - 16 * u) / 2)
    ctx.scale(u, u)
    ctx.strokeStyle = color
    ctx.fillStyle = color
    ctx.lineWidth = 1.6
    ctx.lineCap = "round"
    ctx.lineJoin = "round"

    if (name === "up") {
        ctx.beginPath()
        ctx.moveTo(8, 12.5)
        ctx.lineTo(8, 3.5)
        ctx.moveTo(3.8, 7.7)
        ctx.lineTo(8, 3.5)
        ctx.lineTo(12.2, 7.7)
        ctx.stroke()
    } else if (name === "transfer") {
        ctx.beginPath()
        ctx.moveTo(5, 12.5)
        ctx.lineTo(5, 3.5)
        ctx.moveTo(2.4, 6.1)
        ctx.lineTo(5, 3.5)
        ctx.lineTo(7.6, 6.1)
        ctx.moveTo(11, 3.5)
        ctx.lineTo(11, 12.5)
        ctx.moveTo(8.4, 9.9)
        ctx.lineTo(11, 12.5)
        ctx.lineTo(13.6, 9.9)
        ctx.stroke()
    } else if (name === "refresh") {
        var a0 = -0.35 * Math.PI
        ctx.beginPath()
        ctx.arc(8, 8, 5.4, a0, a0 + 1.65 * Math.PI)
        ctx.stroke()
        var ax = 8 + 5.4 * Math.cos(a0)
        var ay = 8 + 5.4 * Math.sin(a0)
        ctx.beginPath()
        ctx.moveTo(ax - 2.4, ay - 1.0)
        ctx.lineTo(ax, ay)
        ctx.lineTo(ax + 1.0, ay + 2.4)
        ctx.stroke()
    } else if (name === "newfolder") {
        ctx.beginPath()
        ctx.moveTo(1.5, 11)
        ctx.lineTo(1.5, 3.5)
        ctx.lineTo(5.6, 3.5)
        ctx.lineTo(7.1, 5.6)
        ctx.lineTo(12, 5.6)
        ctx.lineTo(12, 11)
        ctx.closePath()
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(13.2, 9.5)
        ctx.lineTo(13.2, 13.5)
        ctx.moveTo(11.2, 11.5)
        ctx.lineTo(15.2, 11.5)
        ctx.stroke()
    } else if (name === "arrowRight") {
        ctx.beginPath()
        ctx.moveTo(2.5, 8)
        ctx.lineTo(13, 8)
        ctx.moveTo(9.4, 4.4)
        ctx.lineTo(13, 8)
        ctx.lineTo(9.4, 11.6)
        ctx.stroke()
    } else if (name === "arrowLeft") {
        ctx.beginPath()
        ctx.moveTo(13.5, 8)
        ctx.lineTo(3, 8)
        ctx.moveTo(6.6, 4.4)
        ctx.lineTo(3, 8)
        ctx.lineTo(6.6, 11.6)
        ctx.stroke()
    } else if (name === "upload") {
        ctx.beginPath()
        ctx.moveTo(8, 10.5)
        ctx.lineTo(8, 2.5)
        ctx.moveTo(4.2, 6.3)
        ctx.lineTo(8, 2.5)
        ctx.lineTo(11.8, 6.3)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(3.5, 13.4)
        ctx.lineTo(12.5, 13.4)
        ctx.stroke()
    } else if (name === "download") {
        ctx.beginPath()
        ctx.moveTo(8, 2.5)
        ctx.lineTo(8, 10.5)
        ctx.moveTo(4.2, 6.7)
        ctx.lineTo(8, 10.5)
        ctx.lineTo(11.8, 6.7)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(3.5, 13.4)
        ctx.lineTo(12.5, 13.4)
        ctx.stroke()
    } else if (name === "link") {
        ctx.beginPath()
        ctx.arc(5.6, 10.4, 3.3, Math.PI * 0.62, Math.PI * 1.62)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(10.4, 5.6, 3.3, Math.PI * 1.62, Math.PI * 0.62)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(6, 10)
        ctx.lineTo(10, 6)
        ctx.stroke()
    } else if (name === "sliders") {
        ctx.beginPath()
        ctx.moveTo(2, 4.5)
        ctx.lineTo(14, 4.5)
        ctx.moveTo(2, 8)
        ctx.lineTo(14, 8)
        ctx.moveTo(2, 11.5)
        ctx.lineTo(14, 11.5)
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(10.6, 4.5, 1.8, 0, 6.2832)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(5.4, 8, 1.8, 0, 6.2832)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(11.4, 11.5, 1.8, 0, 6.2832)
        ctx.fill()
    } else if (name === "inbox") {
        ctx.beginPath()
        ctx.moveTo(2.5, 3.5)
        ctx.lineTo(13.5, 3.5)
        ctx.lineTo(13.5, 12.5)
        ctx.lineTo(2.5, 12.5)
        ctx.closePath()
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(2.5, 8.8)
        ctx.lineTo(6.2, 8.8)
        ctx.lineTo(7.3, 10.5)
        ctx.lineTo(8.7, 10.5)
        ctx.lineTo(9.8, 8.8)
        ctx.lineTo(13.5, 8.8)
        ctx.stroke()
    } else if (name === "folderopen") {
        ctx.beginPath()
        ctx.moveTo(2, 12.5)
        ctx.lineTo(2, 4)
        ctx.lineTo(6.4, 4)
        ctx.lineTo(8, 6)
        ctx.lineTo(13.5, 6)
        ctx.lineTo(13.5, 12.5)
        ctx.closePath()
        ctx.stroke()
    } else if (name === "ban") {
        ctx.beginPath()
        ctx.arc(8, 8, 6, 0, 6.2832)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(3.8, 12.2)
        ctx.lineTo(12.2, 3.8)
        ctx.stroke()
    }
    ctx.restore()
}
