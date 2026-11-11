// SPDX-License-Identifier: Apache-2.0
#include "nfcadapter.h"
#include "ndef.h"

#include <QJsonArray>
#include <QLoggingCategory>
#include <QSocketNotifier>

#include <cerrno>
#include <cstring>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include <linux/genetlink.h>
#include <linux/netlink.h>
#include <linux/nfc.h>

#ifndef AF_NFC
#define AF_NFC 39
#endif
#ifndef SOL_NETLINK
#define SOL_NETLINK 270
#endif

Q_LOGGING_CATEGORY(lcNfc, "astrad.nfc")

namespace astrad::nfc {

namespace {

QString K(const char *s) { return QString::fromLatin1(s); }

// What the answers of a tag are preceded by on the kernel's raw NFC socket.
constexpr int kHeader = 1;
// Tags a phone meets: Type 2 and Type 4 are read, the others named.
constexpr quint32 kProtocols = NFC_PROTO_JEWEL_MASK | NFC_PROTO_MIFARE_MASK | NFC_PROTO_FELICA_MASK |
                               NFC_PROTO_ISO14443_MASK | NFC_PROTO_ISO14443_B_MASK | NFC_PROTO_ISO15693_MASK;
// A tag left on the phone is found again every second: it is the same visit.
constexpr int kSameVisitMs = 4000;

QByteArray u32(quint32 v) { return QByteArray(reinterpret_cast<const char *>(&v), sizeof v); }

quint32 toU32(const QByteArray &b)
{
    quint32 v = 0;
    memcpy(&v, b.constData(), qMin<size_t>(sizeof v, size_t(b.size())));
    return v;
}

QHash<int, QByteArray> parseAttrs(const char *data, int length)
{
    QHash<int, QByteArray> out;
    while (length >= int(NLA_HDRLEN)) {
        nlattr a;
        memcpy(&a, data, sizeof a);
        if (a.nla_len < NLA_HDRLEN || a.nla_len > length)
            break;
        out.insert(a.nla_type & NLA_TYPE_MASK, QByteArray(data + NLA_HDRLEN, a.nla_len - NLA_HDRLEN));
        const int step = NLA_ALIGN(a.nla_len);
        data += step;
        length -= step;
    }
    return out;
}

QByteArray buildMessage(int family, int flags, quint32 seq, int command, const QHash<int, QByteArray> &attrs)
{
    QByteArray b(NLMSG_HDRLEN + GENL_HDRLEN, '\0');
    for (auto it = attrs.constBegin(); it != attrs.constEnd(); ++it) {
        nlattr a;
        a.nla_len = quint16(NLA_HDRLEN + it.value().size());
        a.nla_type = quint16(it.key());
        b.append(reinterpret_cast<const char *>(&a), sizeof a);
        b.append(it.value());
        while (b.size() % NLA_ALIGNTO)
            b.append('\0');
    }
    auto *h = reinterpret_cast<nlmsghdr *>(b.data());
    h->nlmsg_len = quint32(b.size());
    h->nlmsg_type = quint16(family);
    h->nlmsg_flags = quint16(flags);
    h->nlmsg_seq = seq;
    auto *g = reinterpret_cast<genlmsghdr *>(b.data() + NLMSG_HDRLEN);
    g->cmd = quint8(command);
    g->version = 1;
    return b;
}

int netlinkSocket(int flags)
{
    const int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC | flags, NETLINK_GENERIC);
    if (fd < 0)
        return -1;
    sockaddr_nl addr{};
    addr.nl_family = AF_NETLINK;
    if (bind(fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// The tag in front of the phone, on the kernel's raw NFC socket.
class SocketLink : public TagLink
{
public:
    ~SocketLink() override
    {
        if (m_fd >= 0)
            close(m_fd); // which lets go of the tag
    }

    bool open(quint32 device, quint32 target, quint32 protocol)
    {
        m_fd = socket(AF_NFC, SOCK_SEQPACKET | SOCK_CLOEXEC, NFC_SOCKPROTO_RAW);
        if (m_fd < 0)
            return false;
        const timeval wait{2, 0};
        setsockopt(m_fd, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof wait);
        setsockopt(m_fd, SOL_SOCKET, SO_SNDTIMEO, &wait, sizeof wait);
        sockaddr_nfc addr{};
        addr.sa_family = AF_NFC;
        addr.dev_idx = device;
        addr.target_idx = target;
        addr.nfc_protocol = protocol;
        return ::connect(m_fd, reinterpret_cast<sockaddr *>(&addr), sizeof addr) == 0;
    }

    bool transceive(const QByteArray &command, QByteArray *response) override
    {
        if (send(m_fd, command.constData(), size_t(command.size()), 0) != command.size())
            return false;
        char buffer[1024];
        const ssize_t n = recv(m_fd, buffer, sizeof buffer, 0);
        if (n < kHeader)
            return false;
        *response = QByteArray(buffer + kHeader, int(n) - kHeader);
        return true;
    }

private:
    int m_fd = -1;
};

} // namespace

NfcAdapter::NfcAdapter(QObject *parent)
    : QObject(parent)
    , m_probe(this)
    , m_poll(this)
{
    // The controller's driver loads with the other modules, after astrad starts.
    m_probe.setInterval(10000);
    connect(&m_probe, &QTimer::timeout, this, &NfcAdapter::probe);
    // Polling ends by itself when the radio hiccups: it is asked for again.
    m_poll.setInterval(5000);
    connect(&m_poll, &QTimer::timeout, this, &NfcAdapter::startPoll);
}

NfcAdapter::~NfcAdapter()
{
    closeNetlink();
}

void NfcAdapter::start()
{
    probe();
    if (m_device < 0)
        m_probe.start();
}

void NfcAdapter::closeNetlink()
{
    delete m_notifier;
    m_notifier = nullptr;
    if (m_cmd >= 0)
        close(m_cmd);
    if (m_events >= 0)
        close(m_events);
    m_cmd = m_events = -1;
    m_family = 0;
}

int NfcAdapter::request(int command, const Attrs &attrs, bool dump, QList<Reply> *replies, int timeoutMs)
{
    if (m_cmd < 0)
        return -ENODEV;
    // The first request finds the family, through the one every kernel has.
    const int family = m_family ? m_family : GENL_ID_CTRL;
    const quint32 seq = ++m_seq;
    const QByteArray message = buildMessage(family, NLM_F_REQUEST | (dump ? NLM_F_DUMP : NLM_F_ACK), seq, command, attrs);
    if (send(m_cmd, message.constData(), size_t(message.size()), 0) < 0)
        return -errno;

    QElapsedTimer timer;
    timer.start();
    QByteArray buffer(32768, '\0');
    for (;;) {
        const int left = timeoutMs - int(timer.elapsed());
        if (left <= 0)
            return -ETIMEDOUT;
        pollfd p{m_cmd, POLLIN, 0};
        const int ready = poll(&p, 1, left);
        if (ready < 0 && errno == EINTR)
            continue;
        if (ready <= 0)
            return -ETIMEDOUT;
        const ssize_t n = recv(m_cmd, buffer.data(), size_t(buffer.size()), 0);
        if (n < 0) {
            if (errno == EINTR || errno == EAGAIN)
                continue;
            return -errno;
        }
        int length = int(n);
        for (auto *h = reinterpret_cast<nlmsghdr *>(buffer.data()); NLMSG_OK(h, length); h = NLMSG_NEXT(h, length)) {
            if (h->nlmsg_seq != seq)
                continue;
            if (h->nlmsg_type == NLMSG_ERROR)
                return static_cast<nlmsgerr *>(NLMSG_DATA(h))->error; // 0 acknowledges
            if (h->nlmsg_type == NLMSG_DONE)
                return 0;
            if (h->nlmsg_len < NLMSG_HDRLEN + GENL_HDRLEN || !replies)
                continue;
            const auto *g = static_cast<const genlmsghdr *>(NLMSG_DATA(h));
            Reply reply;
            reply.command = g->cmd;
            reply.attrs = parseAttrs(reinterpret_cast<const char *>(g) + GENL_HDRLEN,
                                     int(h->nlmsg_len) - int(NLMSG_HDRLEN) - int(GENL_HDRLEN));
            replies->append(reply);
        }
    }
}

bool NfcAdapter::openNetlink()
{
    if (m_family)
        return true;
    closeNetlink();
    // Asking for an NFC socket has the kernel load its NFC support, where it can.
    const int wake = socket(AF_NFC, SOCK_SEQPACKET | SOCK_CLOEXEC, NFC_SOCKPROTO_RAW);
    if (wake >= 0)
        close(wake);

    m_cmd = netlinkSocket(0);
    if (m_cmd < 0)
        return false;
    QList<Reply> replies;
    if (request(CTRL_CMD_GETFAMILY, {{CTRL_ATTR_FAMILY_NAME, QByteArray(NFC_GENL_NAME, int(sizeof NFC_GENL_NAME))}},
                false, &replies) != 0 || replies.isEmpty()) {
        closeNetlink();
        return false; // this kernel has no NFC (yet)
    }
    const Attrs family = replies.first().attrs;
    quint16 id = 0;
    memcpy(&id, family.value(CTRL_ATTR_FAMILY_ID).constData(), qMin<size_t>(2, size_t(family.value(CTRL_ATTR_FAMILY_ID).size())));
    quint32 group = 0;
    const QByteArray groups = family.value(CTRL_ATTR_MCAST_GROUPS);
    const Attrs list = parseAttrs(groups.constData(), int(groups.size()));
    for (const QByteArray &entry : list) {
        const Attrs g = parseAttrs(entry.constData(), int(entry.size()));
        if (g.value(CTRL_ATTR_MCAST_GRP_NAME).startsWith(NFC_GENL_MCAST_EVENT_NAME))
            group = toU32(g.value(CTRL_ATTR_MCAST_GRP_ID));
    }
    m_events = netlinkSocket(SOCK_NONBLOCK);
    if (!id || !group || m_events < 0 ||
        setsockopt(m_events, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &group, sizeof group) < 0) {
        closeNetlink();
        return false;
    }
    m_family = id;
    m_notifier = new QSocketNotifier(m_events, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &NfcAdapter::onEvent);
    return true;
}

bool NfcAdapter::findDevice()
{
    m_device = -1;
    m_powered = false;
    QList<Reply> devices;
    if (request(NFC_CMD_GET_DEVICE, {}, true, &devices) != 0)
        return false;
    for (const Reply &d : std::as_const(devices)) {
        if (!d.attrs.contains(NFC_ATTR_DEVICE_INDEX))
            continue;
        m_device = int(toU32(d.attrs.value(NFC_ATTR_DEVICE_INDEX)));
        m_powered = !d.attrs.value(NFC_ATTR_DEVICE_POWERED).isEmpty() && d.attrs.value(NFC_ATTR_DEVICE_POWERED).at(0);
        qCInfo(lcNfc) << "controller" << d.attrs.value(NFC_ATTR_DEVICE_NAME).constData() << "index" << m_device
                      << "protocols" << Qt::hex << toU32(d.attrs.value(NFC_ATTR_PROTOCOLS));
        return true;
    }
    return false;
}

void NfcAdapter::probe()
{
    if (m_device < 0 && openNetlink() && findDevice()) {
        m_probe.stop();
        apply();
        return;
    }
    // Often for the first minute, then now and then: a phone without NFC never answers.
    if (++m_probes == 6)
        m_probe.setInterval(120000);
    publish();
}

void NfcAdapter::setEnabled(bool on)
{
    m_wanted = on;
    apply();
}

void NfcAdapter::setPendingWrite(const QByteArray &message)
{
    m_pending = message;
}

void NfcAdapter::apply()
{
    if (m_device < 0) {
        publish();
        return;
    }
    const Attrs device{{NFC_ATTR_DEVICE_INDEX, u32(quint32(m_device))}};
    if (m_wanted) {
        if (!m_powered) {
            // The controller starts and loads its settings: seconds, the first time.
            const int r = request(NFC_CMD_DEV_UP, device, false, nullptr, 20000);
            if (r == 0 || r == -EALREADY)
                m_powered = true;
            else
                qCWarning(lcNfc) << "the controller did not turn on:" << strerror(-r);
        }
        if (m_powered) {
            startPoll();
            m_poll.start();
        }
    } else {
        m_poll.stop();
        if (m_powered) {
            request(NFC_CMD_STOP_POLL, device, false, nullptr);
            const int r = request(NFC_CMD_DEV_DOWN, device, false, nullptr, 8000);
            if (r != 0 && r != -EALREADY)
                qCWarning(lcNfc) << "the controller did not turn off:" << strerror(-r);
            m_powered = false;
        }
    }
    publish();
}

void NfcAdapter::startPoll()
{
    if (m_device < 0 || !m_powered || !m_wanted)
        return;
    const int r = request(NFC_CMD_START_POLL,
                          {{NFC_ATTR_DEVICE_INDEX, u32(quint32(m_device))}, {NFC_ATTR_IM_PROTOCOLS, u32(kProtocols)}},
                          false, nullptr, 8000);
    // EBUSY: it is polling already, which is what was asked.
    if (r == -ENODEV) {
        // Turned off behind our back (the driver restarted the controller).
        m_powered = false;
        apply();
    } else if (r != 0 && r != -EBUSY) {
        qCWarning(lcNfc) << "polling did not start:" << strerror(-r);
    }
}

void NfcAdapter::onEvent()
{
    bool targets = false, devices = false;
    QByteArray buffer(16384, '\0');
    for (;;) {
        const ssize_t n = recv(m_events, buffer.data(), size_t(buffer.size()), 0);
        if (n <= 0)
            break; // nothing more (or events were dropped: the poll timer catches up)
        int length = int(n);
        for (auto *h = reinterpret_cast<nlmsghdr *>(buffer.data()); NLMSG_OK(h, length); h = NLMSG_NEXT(h, length)) {
            if (h->nlmsg_type != m_family || h->nlmsg_len < NLMSG_HDRLEN + GENL_HDRLEN)
                continue;
            switch (static_cast<const genlmsghdr *>(NLMSG_DATA(h))->cmd) {
            case NFC_EVENT_TARGETS_FOUND: targets = true; break;
            case NFC_EVENT_DEVICE_ADDED:
            case NFC_EVENT_DEVICE_REMOVED: devices = true; break;
            default: break;
            }
        }
    }
    if (devices) {
        const bool had = m_device >= 0;
        findDevice();
        if (m_device < 0 && had)
            m_probe.start();
        apply();
    }
    if (targets)
        onTargets();
}

void NfcAdapter::onTargets()
{
    if (m_device < 0)
        return;
    QList<Reply> targets;
    request(NFC_CMD_GET_TARGET, {{NFC_ATTR_DEVICE_INDEX, u32(quint32(m_device))}}, true, &targets);
    if (!targets.isEmpty() && targets.first().attrs.contains(NFC_ATTR_TARGET_INDEX))
        handleTarget(targets.first().attrs);
    // Finding a tag ends the polling: look again, once this one has had its time.
    QTimer::singleShot(900, this, &NfcAdapter::startPoll);
}

void NfcAdapter::handleTarget(const Attrs &target)
{
    const quint32 index = toU32(target.value(NFC_ATTR_TARGET_INDEX));
    const quint32 protocols = toU32(target.value(NFC_ATTR_PROTOCOLS));
    const QByteArray uid = target.value(NFC_ATTR_TARGET_NFCID1);
    const int sak = target.value(NFC_ATTR_TARGET_SEL_RES).isEmpty() ? 0 : quint8(target.value(NFC_ATTR_TARGET_SEL_RES).at(0));
    const bool recent = m_lastSeen.isValid() && m_lastSeen.elapsed() < kSameVisitMs;
    bool again = recent && !uid.isEmpty() && uid == m_lastUid;
    if (again && m_pending.isEmpty()) {
        m_lastSeen.restart();
        return;
    }

    QJsonObject tag{{K("uid"), QString::fromLatin1(uid.toHex(':')).toUpper()}};
    QByteArray message;
    QString error;
    bool wrote = false;
    if ((protocols & NFC_PROTO_MIFARE_MASK) && sak == 0) {
        tag.insert(K("type"), K("Type 2"));
        SocketLink link;
        if (!link.open(quint32(m_device), index, NFC_PROTO_MIFARE))
            return; // gone before it could be read: it will be found again
        if (!m_pending.isEmpty()) {
            QString writeError;
            wrote = writeType2(link, m_pending, &writeError);
            if (wrote)
                m_pending.clear();
            Q_EMIT writeFinished(wrote, writeError);
        }
        Type2Info info;
        if (readType2(link, &message, &info, &error)) {
            tag.insert(K("capacity"), info.capacity);
            tag.insert(K("writable"), info.writable || !info.formatted);
        }
    } else if (protocols & (NFC_PROTO_ISO14443_MASK | NFC_PROTO_ISO14443_B_MASK)) {
        tag.insert(K("type"), K("Type 4"));
        if (!m_pending.isEmpty()) {
            m_pending.clear();
            Q_EMIT writeFinished(false, K("Writing works on NTAG and Ultralight tags, not on this card"));
        }
        SocketLink link;
        if (!link.open(quint32(m_device), index,
                       (protocols & NFC_PROTO_ISO14443_MASK) ? NFC_PROTO_ISO14443 : NFC_PROTO_ISO14443_B))
            return;
        readType4(link, &message, &error);
    } else {
        tag.insert(K("type"), (protocols & NFC_PROTO_MIFARE_MASK) ? K("MIFARE Classic")
                              : (protocols & NFC_PROTO_FELICA_MASK) ? K("FeliCa")
                              : (protocols & NFC_PROTO_ISO15693_MASK) ? K("ISO 15693")
                              : (protocols & NFC_PROTO_JEWEL_MASK) ? K("Type 1") : K("Unknown"));
        error = K("This kind of tag is not read by astraOS");
        if (!m_pending.isEmpty()) {
            m_pending.clear();
            Q_EMIT writeFinished(false, K("Writing works on NTAG and Ultralight tags, not on this one"));
        }
    }

    // Phones and some cards take a new identifier for every visit: what they
    // say tells that it is the same one.
    if (!again && recent && !message.isEmpty() && message == m_lastMessage)
        again = true;
    m_lastUid = uid;
    m_lastMessage = message;
    m_lastSeen.restart();

    tag.insert(K("records"), parseMessage(message));
    tag.insert(K("empty"), message.isEmpty());
    if (!error.isEmpty())
        tag.insert(K("error"), error);
    tag.insert(K("repeat"), again && !wrote);
    tag.insert(K("written"), wrote);
    Q_EMIT tagRead(tag);
}

void NfcAdapter::publish()
{
    const bool available = m_device >= 0;
    if (m_published && available == m_publishedAvailable && m_powered == m_publishedPowered)
        return;
    m_published = true;
    m_publishedAvailable = available;
    m_publishedPowered = m_powered;
    Q_EMIT stateChanged(available, m_powered);
}

} // namespace astrad::nfc
