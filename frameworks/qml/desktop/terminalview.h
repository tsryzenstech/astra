// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "vtscreen.h"

#include <QColor>
#include <QFont>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

namespace astra::desktop {

// A terminal: draws a VtScreen and talks to astrad's terminal service (a shell, as the user, on a pseudo terminal). The
// Terminal app is this item and a window. Needs astra.permission.TERMINAL.
//
//   TerminalView { id: term; anchors.fill: parent; focus: true; Component.onCompleted: start() }
class TerminalView : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal fontSize READ fontSize WRITE setFontSize NOTIFY fontSizeChanged)
    Q_PROPERTY(QColor foreground READ foreground WRITE setForeground NOTIFY colorsChanged)
    Q_PROPERTY(QColor background READ background WRITE setBackground NOTIFY colorsChanged)
    Q_PROPERTY(QColor accent READ accent WRITE setAccent NOTIFY colorsChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int columns READ columns NOTIFY sizeChanged)
    Q_PROPERTY(int lines READ lines NOTIFY sizeChanged)

public:
    explicit TerminalView(QQuickItem *parent = nullptr);
    ~TerminalView() override;

    qreal fontSize() const { return m_fontSize; }
    void setFontSize(qreal px);
    QColor foreground() const { return m_fg; }
    void setForeground(const QColor &c) { m_fg = c; Q_EMIT colorsChanged(); update(); }
    QColor background() const { return m_bg; }
    void setBackground(const QColor &c) { m_bg = c; Q_EMIT colorsChanged(); update(); }
    QColor accent() const { return m_accent; }
    void setAccent(const QColor &c) { m_accent = c; Q_EMIT colorsChanged(); update(); }
    QString title() const { return m_screen.title(); }
    bool running() const { return m_id > 0; }
    int columns() const { return m_screen.cols(); }
    int lines() const { return m_screen.rows(); }

    // Opens the shell (once the item has a size).
    Q_INVOKABLE void start();
    Q_INVOKABLE void copy();
    Q_INVOKABLE void paste();
    Q_INVOKABLE void zoom(int delta);

    void paint(QPainter *painter) override;

Q_SIGNALS:
    void fontSizeChanged();
    void colorsChanged();
    void titleChanged();
    void runningChanged();
    void sizeChanged();
    void exited();

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void focusInEvent(QFocusEvent *) override { update(); }
    void focusOutEvent(QFocusEvent *) override { update(); }

private:
    void send(const QByteArray &bytes);
    void measure();
    void fit();
    QPoint cellAt(const QPointF &p) const;

    VtScreen m_screen;
    QFont m_font;
    qreal m_fontSize = 15;
    qreal m_cellW = 9, m_cellH = 18, m_ascent = 14;
    QColor m_fg{0xE6, 0xE6, 0xEA}, m_bg{0x14, 0x14, 0x16}, m_accent{0xFF, 0x7A, 0x00};
    int m_id = 0;
    bool m_starting = false;
    int m_offset = 0;                       // lines scrolled back
    bool m_selecting = false;
    QPoint m_selA{-1, -1}, m_selB{-1, -1};   // in cells of the view
    int m_selOffset = 0;
};

} // namespace astra::desktop
