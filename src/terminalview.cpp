#include "terminalview.h"

#include <QClipboard>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QString>
#include <QWheelEvent>
#include <QtMath>

// —— 主题（One Dark 风格调色板，深色底）——
static const QRgb kDefaultBg   = 0xff101419;
static const QRgb kDefaultFg   = 0xffc9d3df;
static const QRgb kCursorColor = 0xffc9d3df;
static const QRgb kAnsiColors[16] = {
    0xff3f4451, 0xffe06c75, 0xff98c379, 0xffe5c07b,
    0xff61afef, 0xffc678dd, 0xff56b6c2, 0xffabb2bf,
    0xff5c6370, 0xffff7b86, 0xffb0e08f, 0xfff0d197,
    0xff79c0ff, 0xffd9a5f5, 0xff62d4e3, 0xffffffff,
};
static const QColor kSelectionColor(88, 132, 210, 110);
static const int kScrollbackMax = 5000;

static QRgb xterm256(int idx)
{
    idx = qBound(0, idx, 255);
    if (idx < 16)
        return kAnsiColors[idx];
    if (idx < 232) {
        const int n = idx - 16;
        static const int lv[6] = {0, 95, 135, 175, 215, 255};
        return qRgb(lv[n / 36], lv[(n / 6) % 6], lv[n % 6]);
    }
    const int v = 8 + (idx - 232) * 10;
    return qRgb(v, v, v);
}

static inline void appendUtf16(QString &s, char32_t cp)
{
    if (cp < 0x10000) {
        s.append(QChar(ushort(cp)));
    } else {
        cp -= 0x10000;
        s.append(QChar(ushort(0xd800 + (cp >> 10))));
        s.append(QChar(ushort(0xdc00 + (cp & 0x3ff))));
    }
}

static inline QRgb effFg(const TerminalView::Cell &c)
{
    if (c.flags & TerminalView::FlagReverse)
        return c.bg ? c.bg : kDefaultBg;
    return c.fg ? c.fg : kDefaultFg;
}

static inline QRgb effBg(const TerminalView::Cell &c)
{
    if (c.flags & TerminalView::FlagReverse)
        return c.fg ? c.fg : kDefaultFg;
    return c.bg ? c.bg : kDefaultBg;
}

static inline const TerminalView::Cell &cellRef(const TerminalView::Line &line, int col)
{
    static const TerminalView::Cell blank;
    if (col >= 0 && col < line.cells.size())
        return line.cells.at(col);
    return blank;
}

// CSI 数值参数（0 视为缺省）
static int csiArg(const QVector<int> &p, int i, int def)
{
    if (i >= p.size())
        return def;
    const int v = p.at(i);
    return v > 0 ? v : def;
}

TerminalView::TerminalView(QQuickItem *parent) : QQuickPaintedItem(parent)
{
    setFlag(QQuickItem::ItemAcceptsInputMethod, true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::MiddleButton);
    m_screen = blankScreen();
    m_scrollBottom = m_rows - 1;
}

TerminalView::~TerminalView() = default;

void TerminalView::setFontSize(int px)
{
    px = qBound(6, px, 72);
    if (px == m_fontSize)
        return;
    m_fontSize = px;
    m_fontReady = false;
    ensureFont();
    update();
    emit fontSizeChanged();
}

// ———————————————————————— 字体与画布 ————————————————————————

void TerminalView::ensureFont()
{
    if (m_fontReady)
        return;
    QFont f;
    f.setPixelSize(m_fontSize);
    f.setStyleHint(QFont::TypeWriter);
    f.setHintingPreference(QFont::PreferFullHinting);
    f.setStyleStrategy(QFont::PreferAntialias);
    // 等宽且覆盖中文的字体优先（终端观感的关键）
    const QStringList prefer = {
        QStringLiteral("Noto Sans Mono CJK SC"),
        QStringLiteral("WenQuanYi Micro Hei Mono"),
        QStringLiteral("DejaVu Sans Mono"),
        QStringLiteral("Noto Mono"),
        QStringLiteral("Liberation Mono"),
    };
    const QStringList families = QFontDatabase().families();
    for (const QString &fam : prefer) {
        if (families.contains(fam)) {
            f.setFamily(fam);
            break;
        }
    }
    if (f.family().isEmpty()) {
        f = QFontDatabase::systemFont(QFontDatabase::FixedFont);
        f.setPixelSize(m_fontSize);
    }
    m_fontBase = f;
    m_fontBold = f;
    m_fontBold.setBold(true);
    m_fontItalic = f;
    m_fontItalic.setItalic(true);
    m_fontBoldItalic = f;
    m_fontBoldItalic.setBold(true);
    m_fontBoldItalic.setItalic(true);
    m_fontReady = true;
    recomputeMetrics();
}

void TerminalView::recomputeMetrics()
{
    const QFontMetricsF fm(m_fontBase);
    m_cellW = qMax(1.0, fm.horizontalAdvance(QStringLiteral("M")));
    m_ascent = fm.ascent();
    m_cellH = qMax(1.0, qreal(qCeil(fm.ascent()) + qCeil(fm.descent()) + 2));
    m_charWidths.clear();
    updateGridSize();
}

int TerminalView::charWidth(char32_t cp)
{
    if (cp < 0x0300)
        return cp < 0x20 ? 0 : 1;
    // 组合附加符号：不占格（简化处理，直接跳过）
    if (cp <= 0x036f || (cp >= 0x1ab0 && cp <= 0x1aff) ||
        (cp >= 0x20d0 && cp <= 0x20ff) || (cp >= 0xfe20 && cp <= 0xfe2f))
        return 0;
    const auto it = m_charWidths.constFind(uint(cp));
    if (it != m_charWidths.constEnd())
        return it.value();
    if (!m_fontReady)
        ensureFont();
    const uint u = uint(cp);
    const QFontMetricsF fm(m_fontBase);
    const qreal adv = fm.horizontalAdvance(QString::fromUcs4(&u, 1));
    int w = 1;
    if (adv >= m_cellW * 1.5)
        w = 2;
    else if (adv <= m_cellW * 0.1)
        w = 0;
    m_charWidths.insert(uint(cp), w);
    return w;
}

void TerminalView::updateGridSize()
{
    if (!m_fontReady || width() < m_cellW * 2 || height() < m_cellH)
        return;
    const int cols = qMax(2, int(width() / m_cellW));
    const int rows = qMax(1, int(height() / m_cellH));
    if (cols == m_cols && rows == m_rows)
        return;
    applySize(cols, rows);
}

