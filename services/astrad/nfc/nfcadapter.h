// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QTimer>

class QSocketNotifier;

namespace astrad::nfc {

// The phone's NFC controller, through the kernel's own NFC subsystem (generic
// netlink family "nfc" for the controller, AF_NFC sockets for the tag): no
// daemon in between. It lives in its own thread, since turning the controller
// on and talking to a tag take the time the radio takes.
//
// While on, it looks for tags. One that comes near is read (and, when a message
// waits to be written, written) and reported once, however long it stays.
class NfcAdapter : public QObject
{
    Q_OBJECT
public:
    explicit NfcAdapter(QObject *parent = nullptr);
    ~NfcAdapter() override;

public Q_SLOTS:
    void start();
    void setEnabled(bool on);
    // The message for the next tag that comes near; an empty one cancels.
    void setPendingWrite(const QByteArray &message);

Q_SIGNALS:
    void stateChanged(bool available, bool powered);
    // {uid, type, records, empty, writable, capacity, error}
    void tagRead(const QJsonObject &tag);
    void writeFinished(bool ok, const QString &error);

private:
    using Attrs = QHash<int, QByteArray>;
    struct Reply { int command = 0; Attrs attrs; };

    bool openNetlink();
    void closeNetlink();
    int request(int command, const Attrs &attrs, bool dump, QList<Reply> *replies, int timeoutMs = 3000);
    bool findDevice();
    void probe();
    void apply();
    void startPoll();
    void onEvent();
    void onTargets();
    void handleTarget(const Attrs &target);
    void publish();

    int m_cmd = -1;        // requests and their answers
    int m_events = -1;     // what the kernel tells unasked
    int m_family = 0;
    quint32 m_seq = 0;
    QSocketNotifier *m_notifier = nullptr;
    QTimer m_probe;        // until the controller's driver has loaded
    QTimer m_poll;         // looks again after a tag, and should polling have stopped
    int m_probes = 0;
    int m_device = -1;
    bool m_powered = false;
    bool m_wanted = false;
    bool m_published = false, m_publishedAvailable = false, m_publishedPowered = false;
    QByteArray m_pending;
    QByteArray m_lastUid, m_lastMessage;
    QElapsedTimer m_lastSeen;
};

} // namespace astrad::nfc
