#pragma once

#include <QtQuick/QQuickPaintedItem>

#include <QByteArray>
#include <QFont>
#include <QHash>
#include <QRgb>
#include <QString>
#include <QVector>

class QInputMethodEvent;

// 自绘终端视图（VT100/xterm 常用子集）：
//  · 网格字符缓冲 + ANSI 转义解析：光标移动/擦除、SGR 颜色（16/256/真彩）、
//    加粗/斜体/下划线/反显、滚动区域、备用屏（vim/top 等全屏程序）
//  · UTF-8 流式解码（跨读取块续读，中文不乱码）与 CJK 宽字符占位
//  · 回滚缓冲、滚轮/翻页回看、拖选复制、IME（中文输入法）接入
//  · 输入输出与 ShellSession 以原始字节直连，不经 QML 字符串转换
class TerminalView : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(int fontSize READ fontSize WRITE setFontSize NOTIFY fontSizeChanged)

public:
    explicit TerminalView(QQuickItem *parent = nullptr);
    ~TerminalView() override;

    int fontSize() const { return m_fontSize; }
    void setFontSize(int px);

    void paint(QPainter *painter) override;

    Q_INVOKABLE void resetSession();            // 新会话：清屏、清回滚、复位解析状态
    Q_INVOKABLE void clearBuffer();             // 「清空」按钮：清屏 + 清回滚
    Q_INVOKABLE void setSessionActive(bool on); // 会话在线时按键才发往远端
    Q_INVOKABLE bool sessionActive() const { return m_sessionActive; }
    Q_INVOKABLE void reportTerminalSize();      // 向 ShellSession 重新上报当前行列数
    Q_INVOKABLE void scrollView(int lines);     // 回看滚动：正数向下、负数向上

public slots:
    void processOutput(const QByteArray &data); // 远程输出字节流（ShellSession 直连）

signals:
    void dataToSend(const QByteArray &data);    // 键盘/粘贴/终端应答 → ShellSession
    void terminalResized(int cols, int rows);
    void fontSizeChanged();

