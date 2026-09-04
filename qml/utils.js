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