void TerminalView::applySize(int cols, int rows)
{
    m_cols = cols;
    m_rows = rows;
    if (m_screen.isEmpty())
        m_screen = blankScreen();
    // 全空的屏幕（会话开始前/刚清屏）缩行时不进回滚，避免凭空多出历史
    bool screenBlank = true;
    for (const Line &l : m_screen) {
        if (!l.cells.isEmpty()) {
            screenBlank = false;
            break;
        }
    }
    while (m_screen.size() > rows) {
        const Line ln = m_screen.takeFirst();
        if (m_altScreen || screenBlank)
            continue;
        pushScrollback(ln);
    }
    while (m_screen.size() < rows)
        m_screen.append(Line());
    for (Line &l : m_screen) {
        if (l.cells.size() > cols)
            l.cells.resize(cols);
    }
    for (Line &l : m_scrollback) {
        if (l.cells.size() > cols)
            l.cells.resize(cols);
    }
    if (!m_altSavedScreen.isEmpty()) {
        while (m_altSavedScreen.size() > rows)
            m_altSavedScreen.removeFirst();
        while (m_altSavedScreen.size() < rows)
            m_altSavedScreen.append(Line());
        for (Line &l : m_altSavedScreen) {
            if (l.cells.size() > cols)
                l.cells.resize(cols);
        }
    }
    clampCursor();
    m_scrollTop = qBound(0, m_scrollTop, m_rows - 1);
    m_scrollBottom = qBound(m_scrollTop, m_scrollBottom, m_rows - 1);
    m_viewOffset = qBound(0, m_viewOffset, qMax(0, totalLines() - m_rows));
    clearSelection();
    emit terminalResized(m_cols, m_rows);
    update();
}

void TerminalView::reportTerminalSize()
{
    if (!m_fontReady)
        ensureFont();
    updateGridSize();
    emit terminalResized(m_cols, m_rows);
}

QVector<TerminalView::Line> TerminalView::blankScreen() const
{
    QVector<Line> v;
    v.resize(m_rows);
    return v;
}

TerminalView::Line *TerminalView::lineAt(int abs)
{
    if (m_altScreen) {
        if (abs < 0 || abs >= m_screen.size())
            return nullptr;
        return &m_screen[abs];
    }
    if (abs < 0)
        return nullptr;
    if (abs < m_scrollback.size())
        return &m_scrollback[abs];
    const int r = abs - m_scrollback.size();
    if (r >= m_screen.size())
        return nullptr;
    return &m_screen[r];
}

const TerminalView::Line *TerminalView::lineAt(int abs) const
{
    return const_cast<TerminalView *>(this)->lineAt(abs);
}

// ———————————————————————— 输出解析 ————————————————————————

void TerminalView::processOutput(const QByteArray &data)
{
    if (data.isEmpty())
        return;
    if (!m_fontReady)
        ensureFont();
    for (int i = 0; i < data.size(); ++i)
        feedByte(uchar(data.at(i)));
    update();
}

void TerminalView::feedByte(uchar c)
{
    switch (m_state) {
    case StGround: feedGround(c); break;
    case StEsc: feedEsc(c); break;
    case StEscSkip: m_state = StGround; break;
    case StCsi: feedCsi(c); break;
    case StOsc: feedOsc(c); break;
    }
}

void TerminalView::feedGround(uchar c)
{
    if (c < 0x20) {
        switch (c) {
        case 0x07: break;                                            // BEL
        case 0x08: backspace(); break;
        case 0x09: tabForward(1); break;
        case 0x0a: case 0x0b: case 0x0c: lineFeed(); break;
        case 0x0d: carriageReturn(); break;
        case 0x1b: m_state = StEsc; m_csiParams.clear(); break;
        default: break;                                              // SO/SI 等忽略
        }
        return;
    }
    if (c == 0x7f)
        return;                                                      // DEL 忽略
    // UTF-8 流式解码：不足的序列留在缓冲里等下一块数据（中文跨块不乱码）
    m_utf8Buf.append(char(c));
    const uchar b0 = uchar(m_utf8Buf.at(0));
    int need = 1;
    if (b0 >= 0xf0)
        need = 4;
    else if (b0 >= 0xe0)
        need = 3;
    else if (b0 >= 0xc0)
        need = 2;
    else if (b0 >= 0x80) {
        m_utf8Buf.clear();                                           // 非法续字节
        return;
    }
    if (m_utf8Buf.size() < need)
        return;
    char32_t cp = 0;
    bool ok = true;
    if (need == 1) {
        cp = b0;
    } else {
        cp = b0 & (0xffu >> (need + 1));
        for (int i = 1; i < need; ++i) {
            const uchar b = uchar(m_utf8Buf.at(i));
            if ((b & 0xc0) != 0x80) {
                ok = false;
                break;
            }
            cp = (cp << 6) | (b & 0x3f);
        }
    }
    m_utf8Buf.clear();
    if (ok)
        putChar(cp, charWidth(cp));
}

void TerminalView::feedEsc(uchar c)
{
    switch (c) {
    case '[':
        m_state = StCsi;
        m_csiParams.clear();
        return;
    case ']':
        m_state = StOsc;
        m_oscLen = 0;
        return;
    case '7': saveCursor(); m_state = StGround; return;
    case '8': restoreCursor(); m_state = StGround; return;
    case 'D': lineFeed(); m_state = StGround; return;                 // IND
    case 'E': carriageReturn(); lineFeed(); m_state = StGround; return; // NEL
    case 'M':                                                         // RI 反向换行
        m_wrapPending = false;
        if (m_curRow == m_scrollTop)
            scrollDown(1);
        else if (m_curRow > 0)
            --m_curRow;
        m_state = StGround;
        return;
    case '=': case '>':                                               // 小键盘模式：忽略
        m_state = StGround;
        return;
    case 'c':                                                         // RIS 全复位
        clearBuffer();
        m_curFg = m_curBg = 0;
        m_curFlags = 0;
        m_autoWrap = true;
        m_appCursor = false;
        m_bracketedPaste = false;
        m_cursorVisible = true;
        m_scrollTop = 0;
        m_scrollBottom = m_rows - 1;
        m_state = StGround;
        return;
    default:
        // ESC ( B 之类带单字节参数的序列：吃掉参数后回地面
        if (c == '(' || c == ')' || c == '*' || c == '+' || c == '-' ||
            c == '.' || c == '/' || c == '#' || c == '%') {
            m_state = StEscSkip;
            return;
        }
        m_state = StGround;                                           // 未识别：吞掉
        return;
    }
}

void TerminalView::feedCsi(uchar c)
{
    if (c == 0x1b) {                                                  // 序列中遇 ESC：中止
        m_csiParams.clear();
        m_state = StEsc;
        return;
    }
    if (c == 0x18 || c == 0x1a) {
        m_csiParams.clear();
        m_state = StGround;
        return;
    }
    if (c >= 0x20 && c <= 0x3f) {
        if (m_csiParams.size() < 64)
            m_csiParams.append(char(c));
        else {
            m_csiParams.clear();
            m_state = StGround;
        }
        return;
    }
    if (c >= 0x40 && c <= 0x7e) {
        const bool priv = (!m_csiParams.isEmpty() && m_csiParams.at(0) == '?');
        dispatchCsi(c, priv);
        m_csiParams.clear();
        m_state = StGround;
        return;
    }
    m_csiParams.clear();
    m_state = StGround;
}

