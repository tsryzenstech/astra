// SPDX-License-Identifier: Apache-2.0
#include "terminalview.h"

#include <astra/client.h>

#include <QClipboard>
#include <QFontDatabase>
#include <QFontMetricsF>
#include <QGuiApplication>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QWheelEvent>

namespace astra::desktop {

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
}

TerminalView::TerminalView(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_screen(80, 24)
{
    setAcceptedMouseButtons(Qt::LeftButton);
    setFlag(ItemIsFocusScope, true);
    setFlag(ItemAcceptsInputMethod, false);
    setActiveFocusOnTab(true);
    setAntialiasing(true);
    setOpaquePainting(true);
    m_font = QFontDatabase::systemFont(QFontDatabase::FixedFont);
    for (const QString &family : {K("DejaVu Sans Mono"), K("Liberation Mono"), K("Noto Sans Mono")})
        if (QFontDatabase::families().contains(family)) {
            m_font.setFamily(family);
            break;
        }
    m_font.setStyleHint(QFont::Monospace);
    measure();
    m_screen.changed = [this] {
        if (m_offset > 0 && m_screen.historySize() < m_offset)
            m_offset = m_screen.historySize();
        update();
    };
    m_screen.titleChanged = [this](const QString &) { Q_EMIT titleChanged(); };
    m_screen.reply = [this](const QByteArray &b) { send(b); };

    astra::Client *client = astra::Client::instance();
    client->subscribe({K("terminal")});
    connect(client, &astra::Client::event, this, [this](const QString &name, const QJsonValue &data) {
        const QJsonObject o = data.toObject();
        if (m_id == 0 || o.value(K("id")).toInt() != m_id)
            return;
        if (name == QLatin1String("terminal.data")) {
            m_selA = m_selB = QPoint(-1, -1);
            m_screen.write(QByteArray::fromBase64(o.value(K("data")).toString().toLatin1()));
        } else if (name == QLatin1String("terminal.exit")) {
            m_id = 0;
            Q_EMIT runningChanged();
            Q_EMIT exited();
        }
    });
}

TerminalView::~TerminalView()
{
    if (m_id > 0)
        astra::Client::instance()->call(K("terminal.close"), {{K("id"), m_id}});
}

void TerminalView::setFontSize(qreal px)
{
    px = qBound(8.0, px, 40.0);
    if (qFuzzyCompare(px, m_fontSize))
        return;
    m_fontSize = px;
    measure();
    fit();
    Q_EMIT fontSizeChanged();
    update();
}

void TerminalView::zoom(int delta)
{
    setFontSize(m_fontSize + delta);
}

void TerminalView::measure()
{
    m_font.setPixelSize(int(m_fontSize));
    const QFontMetricsF fm(m_font);
    m_cellW = fm.horizontalAdvance(QLatin1Char('M'));
    m_cellH = qCeil(fm.height());
    m_ascent = fm.ascent();
}

// The grid that fits the item.
void TerminalView::fit()
{
    const int cols = qMax(10, int(width() / m_cellW));
    const int rows = qMax(2, int(height() / m_cellH));
    if (cols == m_screen.cols() && rows == m_screen.rows())
        return;
    m_screen.resize(cols, rows);
    if (m_id > 0)
        astra::Client::instance()->call(K("terminal.resize"), {{K("id"), m_id}, {K("cols"), cols}, {K("rows"), rows}});
    Q_EMIT sizeChanged();
}

void TerminalView::geometryChange(const QRectF &n, const QRectF &o)
{
    QQuickPaintedItem::geometryChange(n, o);
    if (n.size() != o.size())
        fit();
    if (m_id == 0 && !m_starting && width() > 50 && height() > 50 && property("autostart").toBool())
        start();
}

void TerminalView::start()
{
    if (m_id > 0 || m_starting)
        return;
    m_starting = true;
    fit();
    astra::Client::instance()->call(K("terminal.open"), {{K("cols"), m_screen.cols()}, {K("rows"), m_screen.rows()}},
                                    [this](const QJsonValue &r, const QString &error) {
                                        m_starting = false;
                                        if (!error.isEmpty()) {
                                            m_screen.write(("\x1b[31m" + error + "\x1b[0m\r\n").toUtf8());
                                            return;
                                        }
                                        m_id = r.toObject().value(K("id")).toInt();
                                        Q_EMIT runningChanged();
                                    });
}

void TerminalView::send(const QByteArray &bytes)
{
    if (m_id > 0 && !bytes.isEmpty())
        astra::Client::instance()->call(K("terminal.write"), {{K("id"), m_id}, {K("data"), QString::fromLatin1(bytes.toBase64())}});
}

QPoint TerminalView::cellAt(const QPointF &p) const
{
    return QPoint(qBound(0, int(p.x() / m_cellW), m_screen.cols() - 1), qBound(0, int(p.y() / m_cellH), m_screen.rows() - 1));
}

void TerminalView::copy()
{
    if (m_selA.x() < 0)
        return;
    QPoint a = m_selA, b = m_selB;
    if (b.y() < a.y() || (b.y() == a.y() && b.x() < a.x()))
        std::swap(a, b);
    QGuiApplication::clipboard()->setText(m_screen.text(a.x(), a.y(), b.x(), b.y(), m_selOffset));
}

void TerminalView::paste()
{
    const QString t = QGuiApplication::clipboard()->text();
    if (t.isEmpty())
        return;
    QByteArray bytes = t.toUtf8();
    bytes.replace("\r\n", "\r").replace('\n', '\r');
    send(m_screen.bracketedPaste() ? "\x1b[200~" + bytes + "\x1b[201~" : bytes);
}

void TerminalView::keyPressEvent(QKeyEvent *e)
{
    const Qt::KeyboardModifiers m = e->modifiers();
    const bool ctrl = m & Qt::ControlModifier, shift = m & Qt::ShiftModifier, alt = m & Qt::AltModifier;
    const int key = e->key();
    if (ctrl && shift && key == Qt::Key_C) { copy(); return; }
    if (ctrl && shift && key == Qt::Key_V) { paste(); return; }
    if (ctrl && (key == Qt::Key_Plus || key == Qt::Key_Equal)) { zoom(1); return; }
    if (ctrl && key == Qt::Key_Minus) { zoom(-1); return; }
    if (shift && key == Qt::Key_PageUp) { m_offset = qMin(m_screen.historySize(), m_offset + m_screen.rows() / 2); update(); return; }
    if (shift && key == Qt::Key_PageDown) { m_offset = qMax(0, m_offset - m_screen.rows() / 2); update(); return; }
    m_offset = 0;
    m_selA = m_selB = QPoint(-1, -1);

    const bool app = m_screen.applicationCursorKeys();
    auto csi = [&](char c) { return QByteArray(app ? "\x1bO" : "\x1b[") + c; };
    QByteArray out;
    switch (key) {
    case Qt::Key_Return: case Qt::Key_Enter: out = "\r"; break;
    case Qt::Key_Backspace: out = "\x7f"; break;
    case Qt::Key_Tab: out = "\t"; break;
    case Qt::Key_Backtab: out = "\x1b[Z"; break;
    case Qt::Key_Escape: out = "\x1b"; break;
    case Qt::Key_Up: out = csi('A'); break;
    case Qt::Key_Down: out = csi('B'); break;
    case Qt::Key_Right: out = csi('C'); break;
    case Qt::Key_Left: out = csi('D'); break;
    case Qt::Key_Home: out = csi('H'); break;
    case Qt::Key_End: out = csi('F'); break;
    case Qt::Key_PageUp: out = "\x1b[5~"; break;
    case Qt::Key_PageDown: out = "\x1b[6~"; break;
    case Qt::Key_Delete: out = "\x1b[3~"; break;
    case Qt::Key_Insert: out = "\x1b[2~"; break;
    default:
        if (key >= Qt::Key_F1 && key <= Qt::Key_F12) {
            static const char *f[] = {"\x1bOP", "\x1bOQ", "\x1bOR", "\x1bOS", "\x1b[15~", "\x1b[17~", "\x1b[18~", "\x1b[19~", "\x1b[20~", "\x1b[21~", "\x1b[23~", "\x1b[24~"};
            out = f[key - Qt::Key_F1];
        } else if (ctrl && key >= Qt::Key_A && key <= Qt::Key_Z) {
            out = QByteArray(1, char(key - Qt::Key_A + 1));
        } else if (ctrl && key == Qt::Key_Space) {
            out = QByteArray(1, '\0');
        } else if (ctrl && key == Qt::Key_BracketLeft) {
            out = "\x1b";
        } else if (!e->text().isEmpty() && !(ctrl && !shift && e->text().at(0).unicode() < 0x20)) {
            out = e->text().toUtf8();
        }
    }
    if (out.isEmpty())
        return;
    if (alt && key != Qt::Key_Escape)
        out.prepend('\x1b');
    send(out);
}

void TerminalView::mousePressEvent(QMouseEvent *e)
{
    forceActiveFocus();
    m_selA = m_selB = cellAt(e->position());
    m_selOffset = m_offset;
    m_selecting = true;
    update();
}

void TerminalView::mouseMoveEvent(QMouseEvent *e)
{
    if (m_selecting) {
        m_selB = cellAt(e->position());
        update();
    }
}

void TerminalView::mouseReleaseEvent(QMouseEvent *)
{
    m_selecting = false;
    if (m_selA == m_selB)
        m_selA = m_selB = QPoint(-1, -1);
    else
        copy();   // what is selected is copied, as in most terminals
    update();
}

void TerminalView::wheelEvent(QWheelEvent *e)
{
    const int lines = e->angleDelta().y() / 40;
    m_offset = qBound(0, m_offset + lines, m_screen.historySize());
    update();
}

void TerminalView::paint(QPainter *p)
{
    p->fillRect(QRectF(0, 0, width(), height()), m_bg);
    p->setFont(m_font);
    const int cols = m_screen.cols(), rows = m_screen.rows();
    const int offset = m_screen.historySize() > 0 ? m_offset : 0;
    QPoint a = m_selA, b = m_selB;
    if (b.y() < a.y() || (b.y() == a.y() && b.x() < a.x()))
        std::swap(a, b);
    auto selected = [&](int c, int r) {
        if (a.x() < 0)
            return false;
        return (r > a.y() || (r == a.y() && c >= a.x())) && (r < b.y() || (r == b.y() && c <= b.x()));
    };
    for (int r = 0; r < rows; ++r) {
        const qreal y = r * m_cellH;
        // Backgrounds, one rectangle per run.
        for (int c = 0; c < cols;) {
            const Cell &first = m_screen.cell(c, r, offset);
            const bool rev0 = first.attrs & Reverse;
            quint32 bg = rev0 ? (first.fg ? first.fg : (0xFF000000 | m_fg.rgb() & 0xFFFFFF)) : first.bg;
            const bool sel0 = selected(c, r);
            int e = c + 1;
            while (e < cols) {
                const Cell &n = m_screen.cell(e, r, offset);
                const bool rev = n.attrs & Reverse;
                const quint32 nbg = rev ? (n.fg ? n.fg : (0xFF000000 | m_fg.rgb() & 0xFFFFFF)) : n.bg;
                if (nbg != bg || selected(e, r) != sel0)
                    break;
                ++e;
            }
            if (sel0)
                p->fillRect(QRectF(c * m_cellW, y, (e - c) * m_cellW, m_cellH), QColor(m_accent.red(), m_accent.green(), m_accent.blue(), 110));
            else if (bg)
                p->fillRect(QRectF(c * m_cellW, y, (e - c) * m_cellW, m_cellH), QColor::fromRgb(bg));
            c = e;
        }
        // Text, one run per attribute set.
        for (int c = 0; c < cols;) {
            const Cell &first = m_screen.cell(c, r, offset);
            int e = c;
            QString text;
            while (e < cols) {
                const Cell &n = m_screen.cell(e, r, offset);
                if (n.fg != first.fg || n.bg != first.bg || n.attrs != first.attrs)
                    break;
                text += QString::fromUcs4(&n.ch, 1);
                ++e;
            }
            if (!text.trimmed().isEmpty() || (first.attrs & Underline)) {
                const bool rev = first.attrs & Reverse;
                QColor color = rev ? (first.bg ? QColor::fromRgb(first.bg) : m_bg) : (first.fg ? QColor::fromRgb(first.fg) : m_fg);
                QFont f = m_font;
                f.setBold(first.attrs & Bold);
                f.setItalic(first.attrs & Italic);
                f.setUnderline(first.attrs & Underline);
                p->setFont(f);
                p->setPen(color);
                for (int i = 0; i < text.size(); ++i)   // each character on its cell: a fixed pitch whatever the font does
                    if (text[i] != QLatin1Char(' '))
                        p->drawText(QPointF((c + i) * m_cellW, y + m_ascent), QString(text[i]));
            }
            c = e;
        }
    }
    if (offset == 0 && m_screen.cursorVisible()) {
        const QRectF cr(m_screen.cursorCol() * m_cellW, m_screen.cursorRow() * m_cellH, m_cellW, m_cellH);
        if (hasActiveFocus()) {
            p->fillRect(cr, QColor(m_fg.red(), m_fg.green(), m_fg.blue(), 200));
            const Cell &under = m_screen.cell(m_screen.cursorCol(), m_screen.cursorRow());
            if (under.ch != U' ') {
                p->setPen(m_bg);
                p->setFont(m_font);
                p->drawText(QPointF(cr.x(), cr.y() + m_ascent), QString::fromUcs4(&under.ch, 1));
            }
        } else {
            p->setPen(m_fg);
            p->drawRect(cr.adjusted(0.5, 0.5, -0.5, -0.5));
        }
    }
}

} // namespace astra::desktop
