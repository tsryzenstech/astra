// SPDX-License-Identifier: Apache-2.0
#include "vtscreen.h"

#include <algorithm>

namespace astra::desktop {

namespace {
const Cell kBlank;
constexpr size_t kMaxHistory = 5000;

// The 16 colours of the terminal (a dark, neutral palette), then the 6x6x6 cube and the greys of the 256 colours.
quint32 xterm256(int n)
{
    static const quint32 base[16] = {0x1E1E22, 0xE5484D, 0x34C759, 0xF5A524, 0x4C8DFF, 0xB26BFF, 0x2ED3C6, 0xD0D0D6,
                                     0x6B6B73, 0xFF6369, 0x4ADE80, 0xFFC53D, 0x7AA8FF, 0xCB94FF, 0x5FE3D8, 0xFFFFFF};
    if (n < 16)
        return 0xFF000000 | base[n];
    if (n < 232) {
        n -= 16;
        const int r = n / 36, g = (n / 6) % 6, b = n % 6;
        auto v = [](int x) { return x == 0 ? 0 : 55 + 40 * x; };
        return 0xFF000000 | (v(r) << 16) | (v(g) << 8) | v(b);
    }
    const int g = 8 + (n - 232) * 10;
    return 0xFF000000 | (g << 16) | (g << 8) | g;
}
} // namespace

VtScreen::VtScreen(int cols, int rows)
    : m_cols(cols)
    , m_rows(rows)
    , m_bottom(rows - 1)
{
    m_screen.fill(blankLine(), rows);
    m_alt.fill(blankLine(), rows);
    m_tabs.fill(false, cols);
    for (int i = 8; i < cols; i += 8)
        m_tabs[i] = true;
}

VtScreen::Line VtScreen::blankLine() const
{
    Line l(m_cols);
    for (Cell &c : l) {
        c.bg = m_pen.bg;   // erased with the current background
    }
    return l;
}

void VtScreen::resize(int cols, int rows)
{
    cols = std::max(2, cols);
    rows = std::max(2, rows);
    if (cols == m_cols && rows == m_rows)
        return;
    auto fix = [&](QVector<Line> &s) {
        for (Line &l : s)
            l.resize(cols);
        // Fewer rows: the top lines go to the history (the shell's last lines stay); more: blank lines at the bottom.
        while (s.size() > rows) {
            if (&s == &m_screen && !m_onAlt) {
                m_history.push_back(s.first());
                if (m_history.size() > kMaxHistory)
                    m_history.pop_front();
                if (m_y > 0)
                    --m_y;
            }
            s.removeFirst();
        }
        while (s.size() < rows)
            s.append(Line(cols));
    };
    m_cols = cols;
    fix(m_screen);
    fix(m_alt);
    m_rows = rows;
    m_top = 0;
    m_bottom = rows - 1;
    m_tabs.fill(false, cols);
    for (int i = 8; i < cols; i += 8)
        m_tabs[i] = true;
    clampCursor();
    if (changed)
        changed();
}

const Cell &VtScreen::cell(int col, int row, int offset) const
{
    if (col < 0 || col >= m_cols || row < 0 || row >= m_rows)
        return kBlank;
    if (offset > 0) {
        const int h = int(m_history.size());
        const int idx = h - offset + row;       // an index into history + screen
        if (idx < 0)
            return kBlank;
        if (idx < h) {
            const Line &l = m_history[size_t(idx)];
            return col < l.size() ? l[col] : kBlank;
        }
        return m_screen[idx - h][col];
    }
    return (m_onAlt ? m_alt : m_screen)[row][col];
}

QString VtScreen::text(int c0, int r0, int c1, int r1, int offset) const
{
    QString out;
    for (int r = r0; r <= r1; ++r) {
        const int from = r == r0 ? c0 : 0, to = r == r1 ? c1 : m_cols - 1;
        QString line;
        for (int c = from; c <= to; ++c)
            line += QString::fromUcs4(&cell(c, r, offset).ch, 1);
        while (line.endsWith(QLatin1Char(' ')))
            line.chop(1);
        out += line;
        if (r != r1)
            out += QLatin1Char('\n');
    }
    return out;
}

void VtScreen::clampCursor()
{
    m_x = std::clamp(m_x, 0, m_cols - 1);
    m_y = std::clamp(m_y, 0, m_rows - 1);
}

void VtScreen::switchScreen(bool alt)
{
    if (alt == m_onAlt)
        return;
    m_onAlt = alt;
    if (alt)
        m_alt.fill(blankLine(), m_rows);
    if (changed)
        changed();
}

// ---- drawing -------------------------------------------------------------------------------------------------------

void VtScreen::put(char32_t ch)
{
    QVector<Line> &s = m_onAlt ? m_alt : m_screen;
    if (m_wrapPending && m_autowrap) {
        m_x = 0;
        lineFeed();
    }
    m_wrapPending = false;
    Cell c = m_pen;
    c.ch = ch;
    s[m_y][m_x] = c;
    if (m_x == m_cols - 1)
        m_wrapPending = true;
    else
        ++m_x;
}

void VtScreen::scrollUp(int n)
{
    QVector<Line> &s = m_onAlt ? m_alt : m_screen;
    for (int i = 0; i < n; ++i) {
        // The lines that leave the top of the whole screen (not of a region) are kept for scrolling back.
        if (m_top == 0 && !m_onAlt) {
            m_history.push_back(s[0]);
            if (m_history.size() > kMaxHistory)
                m_history.pop_front();
        }
        s.remove(m_top);
        s.insert(m_bottom, blankLine());
    }
}

void VtScreen::scrollDown(int n)
{
    QVector<Line> &s = m_onAlt ? m_alt : m_screen;
    for (int i = 0; i < n; ++i) {
        s.remove(m_bottom);
        s.insert(m_top, blankLine());
    }
}

void VtScreen::lineFeed()
{
    if (m_y == m_bottom)
        scrollUp(1);
    else if (m_y < m_rows - 1)
        ++m_y;
}

void VtScreen::reverseIndex()
{
    if (m_y == m_top)
        scrollDown(1);
    else if (m_y > 0)
        --m_y;
}

void VtScreen::eraseLine(int from, int to, int row)
{
    QVector<Line> &s = m_onAlt ? m_alt : m_screen;
    for (int c = std::max(0, from); c <= std::min(to, m_cols - 1); ++c) {
        Cell blank;
        blank.bg = m_pen.bg;
        s[row][c] = blank;
    }
}

// ---- sequences -------------------------------------------------------------------------------------------------------

void VtScreen::sgr(const QVector<int> &p)
{
    if (p.isEmpty()) {
        m_pen = Cell();
        return;
    }
    for (int i = 0; i < p.size(); ++i) {
        const int v = p[i];
        if (v == 0) m_pen = Cell();
        else if (v == 1) m_pen.attrs |= Bold;
        else if (v == 3) m_pen.attrs |= Italic;
        else if (v == 4) m_pen.attrs |= Underline;
        else if (v == 7) m_pen.attrs |= Reverse;
        else if (v == 22) m_pen.attrs &= ~Bold;
        else if (v == 23) m_pen.attrs &= ~Italic;
        else if (v == 24) m_pen.attrs &= ~Underline;
        else if (v == 27) m_pen.attrs &= ~Reverse;
        else if (v >= 30 && v <= 37) m_pen.fg = xterm256(v - 30);
        else if (v == 39) m_pen.fg = 0;
        else if (v >= 40 && v <= 47) m_pen.bg = xterm256(v - 40);
        else if (v == 49) m_pen.bg = 0;
        else if (v >= 90 && v <= 97) m_pen.fg = xterm256(v - 90 + 8);
        else if (v >= 100 && v <= 107) m_pen.bg = xterm256(v - 100 + 8);
        else if (v == 38 || v == 48) {
            quint32 color = 0;
            if (i + 2 < p.size() && p[i + 1] == 5) {
                color = xterm256(std::clamp(p[i + 2], 0, 255));
                i += 2;
            } else if (i + 4 < p.size() && p[i + 1] == 2) {
                color = 0xFF000000 | (quint32(std::clamp(p[i + 2], 0, 255)) << 16) | (quint32(std::clamp(p[i + 3], 0, 255)) << 8) | quint32(std::clamp(p[i + 4], 0, 255));
                i += 4;
            } else {
                break;
            }
            (v == 38 ? m_pen.fg : m_pen.bg) = color;
        }
    }
}

void VtScreen::setMode(const QVector<int> &p, bool on, bool priv)
{
    for (int v : p) {
        if (!priv)
            continue;
        switch (v) {
        case 1: m_appCursor = on; break;
        case 6: m_originMode = on; m_x = 0; m_y = on ? m_top : 0; break;
        case 7: m_autowrap = on; break;
        case 25: m_cursorVisible = on; break;
        case 47: case 1047: switchScreen(on); break;
        case 1049:
            if (on) { m_savedX = m_x; m_savedY = m_y; switchScreen(true); m_x = m_y = 0; }
            else { switchScreen(false); m_x = m_savedX; m_y = m_savedY; clampCursor(); }
            break;
        case 2004: m_bracketed = on; break;
        default: break;
        }
    }
}

void VtScreen::csi(char final)
{
    bool priv = false;
    QByteArray params = m_params;
    if (!params.isEmpty() && (params[0] == '?' || params[0] == '>' || params[0] == '=')) {
        priv = params[0] == '?';
        params.remove(0, 1);
    }
    QVector<int> p;
    for (const QByteArray &part : params.split(';'))
        p.append(part.isEmpty() ? -1 : part.split(':').first().toInt());
    auto arg = [&](int i, int def) { return i < p.size() && p[i] > 0 ? p[i] : def; };
    QVector<Line> &s = m_onAlt ? m_alt : m_screen;
    m_wrapPending = final == 'm' ? m_wrapPending : false;
    switch (final) {
    case 'A': m_y = std::max(m_top, m_y - arg(0, 1)); break;
    case 'B': m_y = std::min(m_bottom, m_y + arg(0, 1)); break;
    case 'C': m_x = std::min(m_cols - 1, m_x + arg(0, 1)); break;
    case 'D': m_x = std::max(0, m_x - arg(0, 1)); break;
    case 'E': m_x = 0; m_y = std::min(m_bottom, m_y + arg(0, 1)); break;
    case 'F': m_x = 0; m_y = std::max(m_top, m_y - arg(0, 1)); break;
    case 'G': m_x = arg(0, 1) - 1; break;
    case 'd': m_y = arg(0, 1) - 1 + (m_originMode ? m_top : 0); break;
    case 'H': case 'f': m_y = arg(0, 1) - 1 + (m_originMode ? m_top : 0); m_x = arg(1, 1) - 1; break;
    case 'J': {
        const int mode = p.isEmpty() || p[0] < 0 ? 0 : p[0];
        if (mode == 0) { eraseLine(m_x, m_cols - 1, m_y); for (int r = m_y + 1; r < m_rows; ++r) eraseLine(0, m_cols - 1, r); }
        else if (mode == 1) { for (int r = 0; r < m_y; ++r) eraseLine(0, m_cols - 1, r); eraseLine(0, m_x, m_y); }
        else { for (int r = 0; r < m_rows; ++r) eraseLine(0, m_cols - 1, r); if (mode == 3) m_history.clear(); }
        break;
    }
    case 'K': {
        const int mode = p.isEmpty() || p[0] < 0 ? 0 : p[0];
        if (mode == 0) eraseLine(m_x, m_cols - 1, m_y);
        else if (mode == 1) eraseLine(0, m_x, m_y);
        else eraseLine(0, m_cols - 1, m_y);
        break;
    }
    case 'L': if (m_y >= m_top && m_y <= m_bottom) { for (int i = 0; i < arg(0, 1); ++i) { s.remove(m_bottom); s.insert(m_y, blankLine()); } } break;
    case 'M': if (m_y >= m_top && m_y <= m_bottom) { for (int i = 0; i < arg(0, 1); ++i) { s.remove(m_y); s.insert(m_bottom, blankLine()); } } break;
    case 'P': { const int n = std::min(arg(0, 1), m_cols - m_x); for (int c = m_x; c < m_cols; ++c) s[m_y][c] = c + n < m_cols ? s[m_y][c + n] : Cell(); break; }
    case '@': { const int n = std::min(arg(0, 1), m_cols - m_x); for (int c = m_cols - 1; c >= m_x; --c) s[m_y][c] = c - n >= m_x ? s[m_y][c - n] : Cell(); break; }
    case 'X': eraseLine(m_x, m_x + arg(0, 1) - 1, m_y); break;
    case 'S': scrollUp(arg(0, 1)); break;
    case 'T': scrollDown(arg(0, 1)); break;
    case 'm': sgr(p); break;
    case 'r': {
        const int top = arg(0, 1) - 1, bottom = arg(1, m_rows) - 1;
        if (top < bottom && bottom < m_rows) { m_top = top; m_bottom = bottom; }
        m_x = 0; m_y = m_originMode ? m_top : 0;
        break;
    }
    case 's': m_savedX = m_x; m_savedY = m_y; break;
    case 'u': m_x = m_savedX; m_y = m_savedY; break;
    case 'h': setMode(p, true, priv); break;
    case 'l': setMode(p, false, priv); break;
    case 'c': if (reply && !priv) reply("\x1b[?62;c"); break;
    case 'n':
        if (reply && !p.isEmpty() && p[0] == 6)
            reply(QByteArray("\x1b[") + QByteArray::number(m_y + 1 - (m_originMode ? m_top : 0)) + ';' + QByteArray::number(m_x + 1) + 'R');
        else if (reply && !p.isEmpty() && p[0] == 5)
            reply("\x1b[0n");
        break;
    case 'g': if (!p.isEmpty() && p[0] == 3) m_tabs.fill(false, m_cols); else if (m_x < m_tabs.size()) m_tabs[m_x] = false; break;
    default: break;
    }
    clampCursor();
}

void VtScreen::osc(const QString &s)
{
    const int semi = s.indexOf(QLatin1Char(';'));
    if (semi < 0)
        return;
    const int code = s.left(semi).toInt();
    if (code == 0 || code == 2) {
        m_title = s.mid(semi + 1);
        if (titleChanged)
            titleChanged(m_title);
    }
}

void VtScreen::write(const QByteArray &data)
{
    for (const unsigned char b : data) {
        switch (m_state) {
        case Ground:
            if (m_utfLeft > 0) {
                if ((b & 0xC0) == 0x80) {
                    m_utf = (m_utf << 6) | (b & 0x3F);
                    if (--m_utfLeft == 0)
                        put(m_utf);
                    continue;
                }
                m_utfLeft = 0;   // a broken sequence: start again with this byte
            }
            if (b == 0x1B) m_state = Esc;
            else if (b == '\n' || b == 0x0B || b == 0x0C) { m_wrapPending = false; lineFeed(); }
            else if (b == '\r') { m_x = 0; m_wrapPending = false; }
            else if (b == '\b') { if (m_x > 0) --m_x; m_wrapPending = false; }
            else if (b == '\t') { int x = m_x + 1; while (x < m_cols - 1 && !m_tabs[x]) ++x; m_x = std::min(x, m_cols - 1); }
            else if (b == 0x07) { /* bell */ }
            else if (b >= 0x20 && b < 0x7F) put(b);
            else if (b >= 0xC2 && b < 0xE0) { m_utf = b & 0x1F; m_utfLeft = 1; }
            else if (b >= 0xE0 && b < 0xF0) { m_utf = b & 0x0F; m_utfLeft = 2; }
            else if (b >= 0xF0 && b < 0xF5) { m_utf = b & 0x07; m_utfLeft = 3; }
            break;
        case Esc:
            m_state = Ground;
            if (b == '[') { m_state = CsiState; m_params.clear(); }
            else if (b == ']') { m_state = OscState; m_osc.clear(); }
            else if (b == '(' || b == ')' || b == '*' || b == '+' || b == '#' || b == '%') m_state = EscSkip;
            else if (b == 'M') reverseIndex();
            else if (b == 'D') lineFeed();
            else if (b == 'E') { m_x = 0; lineFeed(); }
            else if (b == '7') { m_savedX = m_x; m_savedY = m_y; }
            else if (b == '8') { m_x = m_savedX; m_y = m_savedY; clampCursor(); }
            else if (b == 'c') { auto r = reply; auto ch = changed; auto tc = titleChanged; *this = VtScreen(m_cols, m_rows); reply = r; changed = ch; titleChanged = tc; }
            else if (b == 'H') { if (m_x < m_tabs.size()) m_tabs[m_x] = true; }
            else if (b == '=' || b == '>') { /* keypad modes */ }
            break;
        case EscSkip:
            m_state = Ground;
            break;
        case CsiState:
            if (b >= 0x40 && b <= 0x7E) { m_state = Ground; csi(char(b)); }
            else if (m_params.size() < 64) m_params.append(char(b));
            break;
        case OscState:
            if (b == 0x07) { m_state = Ground; osc(m_osc); }
            else if (b == 0x1B) m_state = OscEsc;
            else if (m_osc.size() < 512) m_osc.append(QChar(b));
            break;
        case OscEsc:
            m_state = Ground;
            osc(m_osc);
            if (b == '[') m_state = CsiState, m_params.clear();
            break;
        }
    }
    if (changed)
        changed();
}

} // namespace astra::desktop