void TerminalView::feedOsc(uchar c)
{
    if (c == 0x07) {                                                  // BEL 结束
        m_state = StGround;
        return;
    }
    if (c == 0x1b) {                                                  // ST = ESC \
        m_state = StEsc;
        return;
    }
    if (++m_oscLen > 4096) {                                          // 防御超长 OSC
        m_oscLen = 0;
        m_state = StGround;
    }
}

QVector<int> TerminalView::csiParams() const
{
    QVector<int> out;
    QByteArray s = m_csiParams;
    if (!s.isEmpty() && (s.at(0) == '?' || s.at(0) == '>' || s.at(0) == '='))
        s.remove(0, 1);
    for (const QByteArray &part : s.split(';')) {
        // "38:5:9" 之类的冒号子参数按展开处理
        for (const QByteArray &sub : part.split(':'))
            out.append(sub.isEmpty() ? 0 : sub.toInt());
    }
    return out;
}

void TerminalView::dispatchCsi(uchar final, bool priv)
{
    const QVector<int> p = csiParams();
    if (priv) {
        if (final != 'h' && final != 'l')
            return;
        const bool on = (final == 'h');
        for (int i = 0; i < p.size(); ++i) {
            switch (p.at(i)) {
            case 1: m_appCursor = on; break;
            case 7: m_autoWrap = on; break;
            case 25: m_cursorVisible = on; break;
            case 47:
            case 1047:
            case 1049:
                if (on)
                    enterAltScreen();
                else
                    leaveAltScreen();
                break;
            case 1048:
                if (on)
                    saveCursor();
                else
                    restoreCursor();
                break;
            case 2004: m_bracketedPaste = on; break;
            default: break;                                           // 鼠标/闪烁等忽略
            }
        }
        return;
    }
    switch (final) {
    case 'A':
        clampCursor();
        m_curRow = qMax(m_scrollTop, m_curRow - csiArg(p, 0, 1));
        m_wrapPending = false;
        break;
    case 'B':
        clampCursor();
        m_curRow = qMin(m_scrollBottom, m_curRow + csiArg(p, 0, 1));
        m_wrapPending = false;
        break;
    case 'C': m_curCol = qMin(m_cols - 1, m_curCol + csiArg(p, 0, 1)); m_wrapPending = false; break;
    case 'D': m_curCol = qMax(0, m_curCol - csiArg(p, 0, 1)); m_wrapPending = false; break;
    case 'E': m_curRow = qMin(m_rows - 1, m_curRow + csiArg(p, 0, 1)); m_curCol = 0; m_wrapPending = false; break;
    case 'F': m_curRow = qMax(0, m_curRow - csiArg(p, 0, 1)); m_curCol = 0; m_wrapPending = false; break;
    case 'G': case '`': m_curCol = qBound(0, csiArg(p, 0, 1) - 1, m_cols - 1); m_wrapPending = false; break;
    case 'd': m_curRow = qBound(0, csiArg(p, 0, 1) - 1, m_rows - 1); m_wrapPending = false; break;
    case 'H': case 'f':
        m_curRow = qBound(0, csiArg(p, 0, 1) - 1, m_rows - 1);
        m_curCol = qBound(0, csiArg(p, 1, 1) - 1, m_cols - 1);
        m_wrapPending = false;
        break;
    case 'a': m_curCol = qMin(m_cols - 1, m_curCol + csiArg(p, 0, 1)); break;
    case 'e': m_curRow = qMin(m_rows - 1, m_curRow + csiArg(p, 0, 1)); break;
    case 'J': eraseDisplay(p.isEmpty() ? 0 : p.at(0)); break;
    case 'K': eraseLine(p.isEmpty() ? 0 : p.at(0)); break;
    case 'L': insertLines(csiArg(p, 0, 1)); break;
    case 'M': deleteLines(csiArg(p, 0, 1)); break;
    case 'P': deleteChars(csiArg(p, 0, 1)); break;
    case '@': insertChars(csiArg(p, 0, 1)); break;
    case 'X': eraseChars(csiArg(p, 0, 1)); break;
    case 'S': scrollUp(csiArg(p, 0, 1), true); break;
    case 'T': scrollDown(csiArg(p, 0, 1)); break;
    case 'b':                                                         // REP 重复上一字符
        if (m_lastChar) {
            const int n = csiArg(p, 0, 1);
            for (int i = 0; i < n; ++i)
                putChar(m_lastChar, m_lastCharW);
        }
        break;
    case 'I': tabForward(csiArg(p, 0, 1)); break;
    case 'Z': tabBackward(csiArg(p, 0, 1)); break;
    case 'm': handleSgr(p); break;
    case 'r': {                                                       // DECSTBM 滚动区域
        const int top = csiArg(p, 0, 1) - 1;
        const int bot = csiArg(p, 1, m_rows) - 1;
        if (top < bot) {
            m_scrollTop = qBound(0, top, m_rows - 1);
            m_scrollBottom = qBound(0, bot, m_rows - 1);
            m_curRow = 0;
            m_curCol = 0;
            m_wrapPending = false;
        }
        break;
    }
    case 's': saveCursor(); break;
    case 'u': restoreCursor(); break;
    case 'n':                                                         // DSR
        if (!p.isEmpty() && p.at(0) == 5)
            promptReply("\x1b[0n");
        else if (!p.isEmpty() && p.at(0) == 6)
            promptReply("\x1b[" + QByteArray::number(m_curRow + 1) + ";" +
                        QByteArray::number(m_curCol + 1) + "R");
        break;
    case 'c': promptReply("\x1b[?1;2c"); break;                       // DA1
    case 't':
        if (!p.isEmpty() && p.at(0) == 18)                            // 查询文本区大小
            promptReply("\x1b[8;" + QByteArray::number(m_rows) + ";" +
                        QByteArray::number(m_cols) + "t");
        break;
    default:
        break;
    }
}

