// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QByteArray>
#include <QString>
#include <QVector>

#include <deque>
#include <functional>

namespace astra::desktop {

// The screen of a terminal: a grid of cells and the VT100 / xterm sequences that change it (cursor movement, erasing,
// scrolling regions, colours 16 / 256 / true colour, bold, underline, reverse, the alternate screen, scrollback, the
// title). It has no idea of windows: TerminalView draws it and feeds it what the shell writes.
struct Cell {
    char32_t ch = U' ';
    quint32 fg = 0;          // 0: the default; else 0xFF000000 | rgb
    quint32 bg = 0;
    quint8 attrs = 0;        // Bold | Underline | Reverse | Italic
};
enum Attr : quint8 { Bold = 1, Underline = 2, Reverse = 4, Italic = 8 };

class VtScreen
{
public:
    VtScreen(int cols = 80, int rows = 24);

    int cols() const { return m_cols; }
    int rows() const { return m_rows; }
    void resize(int cols, int rows);
    // What the shell wrote.
    void write(const QByteArray &data);

    // The visible grid, scrolled `offset` lines back into the history (0: the live screen).
    const Cell &cell(int col, int row, int offset = 0) const;
    int historySize() const { return int(m_history.size()); }
    int cursorCol() const { return m_x; }
    int cursorRow() const { return m_y; }
    bool cursorVisible() const { return m_cursorVisible; }
    bool applicationCursorKeys() const { return m_appCursor; }
    bool bracketedPaste() const { return m_bracketed; }
    QString title() const { return m_title; }
    QString text(int c0, int r0, int c1, int r1, int offset) const;   // for copying

    // Answers the shell asked for (device attributes, cursor position): to be sent back to it.
    std::function<void(const QByteArray &)> reply;
    std::function<void()> changed;
    std::function<void(const QString &)> titleChanged;

private:
    using Line = QVector<Cell>;
    Line blankLine() const;
    void put(char32_t ch);
    void lineFeed();
    void reverseIndex();
    void scrollUp(int n);
    void scrollDown(int n);
    void eraseLine(int from, int to, int row);
    void csi(char final);
    void sgr(const QVector<int> &p);
    void setMode(const QVector<int> &p, bool on, bool priv);
    void osc(const QString &s);
    void switchScreen(bool alt);
    void clampCursor();

    int m_cols, m_rows;
    QVector<Line> m_screen, m_alt;
    std::deque<Line> m_history;
    int m_x = 0, m_y = 0, m_savedX = 0, m_savedY = 0;
    int m_top = 0, m_bottom;              // the scrolling region
    bool m_wrapPending = false, m_autowrap = true, m_originMode = false;
    bool m_cursorVisible = true, m_appCursor = false, m_bracketed = false, m_onAlt = false;
    Cell m_pen;
    QString m_title;
    QVector<bool> m_tabs;

    // The parser.
    enum State { Ground, Esc, EscSkip, CsiState, OscState, OscEsc } m_state = Ground;
    QByteArray m_params;
    QString m_osc;
    quint32 m_utf = 0;
    int m_utfLeft = 0;
};

} // namespace astra::desktop