protected:
    void componentComplete() override;
    void geometryChanged(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void keyPressEvent(QKeyEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;

public:
    struct Cell {
        char32_t ch = U' ';
        QRgb fg = 0;          // alpha=0：默认前景色
        QRgb bg = 0;          // alpha=0：默认背景色
        quint8 flags = 0;     // CellFlag 位
        bool cont = false;    // 宽字符第二格（不渲染字形）
    };
    struct Line {
        QVector<Cell> cells;
        bool wrapped = false; // 该行由自动换行折到下一行（复制时不补换行）
    };
    enum CellFlag {
        FlagBold      = 0x01,
        FlagUnderline = 0x02,
        FlagItalic    = 0x04,
        FlagReverse   = 0x08,
        FlagHidden    = 0x10,
        FlagStrike    = 0x20,
    };

private:
    enum ParseState { StGround, StEsc, StEscSkip, StCsi, StOsc };

    // —— 字体与画布度量 ——
    void ensureFont();
    void recomputeMetrics();
    void updateGridSize();
    void applySize(int cols, int rows);
    int charWidth(char32_t cp);               // 占位格数：0/1/2（带缓存）

    // —— 网格访问 ——
    int totalLines() const { return m_altScreen ? m_rows : m_scrollback.size() + m_rows; }
    int absOfScreenRow(int row) const { return (m_altScreen ? 0 : m_scrollback.size()) + row; }
    Line *lineAt(int abs);
    const Line *lineAt(int abs) const;
    Line &screenLine(int row) { return m_screen[row]; }
    QVector<Line> blankScreen() const;

    // —— 输出处理 ——
    void feedByte(uchar c);
    void feedGround(uchar c);
    void feedEsc(uchar c);
    void feedCsi(uchar c);
    void feedOsc(uchar c);
    void dispatchCsi(uchar final, bool priv);
    void handleSgr(const QVector<int> &params);
    QVector<int> csiParams() const;

    void putChar(char32_t cp, int w);
    void handleWrap();
    void carriageReturn();
    void lineFeed();
    void backspace();
    void tabForward(int n);
    void tabBackward(int n);
    void scrollUp(int n, bool pushToScrollback);
    void pushScrollback(const Line &line);
    void scrollDown(int n);
    void eraseDisplay(int mode);
    void eraseLine(int mode);
    void clearLine(Line &line, int from, int to);
    void insertLines(int n);
    void deleteLines(int n);
    void insertChars(int n);
    void deleteChars(int n);
    void eraseChars(int n);
    void clampCursor();
    void saveCursor();
    void restoreCursor();
    void enterAltScreen();
    void leaveAltScreen();
    void promptReply(const QByteArray &reply); // DSR/DA 等终端应答（仅在线时发送）

    // —— 选择与剪贴板 ——
    void clearSelection();
    void copySelection();
    void pasteClipboard(bool primary);
    bool inSelection(int abs, int col) const;
    void selectionRange(int &l0, int &c0, int &l1, int &c1) const;
    QString selectionText() const;
    void cellFromPos(const QPointF &pos, int &abs, int &col) const;

    // —— 渲染 ——
    void drawLine(QPainter *p, int abs, int viewRow);
    void drawCursor(QPainter *p, int topAbs);
    void drawScrollIndicator(QPainter *p);
    const QFont &fontFor(quint8 flags) const;

    // —— 网格数据 ——
    QVector<Line> m_screen;      // 活动屏，恒为 m_rows 行
    QVector<Line> m_scrollback;  // 主屏回滚，0 = 最旧
    int m_curRow = 0;
    int m_curCol = 0;
    bool m_wrapPending = false;  // xterm 延迟换行：写满最后一格后等下一个字符
    int m_scrollTop = 0;
    int m_scrollBottom = 0;
    QRgb m_curFg = 0;
    QRgb m_curBg = 0;
    quint8 m_curFlags = 0;
    char32_t m_lastChar = 0;
    int m_lastCharW = 1;
    bool m_appCursor = false;    // DECCKM：方向键 SS3 序列
    bool m_autoWrap = true;
    bool m_bracketedPaste = false;
    bool m_cursorVisible = true;
    bool m_altScreen = false;
    QVector<Line> m_altSavedScreen; // 备用屏现场
    int m_altSavedRow = 0, m_altSavedCol = 0;
    int m_altSavedTop = 0, m_altSavedBottom = 0;
    QRgb m_altSavedFg = 0, m_altSavedBg = 0;
    quint8 m_altSavedFlags = 0;
    bool m_altSavedWrap = false;
    int m_scRow = 0, m_scCol = 0;  // DECSC 保存的光标
    QRgb m_scFg = 0, m_scBg = 0;
    quint8 m_scFlags = 0;
    bool m_scWrap = false;

    // —— 解析状态 ——
    ParseState m_state = StGround;
    QByteArray m_csiParams;      // CSI 参数字节（含前导 ?）
    QByteArray m_utf8Buf;        // UTF-8 跨块续读
    int m_oscLen = 0;

    // —— 视图状态 ——
    int m_cols = 80;
    int m_rows = 24;
    int m_viewOffset = 0;        // 距底部行数（0 = 贴底）
    bool m_sessionActive = false;
    qreal m_cellW = 8.0;
    qreal m_cellH = 18.0;
    qreal m_ascent = 13.0;
    QFont m_fontBase, m_fontBold, m_fontItalic, m_fontBoldItalic;
    bool m_fontReady = false;
    int m_fontSize = 13;
    QHash<uint, int> m_charWidths;

    // —— 选择与 IME ——
    bool m_selecting = false;
    bool m_hasSelection = false;
    int m_selStartLine = -1, m_selStartCol = 0;
    int m_selEndLine = -1, m_selEndCol = 0;
    QString m_preedit;
};