void TerminalView::handleSgr(const QVector<int> &p)
{
    if (p.isEmpty()) {
        m_curFg = m_curBg = 0;
        m_curFlags = 0;
        return;
    }
    for (int i = 0; i < p.size(); ++i) {
        const int a = p.at(i);
        if (a == 0) {
            m_curFg = m_curBg = 0;
            m_curFlags = 0;
        } else if (a == 1) {
            m_curFlags |= FlagBold;
        } else if (a == 2) {
            // 暗淡：忽略
        } else if (a == 3) {
            m_curFlags |= FlagItalic;
        } else if (a == 4) {
            m_curFlags |= FlagUnderline;
        } else if (a == 7) {
            m_curFlags |= FlagReverse;
        } else if (a == 8) {
            m_curFlags |= FlagHidden;
        } else if (a == 9) {
            m_curFlags |= FlagStrike;
        } else if (a >= 21 && a <= 29) {
            switch (a) {
            case 21: case 22: m_curFlags &= quint8(~FlagBold); break;
            case 23: m_curFlags &= quint8(~FlagItalic); break;
            case 24: m_curFlags &= quint8(~FlagUnderline); break;
            case 27: m_curFlags &= quint8(~FlagReverse); break;
            case 28: m_curFlags &= quint8(~FlagHidden); break;
            case 29: m_curFlags &= quint8(~FlagStrike); break;
            default: break;
            }
        } else if (a >= 30 && a <= 37) {
            m_curFg = kAnsiColors[a - 30];
        } else if (a == 38 || a == 48) {
            QRgb col = 0;
            if (i + 1 < p.size() && p.at(i + 1) == 5 && i + 2 < p.size()) {
                col = xterm256(p.at(i + 2));
                i += 2;
            } else if (i + 1 < p.size() && p.at(i + 1) == 2 && i + 4 < p.size()) {
                col = qRgb(qBound(0, p.at(i + 2), 255), qBound(0, p.at(i + 3), 255),
                           qBound(0, p.at(i + 4), 255));
                i += 4;
            } else {
                i = p.size();                                         // 参数不足：丢弃
            }
            if (col) {
                if (a == 38)
                    m_curFg = col;
                else
                    m_curBg = col;
            }
        } else if (a == 39) {
            m_curFg = 0;
        } else if (a >= 40 && a <= 47) {
            m_curBg = kAnsiColors[a - 40];
        } else if (a == 49) {
            m_curBg = 0;
        } else if (a >= 90 && a <= 97) {
            m_curFg = kAnsiColors[a - 90 + 8];
        } else if (a >= 100 && a <= 107) {
            m_curBg = kAnsiColors[a - 100 + 8];
        }
    }
}

void TerminalView::promptReply(const QByteArray &reply)
{
    if (m_sessionActive && !reply.isEmpty())
        emit dataToSend(reply);
}

// ———————————————————————— 网格编辑 ————————————————————————

void TerminalView::putChar(char32_t cp, int w)
{
    if (w <= 0)
        return;
    if (m_screen.size() != m_rows)
        m_screen = blankScreen();
    if (m_wrapPending)
        handleWrap();
    if (w == 2 && m_curCol >= m_cols - 1) {
        if (m_autoWrap)
            handleWrap();
        else
            m_curCol = qMax(0, m_cols - 2);
    }
    Line &line = screenLine(m_curRow);
    if (line.cells.size() < m_curCol + w)
        line.cells.resize(m_curCol + w);
    // 清掉被覆盖的宽字符残档
    if (line.cells.at(m_curCol).cont && m_curCol > 0)
        line.cells[m_curCol - 1] = Cell();
    if (m_curCol + 1 < line.cells.size() && line.cells.at(m_curCol + 1).cont)
        line.cells[m_curCol + 1] = Cell();
    Cell nc;
    nc.ch = cp;
    nc.fg = m_curFg;
    nc.bg = m_curBg;
    nc.flags = m_curFlags;
    line.cells[m_curCol] = nc;
    if (w == 2) {
        Cell cc;
        cc.cont = true;
        cc.flags = nc.flags;   // 宽字符第二格随前半格（反显底色才能连成整块）
        cc.fg = nc.fg;
        cc.bg = nc.bg;
        line.cells[m_curCol + 1] = cc;
    }
    m_lastChar = cp;
    m_lastCharW = w;
    const int next = m_curCol + w;
    if (next >= m_cols) {
        m_curCol = m_cols - 1;
        if (m_autoWrap)
            m_wrapPending = true;
    } else {
        m_curCol = next;
    }
}

void TerminalView::handleWrap()
{
    m_wrapPending = false;
    if (!m_screen.isEmpty())
        screenLine(m_curRow).wrapped = true;
    if (m_curRow == m_scrollBottom)
        scrollUp(1, !m_altScreen);
    else if (m_curRow < m_rows - 1)
        ++m_curRow;
    m_curCol = 0;
}

void TerminalView::carriageReturn()
{
    m_wrapPending = false;
    m_curCol = 0;
}

void TerminalView::lineFeed()
{
    m_wrapPending = false;
    if (m_curRow == m_scrollBottom)
        scrollUp(1, !m_altScreen);
    else if (m_curRow < m_rows - 1)
        ++m_curRow;
}

void TerminalView::backspace()
{
    m_wrapPending = false;
    if (m_curCol > 0)
        --m_curCol;
}

void TerminalView::tabForward(int n)
{
    for (int i = 0; i < n; ++i) {
        if (m_curCol >= m_cols - 1)
            break;
        m_curCol = qMin(m_cols - 1, ((m_curCol / 8) + 1) * 8);
    }
}

void TerminalView::tabBackward(int n)
{
    for (int i = 0; i < n; ++i) {
        if (m_curCol == 0)
            break;
        m_curCol = ((m_curCol - 1) / 8) * 8;
    }
}

void TerminalView::scrollUp(int n, bool pushToScrollback)
{
    for (int i = 0; i < n; ++i) {
        if (m_screen.size() <= m_scrollTop)
            break;
        const Line ln = m_screen.at(m_scrollTop);
        m_screen.remove(m_scrollTop);
        m_screen.insert(m_scrollBottom, Line());
        if (pushToScrollback && m_scrollTop == 0 && !m_altScreen)
            pushScrollback(ln);
    }
}

void TerminalView::pushScrollback(const Line &line)
{
    m_scrollback.append(line);
    if (m_viewOffset > 0)
        ++m_viewOffset;                                               // 视口内容保持不动
    if (m_scrollback.size() <= kScrollbackMax)
        return;
    const int drop = m_scrollback.size() - kScrollbackMax;
    m_scrollback.remove(0, drop);
    m_viewOffset = qMax(0, m_viewOffset - drop);
    if (m_hasSelection) {
        m_selStartLine -= drop;
        m_selEndLine -= drop;
        if (m_selStartLine < 0 || m_selEndLine < 0)
            clearSelection();
    }
}

void TerminalView::scrollDown(int n)
{
    for (int i = 0; i < n; ++i) {
        if (m_scrollBottom >= m_screen.size())
            break;
        m_screen.remove(m_scrollBottom);
        m_screen.insert(m_scrollTop, Line());
    }
}

void TerminalView::eraseDisplay(int mode)
{
    if (mode == 2 || mode == 3) {
        for (Line &l : m_screen) {
            l.cells.clear();
            l.wrapped = false;
        }
        if (mode == 3)
            m_scrollback.clear();
        return;
    }
    if (mode == 0) {
        if (m_curRow < m_screen.size())
            clearLine(m_screen[m_curRow], m_curCol, m_cols - 1);
        for (int r = m_curRow + 1; r < m_screen.size(); ++r)
            m_screen[r].cells.clear();
    } else if (mode == 1) {
        for (int r = 0; r < m_curRow && r < m_screen.size(); ++r)
            m_screen[r].cells.clear();
        if (m_curRow < m_screen.size())
            clearLine(m_screen[m_curRow], 0, m_curCol);
    }
}

void TerminalView::eraseLine(int mode)
{
    if (m_curRow >= m_screen.size())
        return;
    Line &l = m_screen[m_curRow];
    if (mode == 2) {
        l.cells.clear();
        l.wrapped = false;
    } else if (mode == 0) {
        clearLine(l, m_curCol, m_cols - 1);
    } else if (mode == 1) {
        clearLine(l, 0, m_curCol);
    }
}

void TerminalView::clearLine(Line &line, int from, int to)
{
    if (line.cells.isEmpty())
        return;
    from = qMax(0, from);
    if (from >= line.cells.size())
        return;
    to = qMin(to, line.cells.size() - 1);
    for (int c = from; c <= to; ++c)
        line.cells[c] = Cell();
}

void TerminalView::insertLines(int n)
{
    if (n <= 0 || m_curRow < m_scrollTop || m_curRow > m_scrollBottom)
        return;
    n = qMin(n, m_scrollBottom - m_curRow + 1);
    for (int i = 0; i < n; ++i) {
        m_screen.remove(m_scrollBottom);
        m_screen.insert(m_curRow, Line());
    }
}

void TerminalView::deleteLines(int n)
{
    if (n <= 0 || m_curRow < m_scrollTop || m_curRow > m_scrollBottom)
        return;
    n = qMin(n, m_scrollBottom - m_curRow + 1);
    for (int i = 0; i < n; ++i) {
        m_screen.remove(m_curRow);
        m_screen.insert(m_scrollBottom, Line());
    }
}

void TerminalView::insertChars(int n)
{
    if (n <= 0 || m_curRow >= m_screen.size())
        return;
    Line &l = m_screen[m_curRow];
    if (m_curCol >= l.cells.size())
        return;
    n = qMin(n, m_cols - m_curCol);
    for (int i = 0; i < n; ++i)
        l.cells.insert(m_curCol, Cell());
    if (l.cells.size() > m_cols)
        l.cells.resize(m_cols);
}

void TerminalView::deleteChars(int n)
{
    if (n <= 0 || m_curRow >= m_screen.size())
        return;
    Line &l = m_screen[m_curRow];
    if (m_curCol >= l.cells.size())
        return;
    n = qMin(n, l.cells.size() - m_curCol);
    l.cells.remove(m_curCol, n);
}

void TerminalView::eraseChars(int n)
{
    if (n <= 0 || m_curRow >= m_screen.size())
        return;
    Line &l = m_screen[m_curRow];
    if (m_curCol >= l.cells.size())
        return;
    n = qMin(n, qMin(l.cells.size() - m_curCol, m_cols - m_curCol));
    for (int i = 0; i < n; ++i)
        l.cells[m_curCol + i] = Cell();
}

void TerminalView::clampCursor()
{
    m_curRow = qBound(0, m_curRow, m_rows - 1);
    m_curCol = qBound(0, m_curCol, m_cols - 1);
}

void TerminalView::saveCursor()
{
    m_scRow = m_curRow;
    m_scCol = m_curCol;
    m_scFg = m_curFg;
    m_scBg = m_curBg;
    m_scFlags = m_curFlags;
    m_scWrap = m_wrapPending;
}

void TerminalView::restoreCursor()
{
    m_curRow = qBound(0, m_scRow, m_rows - 1);
    m_curCol = qBound(0, m_scCol, m_cols - 1);
    m_curFg = m_scFg;
    m_curBg = m_scBg;
    m_curFlags = m_scFlags;
    m_wrapPending = false;
}

void TerminalView::enterAltScreen()
{
    if (m_altScreen)
        return;
    m_altScreen = true;
    m_altSavedScreen = m_screen;
    m_altSavedRow = m_curRow;
    m_altSavedCol = m_curCol;
    m_altSavedTop = m_scrollTop;
    m_altSavedBottom = m_scrollBottom;
    m_altSavedFg = m_curFg;
    m_altSavedBg = m_curBg;
    m_altSavedFlags = m_curFlags;
    m_altSavedWrap = m_wrapPending;
    m_screen = blankScreen();
    m_curRow = 0;
    m_curCol = 0;
    m_wrapPending = false;
    m_scrollTop = 0;
    m_scrollBottom = m_rows - 1;
    m_viewOffset = 0;
    clearSelection();
}

void TerminalView::leaveAltScreen()
{
    if (!m_altScreen)
        return;
    m_altScreen = false;
    m_screen = m_altSavedScreen;
    while (m_screen.size() > m_rows)
        m_screen.removeFirst();
    while (m_screen.size() < m_rows)
        m_screen.append(Line());
    for (Line &l : m_screen) {
        if (l.cells.size() > m_cols)
            l.cells.resize(m_cols);
    }
    m_curRow = qBound(0, m_altSavedRow, m_rows - 1);
    m_curCol = qBound(0, m_altSavedCol, m_cols - 1);
    m_curFg = m_altSavedFg;
    m_curBg = m_altSavedBg;
    m_curFlags = m_altSavedFlags;
    m_wrapPending = false;
    m_scrollTop = 0;
    m_scrollBottom = m_rows - 1;
    m_viewOffset = 0;
    clearSelection();
}

// ———————————————————————— 会话与视图状态 ————————————————————————

void TerminalView::resetSession()
{
    m_state = StGround;
    m_csiParams.clear();
    m_utf8Buf.clear();
    m_oscLen = 0;
    m_scrollback.clear();
    m_screen = blankScreen();
    m_curRow = 0;
    m_curCol = 0;
    m_wrapPending = false;
    m_curFg = m_curBg = 0;
    m_curFlags = 0;
    m_scrollTop = 0;
    m_scrollBottom = m_rows - 1;
    m_appCursor = false;
    m_autoWrap = true;
    m_bracketedPaste = false;
    m_cursorVisible = true;
    m_altScreen = false;
    m_altSavedScreen.clear();
    m_viewOffset = 0;
    m_preedit.clear();
    clearSelection();
    reportTerminalSize();
    update();
}

void TerminalView::clearBuffer()
{
    m_scrollback.clear();
    m_screen = blankScreen();
    m_curRow = 0;
    m_curCol = 0;
    m_wrapPending = false;
    m_viewOffset = 0;
    clearSelection();
    update();
}

void TerminalView::setSessionActive(bool on)
{
    if (m_sessionActive == on)
        return;
    m_sessionActive = on;
    if (on)
        scrollView(1000000);                                          // 回到底部
    update();
}

void TerminalView::scrollView(int lines)
{
    const int maxOff = qMax(0, totalLines() - m_rows);
    if (maxOff <= 0) {
        if (m_viewOffset != 0) {
            m_viewOffset = 0;
            update();
        }
        return;
    }
    const int v = qBound(0, m_viewOffset - lines, maxOff);
    if (v != m_viewOffset) {
        m_viewOffset = v;
        update();
    }
}

// ———————————————————————— 键盘输入 ————————————————————————

void TerminalView::keyPressEvent(QKeyEvent *event)
{
    const int key = event->key();
    const Qt::KeyboardModifiers mods = event->modifiers();
    const bool ctrl = mods & Qt::ControlModifier;
    const bool shift = mods & Qt::ShiftModifier;
    const bool alt = mods & Qt::AltModifier;

    const int page = qMax(1, m_rows - 1);
    // 视图回看滚动（Shift+翻页/方向键，任何状态可用）
    if (shift && (key == Qt::Key_PageUp || key == Qt::Key_PageDown ||
                  key == Qt::Key_Up || key == Qt::Key_Down)) {
        if (key == Qt::Key_PageUp)
            scrollView(-page);
        else if (key == Qt::Key_PageDown)
            scrollView(page);
        else if (key == Qt::Key_Up)
            scrollView(-1);
        else
            scrollView(1);
        event->accept();
        return;
    }
    if (!m_sessionActive) {
        // 断线状态：方向/翻页键用于回看历史输出
        if (key == Qt::Key_PageUp)
            scrollView(-page);
        else if (key == Qt::Key_PageDown)
            scrollView(page);
        else if (key == Qt::Key_Up)
            scrollView(-1);
        else if (key == Qt::Key_Down)
            scrollView(1);
        event->accept();
        return;
    }

    // 复制/粘贴
    if (ctrl && shift && key == Qt::Key_C) {
        copySelection();
        event->accept();
        return;
    }
    if (ctrl && shift && key == Qt::Key_V) {
        pasteClipboard(false);
        event->accept();
        return;
    }
    if (ctrl && !shift && !alt && key == Qt::Key_C && m_hasSelection) {
        copySelection();
        event->accept();
        return;
    }
    if (ctrl && key == Qt::Key_Insert) {
        copySelection();
        event->accept();
        return;
    }
    if (shift && key == Qt::Key_Insert) {
        pasteClipboard(false);
        event->accept();
        return;
    }

    const int modNum = 1 + (shift ? 1 : 0) + (alt ? 2 : 0) + (ctrl ? 4 : 0);
    auto cursorSeq = [this, modNum](char final) -> QByteArray {
        if (modNum > 1)
            return QByteArray("\x1b[1;") + QByteArray::number(modNum) + final;
        if (m_appCursor)
            return QByteArray("\x1bO") + final;
        return QByteArray("\x1b[") + final;
    };

    QByteArray data;
    switch (key) {
    case Qt::Key_Return: case Qt::Key_Enter: data = "\r"; break;
    case Qt::Key_Backspace: data = ctrl ? QByteArray(1, char(0x08)) : QByteArray(1, char(0x7f)); break;
    case Qt::Key_Tab: data = QByteArray(1, '\t'); break;
    case Qt::Key_Backtab: data = "\x1b[Z"; break;
    case Qt::Key_Escape: data = QByteArray(1, char(0x1b)); break;
    case Qt::Key_Up: data = cursorSeq('A'); break;
    case Qt::Key_Down: data = cursorSeq('B'); break;
    case Qt::Key_Right: data = cursorSeq('C'); break;
    case Qt::Key_Left: data = cursorSeq('D'); break;
    case Qt::Key_Home: data = m_appCursor ? "\x1bOH" : "\x1b[H"; break;
    case Qt::Key_End: data = m_appCursor ? "\x1bOF" : "\x1b[F"; break;
    case Qt::Key_Insert: data = "\x1b[2~"; break;
    case Qt::Key_Delete: data = "\x1b[3~"; break;
    case Qt::Key_PageUp: data = "\x1b[5~"; break;
    case Qt::Key_PageDown: data = "\x1b[6~"; break;
    case Qt::Key_F1: data = "\x1bOP"; break;
    case Qt::Key_F2: data = "\x1bOQ"; break;
    case Qt::Key_F3: data = "\x1bOR"; break;
    case Qt::Key_F4: data = "\x1bOS"; break;
    case Qt::Key_F5: data = "\x1b[15~"; break;
    case Qt::Key_F6: data = "\x1b[17~"; break;
    case Qt::Key_F7: data = "\x1b[18~"; break;
    case Qt::Key_F8: data = "\x1b[19~"; break;
    case Qt::Key_F9: data = "\x1b[20~"; break;
    case Qt::Key_F10: data = "\x1b[21~"; break;
    case Qt::Key_F11: data = "\x1b[23~"; break;
    case Qt::Key_F12: data = "\x1b[24~"; break;
    case Qt::Key_Space:
        if (ctrl && !alt)
            data = QByteArray(1, char(0));
        break;
    default:
        break;
    }

    if (data.isEmpty() && ctrl && !alt) {
        if (key >= Qt::Key_A && key <= Qt::Key_Z)
            data = QByteArray(1, char(key - Qt::Key_A + 1));
        else if (key == Qt::Key_BracketLeft)
            data = QByteArray(1, char(0x1b));
        else if (key == Qt::Key_Backslash)
            data = QByteArray(1, char(0x1c));
        else if (key == Qt::Key_BracketRight)
            data = QByteArray(1, char(0x1d));
        else if (key == Qt::Key_AsciiCircum)
            data = QByteArray(1, char(0x1e));
        else if (key == Qt::Key_Underscore)
            data = QByteArray(1, char(0x1f));
        else if (key == Qt::Key_2 || key == Qt::Key_At)
            data = QByteArray(1, char(0));
        else if (key == Qt::Key_6)
            data = QByteArray(1, char(0x1e));
        else if (key == Qt::Key_Slash)
            data = QByteArray(1, char(0x1f));
        else if (key == Qt::Key_8)
            data = QByteArray(1, char(0x7f));
    }
    if (data.isEmpty() && alt && !ctrl) {
        const QString t = event->text();
        if (!t.isEmpty())
            data = QByteArray(1, char(0x1b)) + t.toUtf8();
    }
    if (data.isEmpty() && !ctrl && !alt) {
        const QString t = event->text();
        if (!t.isEmpty())
            data = t.toUtf8();
    }

    if (data.isEmpty()) {
        event->ignore();
        return;
    }
    scrollView(1000000);                                              // 输入即回到底部
    emit dataToSend(data);
    event->accept();
}

void TerminalView::inputMethodEvent(QInputMethodEvent *event)
{
    if (!event->commitString().isEmpty()) {
        m_preedit.clear();
        if (m_sessionActive) {
            scrollView(1000000);
            emit dataToSend(event->commitString().toUtf8());
        }
    } else {
        m_preedit = event->preeditString();
    }
    update();
    event->accept();
}

QVariant TerminalView::inputMethodQuery(Qt::InputMethodQuery query) const
{
    switch (query) {
    case Qt::ImEnabled:
        return m_sessionActive;
    case Qt::ImCursorRectangle: {
        const int topAbs = totalLines() - m_rows - m_viewOffset;
        const int viewRow = absOfScreenRow(m_curRow) - topAbs;
        return QRectF(m_curCol * m_cellW, viewRow * m_cellH, m_cellW, m_cellH);
    }
    case Qt::ImHints:
        return int(Qt::ImhNoAutoUppercase | Qt::ImhNoPredictiveText | Qt::ImhMultiLine);
    default:
        return QQuickItem::inputMethodQuery(query);
    }
}

void TerminalView::focusInEvent(QFocusEvent *event)
{
    QQuickItem::focusInEvent(event);
    update();
}

void TerminalView::focusOutEvent(QFocusEvent *event)
{
    m_preedit.clear();
    QQuickItem::focusOutEvent(event);
    update();
}

// ———————————————————————— 鼠标 ————————————————————————

void TerminalView::cellFromPos(const QPointF &pos, int &abs, int &col) const
{
    const int viewRow = qBound(0, int(pos.y() / m_cellH), m_rows - 1);
    const int topAbs = totalLines() - m_rows - m_viewOffset;
    abs = topAbs + viewRow;
    col = qBound(0, int(pos.x() / m_cellW), m_cols - 1);
}

void TerminalView::mousePressEvent(QMouseEvent *event)
{
    forceActiveFocus();
    if (event->button() == Qt::MiddleButton) {
        pasteClipboard(true);
        event->accept();
        return;
    }
    if (event->button() != Qt::LeftButton) {
        event->ignore();
        return;
    }
    int abs = 0;
    int col = 0;
    cellFromPos(event->localPos(), abs, col);
    m_selecting = true;
    m_selStartLine = m_selEndLine = abs;
    m_selStartCol = m_selEndCol = col;
    m_hasSelection = false;
    update();
    event->accept();
}

void TerminalView::mouseMoveEvent(QMouseEvent *event)
{
    if (!m_selecting) {
        event->ignore();
        return;
    }
    int abs = 0;
    int col = 0;
    cellFromPos(event->localPos(), abs, col);
    if (abs != m_selEndLine || col != m_selEndCol) {
        m_selEndLine = abs;
        m_selEndCol = col;
        m_hasSelection = !(m_selStartLine == m_selEndLine && m_selStartCol == m_selEndCol);
        update();
    }
    event->accept();
}

void TerminalView::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && m_selecting) {
        m_selecting = false;
        m_hasSelection = !(m_selStartLine == m_selEndLine && m_selStartCol == m_selEndCol);
        update();
        event->accept();
        return;
    }
    event->ignore();
}

void TerminalView::wheelEvent(QWheelEvent *event)
{
    const int dy = event->angleDelta().y();
    if (dy == 0) {
        event->ignore();
        return;
    }
    scrollView(dy > 0 ? -3 : 3);
    event->accept();
}

// ———————————————————————— 选择与剪贴板 ————————————————————————

void TerminalView::clearSelection()
{
    m_selecting = false;
    m_hasSelection = false;
    m_selStartLine = m_selEndLine = -1;
    m_selStartCol = m_selEndCol = 0;
}

void TerminalView::selectionRange(int &l0, int &c0, int &l1, int &c1) const
{
    if (m_selStartLine < m_selEndLine ||
        (m_selStartLine == m_selEndLine && m_selStartCol <= m_selEndCol)) {
        l0 = m_selStartLine;
        c0 = m_selStartCol;
        l1 = m_selEndLine;
        c1 = m_selEndCol;
    } else {
        l0 = m_selEndLine;
        c0 = m_selEndCol;
        l1 = m_selStartLine;
        c1 = m_selStartCol;
    }
}

bool TerminalView::inSelection(int abs, int col) const
{
    if (!m_hasSelection)
        return false;
    int l0, c0, l1, c1;
    selectionRange(l0, c0, l1, c1);
    if (abs < l0 || abs > l1)
        return false;
    if (abs == l0 && col < c0)
        return false;
    if (abs == l1 && col > c1)
        return false;
    return true;
}

QString TerminalView::selectionText() const
{
    if (!m_hasSelection)
        return QString();
    int l0, c0, l1, c1;
    selectionRange(l0, c0, l1, c1);
    QString out;
    static const Line kBlankLine;
    for (int abs = l0; abs <= l1; ++abs) {
        const Line *line = lineAt(abs);
        const Line &ln = line ? *line : kBlankLine;
        const int end = (abs == l1) ? c1 : m_cols - 1;
        QString s;
        for (int col = c0; col <= end; ++col) {
            const Cell &c = cellRef(ln, col);
            if (c.cont)
                continue;
            appendUtf16(s, c.ch);
        }
        while (s.endsWith(QLatin1Char(' ')))
            s.chop(1);
        out += s;
        const bool wrapped = line && line->wrapped && abs != l1;
        if (abs != l1 && !wrapped)
            out += QLatin1Char('\n');
    }
    return out;
}

void TerminalView::copySelection()
{
    const QString text = selectionText();
    if (text.isEmpty())
        return;
    QGuiApplication::clipboard()->setText(text, QClipboard::Clipboard);
    QGuiApplication::clipboard()->setText(text, QClipboard::Selection);
}

void TerminalView::pasteClipboard(bool primary)
{
    if (!m_sessionActive)
        return;
    const QClipboard *cb = QGuiApplication::clipboard();
    QString text = cb->text(primary ? QClipboard::Selection : QClipboard::Clipboard);
    if (text.isEmpty())
        return;
    text.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
    text.replace(QLatin1Char('\n'), QLatin1Char('\r'));
    QByteArray payload = text.toUtf8();
    if (m_bracketedPaste)
        payload = QByteArrayLiteral("\x1b[200~") + payload + QByteArrayLiteral("\x1b[201~");
    scrollView(1000000);
    emit dataToSend(payload);
}

// ———————————————————————— 渲染 ————————————————————————

void TerminalView::componentComplete()
{
    QQuickItem::componentComplete();
    ensureFont();
    updateGridSize();
}

void TerminalView::geometryChanged(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChanged(newGeometry, oldGeometry);
    if (!m_fontReady)
        ensureFont();
    updateGridSize();
    update();
}

const QFont &TerminalView::fontFor(quint8 flags) const
{
    if ((flags & FlagBold) && (flags & FlagItalic))
        return m_fontBoldItalic;
    if (flags & FlagBold)
        return m_fontBold;
    if (flags & FlagItalic)
        return m_fontItalic;
    return m_fontBase;
}

void TerminalView::paint(QPainter *p)
{
    if (!m_fontReady)
        ensureFont();
    p->fillRect(contentsBoundingRect(), QColor::fromRgba(kDefaultBg));
    if (!m_fontReady)
        return;
    p->setRenderHint(QPainter::TextAntialiasing, true);
    const int topAbs = totalLines() - m_rows - m_viewOffset;
    for (int row = 0; row < m_rows; ++row)
        drawLine(p, topAbs + row, row);
    drawCursor(p, topAbs);
    drawScrollIndicator(p);
}

void TerminalView::drawLine(QPainter *p, int abs, int viewRow)
{
    const Line *line = lineAt(abs);
    static const Line kBlank;
    const Line &ln = line ? *line : kBlank;
    const qreal y = viewRow * m_cellH;

    // 背景色块与选择高亮（按同背景合并成段，减少绘制次数）
    int col = 0;
    while (col < m_cols) {
        const Cell &c = cellRef(ln, col);
        const QRgb bg = effBg(c);
        const bool sel = inSelection(abs, col);
        int runEnd = col + 1;
        while (runEnd < m_cols) {
            const Cell &c2 = cellRef(ln, runEnd);
            if (effBg(c2) != bg || inSelection(abs, runEnd) != sel)
                break;
            ++runEnd;
        }
        const QRectF r(col * m_cellW, y, (runEnd - col) * m_cellW, m_cellH);
        if (bg != kDefaultBg)
            p->fillRect(r, QColor::fromRgba(bg));
        if (sel)
            p->fillRect(r, kSelectionColor);
        col = runEnd;
    }

    // 前景文字（同字体同色聚合成串）
    col = 0;
    while (col < m_cols) {
        const Cell &c = cellRef(ln, col);
        if (c.cont || c.ch == U' ' || (c.flags & FlagHidden)) {
            ++col;
            continue;
        }
        const QFont &f = fontFor(c.flags);
        const QRgb fg = effFg(c);
        const bool wide = (col + 1 < m_cols) && cellRef(ln, col + 1).cont;
        if (wide) {
            const uint u = uint(c.ch);
            p->setFont(f);
            p->setPen(QColor::fromRgba(fg));
            p->drawText(QPointF(col * m_cellW, y + m_ascent), QString::fromUcs4(&u, 1));
            if (c.flags & (FlagUnderline | FlagStrike)) {
                const qreal x0 = col * m_cellW;
                const qreal x1 = (col + 2) * m_cellW;
                if (c.flags & FlagUnderline)
                    p->fillRect(QRectF(x0, y + m_cellH - 2, x1 - x0, 1.0), QColor::fromRgba(fg));
                if (c.flags & FlagStrike)
                    p->fillRect(QRectF(x0, y + m_cellH * 0.55, x1 - x0, 1.0), QColor::fromRgba(fg));
            }
            ++col;
            continue;
        }
        const quint8 attr = c.flags & (FlagBold | FlagItalic | FlagUnderline | FlagStrike);
        const int start = col;
        QString s;
        while (col < m_cols) {
            const Cell &d = cellRef(ln, col);
            if (d.cont || d.ch == U' ' || (d.flags & FlagHidden))
                break;
            if ((d.flags & (FlagBold | FlagItalic | FlagUnderline | FlagStrike)) != attr ||
                effFg(d) != fg)
                break;
            if (col + 1 < m_cols && cellRef(ln, col + 1).cont)
                break;                                                // 宽字符单独画
            appendUtf16(s, d.ch);
            ++col;
        }
        if (s.isEmpty()) {
            ++col;
            continue;
        }
        p->setFont(f);
        p->setPen(QColor::fromRgba(fg));
        p->drawText(QPointF(start * m_cellW, y + m_ascent), s);
        if (attr & (FlagUnderline | FlagStrike)) {
            const qreal x0 = start * m_cellW;
            const qreal x1 = col * m_cellW;
            if (attr & FlagUnderline)
                p->fillRect(QRectF(x0, y + m_cellH - 2, x1 - x0, 1.0), QColor::fromRgba(fg));
            if (attr & FlagStrike)
                p->fillRect(QRectF(x0, y + m_cellH * 0.55, x1 - x0, 1.0), QColor::fromRgba(fg));
        }
    }
}

void TerminalView::drawCursor(QPainter *p, int topAbs)
{
    if (!m_cursorVisible || !hasActiveFocus())
        return;
    const int abs = absOfScreenRow(m_curRow);
    const int viewRow = abs - topAbs;
    if (viewRow < 0 || viewRow >= m_rows)
        return;
    const qreal x = m_curCol * m_cellW;
    const qreal y = viewRow * m_cellH;
    if (!m_preedit.isEmpty()) {
        // 输入法预编辑：候选串加下划线，右侧补一个空心框示意
        p->setFont(m_fontBase);
        p->setPen(QColor::fromRgba(kDefaultFg));
        p->drawText(QPointF(x, y + m_ascent), m_preedit);
        const qreal w = QFontMetricsF(m_fontBase).horizontalAdvance(m_preedit);
        p->drawRect(QRectF(x + w, y, m_cellW, m_cellH));
        return;
    }
    static const Line kBlank;
    const Line *line = lineAt(abs);
    const Cell &c = cellRef(line ? *line : kBlank, m_curCol);
    p->fillRect(QRectF(x, y, m_cellW, m_cellH), QColor::fromRgba(kCursorColor));
    if (c.ch != U' ' && !c.cont && !(c.flags & FlagHidden)) {
        p->setFont(fontFor(c.flags));
        p->setPen(QColor::fromRgba(effBg(c)));
        if (c.ch < 0x10000)
            p->drawText(QPointF(x, y + m_ascent), QString(QChar(ushort(c.ch))));
        else {
            const uint u = uint(c.ch);
            p->drawText(QPointF(x, y + m_ascent), QString::fromUcs4(&u, 1));
        }
    }
}

void TerminalView::drawScrollIndicator(QPainter *p)
{
    const int total = totalLines();
    if (m_altScreen || total <= m_rows)
        return;
    const qreal h = height();
    const qreal track = 4.0;
    const qreal thumbH = qMax(28.0, h * qreal(m_rows) / qreal(total));
    const int maxOff = total - m_rows;
    const qreal t = maxOff > 0 ? qreal(maxOff - m_viewOffset) / qreal(maxOff) : 1.0;
    const qreal y = (h - thumbH) * t;
    p->fillRect(QRectF(width() - track - 1.0, y, track, thumbH), QColor(255, 255, 255, 46));
}
