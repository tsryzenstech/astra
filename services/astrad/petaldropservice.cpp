// SPDX-License-Identifier: Apache-2.0
#include "petaldropservice.h"
#include "accountservice.h"
#include "dialogservice.h"
#include "notificationservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/form.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHostAddress>
#include <QHostInfo>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QMessageAuthenticationCode>
#include <QNetworkInterface>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUdpSocket>
#include <QUuid>

Q_LOGGING_CATEGORY(lcPetal, "astrad.petaldrop")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
constexpr int kMaxFiles = 500;
constexpr qint64 kMaxTotal = Q_INT64_C(8) * 1024 * 1024 * 1024;
constexpr int kMaxLine = 1024 * 1024;
constexpr qint64 kChunk = 64 * 1024;

QByteArray line(const QJsonObject &o)
{
    return QJsonDocument(o).toJson(QJsonDocument::Compact) + '\n';
}

// The next line of buf (without its newline), or a null array when there is none yet.
QByteArray takeLine(QByteArray &buf)
{
    const int i = buf.indexOf('\n');
    if (i < 0)
        return {};
    const QByteArray l = buf.left(i);
    buf.remove(0, i + 1);
    return l.isNull() ? QByteArray("") : l;
}

QString safeName(const QString &name)
{
    QString n = QFileInfo(name).fileName();
    n.remove(QRegularExpression(QStringLiteral("[\\x00-\\x1f\\\\/:*?\"<>|]")));
    while (n.startsWith(QLatin1Char('.')))
        n.remove(0, 1);
    n = n.left(150).trimmed();
    return n.isEmpty() ? QStringLiteral("file") : n;
}

QString uniquePath(const QString &dir, const QString &name)
{
    QString target = dir + QLatin1Char('/') + name;
    const QFileInfo info(name);
    for (int i = 1; QFile::exists(target); ++i)
        target = dir + QLatin1Char('/') + info.completeBaseName() + QStringLiteral(" (%1)").arg(i) +
                 (info.suffix().isEmpty() ? QString() : QLatin1Char('.') + info.suffix());
    return target;
}

QString sha256Of(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    QCryptographicHash h(QCryptographicHash::Sha256);
    h.addData(&f);
    return QString::fromLatin1(h.result().toHex());
}
} // namespace

struct PetalDropService::Transfer {
    int id = 0;
    QString peerId, peerName, package;
    struct File { QString path, name; qint64 size = 0; QString sha; };
    QList<File> files;
    int index = 0;
    QFile *current = nullptr;
    qint64 sent = 0, total = 0;
    QString state = QStringLiteral("connecting"); // connecting, waiting, sending, done, declined, failed, cancelled
    QString error;
    QString offerId;
    bool accepted = false, finished = false;
    QByteArray rx;
    QTcpSocket *sock = nullptr;
};

struct PetalDropService::Incoming {
    enum Stage { Offer, Await, Header, Body, Closed };
    QTcpSocket *sock = nullptr;
    QByteArray buf;
    Stage stage = Offer;
    QString fromName;
    QString dir;
    QJsonArray files;
    int index = 0;
    qint64 remaining = 0;
    QFile *out = nullptr;
    QCryptographicHash hash{QCryptographicHash::Sha256};
    QString expected, outPath;
    QStringList received;
    bool mine = false;
};

PetalDropService::PetalDropService(Server *server, SettingsService *settings, AccountService *account,
                                   DialogService *dialogs, NotificationService *notifications, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_account(account)
    , m_dialogs(dialogs)
    , m_notifications(notifications)
{
    m_beaconTimer.setInterval(4000);
    connect(&m_beaconTimer, &QTimer::timeout, this, &PetalDropService::beacon);
    m_accountTimer.setInterval(60 * 1000);
    connect(&m_accountTimer, &QTimer::timeout, this, &PetalDropService::syncAccount);
    connect(m_account, &AccountService::accountChanged, this, [this] { m_key.clear(); configure(); QTimer::singleShot(1000, this, &PetalDropService::syncAccount); });
    connect(m_settings, &SettingsService::changed, this, [this](const QString &key, const QJsonValue &) {
        if (key == QLatin1String("petaldrop.receive") || key == QLatin1String("account.name"))
            configure();
    });
    QTimer::singleShot(3000, this, [this] { configure(); syncAccount(); });
}

PetalDropService::~PetalDropService()
{
    qDeleteAll(m_transfers);
}

QString PetalDropService::receiveMode() const
{
    const QString m = m_settings->value(K("petaldrop.receive")).toString(K("mydevices"));
    return m == QLatin1String("off") || m == QLatin1String("everyone") ? m : K("mydevices");
}

QString PetalDropService::deviceKind() const
{
    return Form::isDesktop() ? K("desktop") : K("phone");
}

QString PetalDropService::deviceName() const
{
    const QString owner = m_settings->value(K("account.name")).toString();
    if (!owner.isEmpty())
        return Form::isDesktop() ? QStringLiteral("%1's desktop").arg(owner) : QStringLiteral("%1's phone").arg(owner);
    return QHostInfo::localHostName().isEmpty() ? K("astraOS") : QHostInfo::localHostName();
}

QString PetalDropService::selfId()
{
    if (m_account->signedIn() && m_account->deviceId() > 0)
        return QStringLiteral("d%1").arg(m_account->deviceId());
    if (m_selfId.isEmpty()) {
        m_selfId = m_settings->value(K("petaldrop.id")).toString();
        if (m_selfId.isEmpty()) {
            m_selfId = QStringLiteral("r") + QUuid::createUuid().toString(QUuid::Id128).left(12);
            m_settings->setValue(K("petaldrop.id"), m_selfId);
        }
    }
    return m_selfId;
}

// Listens (TCP) and announces (UDP) while the device may receive; stops when it may not.
void PetalDropService::configure()
{
    const bool on = receiveMode() != QLatin1String("off");
    if (!m_udp) {
        m_udp = new QUdpSocket(this);
        if (m_udp->bind(QHostAddress::AnyIPv4, BeaconPort, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint))
            connect(m_udp, &QUdpSocket::readyRead, this, &PetalDropService::readBeacons);
        else
            qCWarning(lcPetal) << "no beacon port:" << m_udp->errorString();
    }
    if (on && !m_tcp) {
        m_tcp = new QTcpServer(this);
        if (!m_tcp->listen(QHostAddress::AnyIPv4, TransferPort) && !m_tcp->listen(QHostAddress::AnyIPv4, 0)) {
            qCWarning(lcPetal) << "cannot listen:" << m_tcp->errorString();
            delete m_tcp;
            m_tcp = nullptr;
            return;
        }
        connect(m_tcp, &QTcpServer::newConnection, this, &PetalDropService::incomingConnection);
        qCInfo(lcPetal) << "listening on" << m_tcp->serverPort();
    } else if (!on && m_tcp) {
        m_tcp->close();
        m_tcp->deleteLater();
        m_tcp = nullptr;
    }
    if (on) {
        m_beaconTimer.start();
        m_accountTimer.start();
        beacon();
    } else {
        m_beaconTimer.stop();
    }
}

// A tag only the devices of one account can make: HMAC(account key, id + the current 5 minutes).
static QByteArray tagFor(const QByteArray &key, const QString &id, qint64 bucket)
{
    return QMessageAuthenticationCode::hash((id + QLatin1Char(':') + QString::number(bucket)).toUtf8(), key,
                                            QCryptographicHash::Sha256).toHex().left(24);
}

void PetalDropService::beacon()
{
    if (!m_udp || !m_tcp)
        return;
    const QString id = selfId();
    QJsonObject b{{K("petal"), 1}, {K("id"), id}, {K("name"), deviceName()}, {K("kind"), deviceKind()},
                  {K("port"), int(m_tcp->serverPort())}};
    if (!m_key.isEmpty())
        b.insert(K("tag"), QString::fromLatin1(tagFor(m_key, id, QDateTime::currentSecsSinceEpoch() / 300)));
    const QByteArray data = QJsonDocument(b).toJson(QJsonDocument::Compact);
    m_udp->writeDatagram(data, QHostAddress::Broadcast, BeaconPort);
    // Not every network lets a broadcast through, nor a loopback-only test: say it to localhost too.
    m_udp->writeDatagram(data, QHostAddress::LocalHost, BeaconPort);
}

void PetalDropService::readBeacons()
{
    while (m_udp && m_udp->hasPendingDatagrams()) {
        QHostAddress from;
        QByteArray data(int(m_udp->pendingDatagramSize()), Qt::Uninitialized);
        m_udp->readDatagram(data.data(), data.size(), &from);
        const QJsonObject b = QJsonDocument::fromJson(data).object();
        if (b.value(K("petal")).toInt() != 1 || data.size() > 2048)
            continue;
        const QString id = b.value(K("id")).toString().left(40);
        if (id.isEmpty() || id == selfId())
            continue;
        Peer p;
        p.id = id;
        p.name = b.value(K("name")).toString().left(80);
        p.kind = b.value(K("kind")).toString() == QLatin1String("desktop") ? K("desktop") : K("phone");
        p.port = quint16(b.value(K("port")).toInt());
        p.address = from.isNull() ? QString() : QHostAddress(from.toIPv4Address()).toString();
        p.seen = QDateTime::currentMSecsSinceEpoch();
        const QString tag = b.value(K("tag")).toString();
        if (!m_key.isEmpty() && !tag.isEmpty()) {
            const qint64 bucket = QDateTime::currentSecsSinceEpoch() / 300;
            for (qint64 d : {0, -1})
                if (tag.toLatin1() == tagFor(m_key, id, bucket + d))
                    p.mine = true;
        }
        if (p.port == 0 || p.address.isEmpty())
            continue;
        m_beaconPeers.insert(id, p);
    }
}

// The account's key, and where its other devices listen; tells the server where this one does.
void PetalDropService::syncAccount()
{
    if (!m_account->signedIn())
        return;
    if (m_tcp) {
        QJsonArray addresses;
        for (const QHostAddress &a : QNetworkInterface::allAddresses())
            if (a.protocol() == QAbstractSocket::IPv4Protocol && !a.isLoopback())
                addresses.append(a.toString());
        QNetworkReply *r = m_account->request("POST", K("/api/device/lan"), QJsonObject{{K("addresses"), addresses}, {K("port"), int(m_tcp->serverPort())}});
        connect(r, &QNetworkReply::finished, r, &QObject::deleteLater);
    }
    QNetworkReply *reply = m_account->request("GET", K("/api/device/petal"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError)
            return;
        const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
        m_key = QByteArray::fromHex(r.value(K("key")).toString().toLatin1());
        m_accountPeers.clear();
        for (const QJsonValue &v : r.value(K("peers")).toArray()) {
            const QJsonObject o = v.toObject();
            const QJsonArray addresses = o.value(K("addresses")).toArray();
            if (addresses.isEmpty() || o.value(K("port")).toInt() <= 0)
                continue;
            Peer p;
            p.id = QStringLiteral("d%1").arg(o.value(K("id")).toInt());
            p.name = o.value(K("name")).toString();
            p.kind = o.value(K("kind")).toString();
            p.address = addresses.first().toString();
            p.port = quint16(o.value(K("port")).toInt());
            p.mine = true;
            p.seen = QDateTime::currentMSecsSinceEpoch();
            m_accountPeers.insert(p.id, p);
        }
    });
}

QJsonArray PetalDropService::peerList() const
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QHash<QString, Peer> all = m_accountPeers;
    for (const Peer &p : m_beaconPeers) {
        if (now - p.seen > 12000)
            continue;
        Peer merged = p;
        merged.mine = p.mine || all.value(p.id).mine;
        all.insert(p.id, merged);
    }
    QList<Peer> list = all.values();
    std::sort(list.begin(), list.end(), [](const Peer &a, const Peer &b) { return a.mine != b.mine ? a.mine : a.name < b.name; });
    QJsonArray out;
    for (const Peer &p : list)
        out.append(QJsonObject{{K("id"), p.id}, {K("name"), p.name}, {K("kind"), p.kind}, {K("mine"), p.mine},
                               {K("address"), p.address}, {K("port"), int(p.port)}});
    return out;
}

QJsonObject PetalDropService::state() const
{
    QJsonArray transfers;
    for (const Transfer *t : m_transfers)
        transfers.append(QJsonObject{{K("id"), t->id}, {K("peer"), t->peerName}, {K("state"), t->state},
                                     {K("sent"), double(t->sent)}, {K("total"), double(t->total)}, {K("error"), t->error}});
    return {{K("receive"), receiveMode()}, {K("name"), deviceName()}, {K("kind"), deviceKind()},
            {K("port"), m_tcp ? int(m_tcp->serverPort()) : 0}, {K("signedIn"), m_account->signedIn()},
            {K("peers"), peerList()}, {K("transfers"), transfers}};
}

QByteArray PetalDropService::sign(const QString &id, const QJsonArray &files) const
{
    if (m_key.isEmpty())
        return {};
    return QMessageAuthenticationCode::hash(id.toUtf8() + '\n' + QJsonDocument(files).toJson(QJsonDocument::Compact), m_key,
                                            QCryptographicHash::Sha256).toHex();
}

bool PetalDropService::isMine(const QString &id, const QJsonArray &files, const QString &signature) const
{
    const QByteArray expected = sign(id, files);
    return !expected.isEmpty() && !signature.isEmpty() && expected == signature.toLatin1();
}

// ---- receiving ------------------------------------------------------------------------------------

void PetalDropService::incomingConnection()
{
    while (m_tcp && m_tcp->hasPendingConnections()) {
        auto *in = new Incoming;
        in->sock = m_tcp->nextPendingConnection();
        in->sock->setParent(this);
        in->dir = Paths::userMedia() + QStringLiteral("/Download/PetalDrop");
        connect(in->sock, &QTcpSocket::readyRead, this, [this, in] {
            in->buf += in->sock->readAll();
            readIncoming(in);
        });
        connect(in->sock, &QTcpSocket::disconnected, this, [this, in] {
            if (in->stage != Incoming::Closed)
                finishIncoming(in, QStringLiteral("cut"));
        });
        // A connection that says nothing is dropped.
        QTimer::singleShot(30000, in->sock, [this, in] { if (in->stage == Incoming::Offer) finishIncoming(in, QStringLiteral("silent")); });
    }
}

void PetalDropService::readIncoming(Incoming *in)
{
    while (in->stage != Incoming::Closed) {
        if (in->buf.size() > kMaxLine && in->stage != Incoming::Body) {
            finishIncoming(in, QStringLiteral("too long"));
            return;
        }
        if (in->stage == Incoming::Offer) {
            const QByteArray l = takeLine(in->buf);
            if (l.isNull())
                return;
            const QJsonObject offer = QJsonDocument::fromJson(l).object();
            const QJsonArray files = offer.value(K("files")).toArray();
            qint64 total = 0;
            bool ok = offer.value(K("type")).toString() == QLatin1String("offer") && !files.isEmpty() && files.size() <= kMaxFiles;
            for (const QJsonValue &v : files) {
                const QJsonObject f = v.toObject();
                const qint64 size = qint64(f.value(K("size")).toDouble(-1));
                if (size < 0 || f.value(K("name")).toString().isEmpty())
                    ok = false;
                total += size;
            }
            if (!ok || total > kMaxTotal) {
                in->sock->write(line({{K("type"), K("decline")}, {K("why"), K("bad offer")}}));
                finishIncoming(in, QStringLiteral("bad offer"));
                return;
            }
            const QString id = offer.value(K("from")).toObject().value(K("id")).toString();
            in->fromName = offer.value(K("from")).toObject().value(K("name")).toString().left(80);
            in->files = files;
            in->mine = isMine(id, files, offer.value(K("sig")).toString());
            in->stage = Incoming::Await;
            const QString mode = receiveMode();
            auto answer = [this, in](bool accept) {
                if (in->stage == Incoming::Closed)
                    return;
                if (!accept) {
                    in->sock->write(line({{K("type"), K("decline")}}));
                    finishIncoming(in, QStringLiteral("declined"));
                    return;
                }
                QDir().mkpath(in->dir);
                in->sock->write(line({{K("type"), K("accept")}}));
                in->stage = Incoming::Header;
                QMetaObject::invokeMethod(this, [this, in] { if (in->stage != Incoming::Closed) readIncoming(in); }, Qt::QueuedConnection);
            };
            if (mode == QLatin1String("off") || (mode == QLatin1String("mydevices") && !in->mine)) {
                answer(false);
                return;
            }
            if (in->mine) {
                answer(true);   // the same AstraID: no question
                return;
            }
            const QString what = files.size() == 1 ? files.first().toObject().value(K("name")).toString()
                                                   : QStringLiteral("%1 files").arg(files.size());
            m_dialogs->show(QString(),
                            QJsonObject{{K("title"), QStringLiteral("%1 wants to send you %2").arg(in->fromName.isEmpty() ? K("A device nearby") : in->fromName, what)},
                                        {K("message"), K("Received with PetalDrop. Only accept what you expect.")},
                                        {K("icon"), K("share")},
                                        {K("buttons"), QJsonArray{QJsonObject{{K("id"), K("decline")}, {K("label"), K("Decline")}},
                                                                  QJsonObject{{K("id"), K("accept")}, {K("label"), K("Accept")}, {K("style"), K("primary")}}}}},
                            K("decline"), [answer](const QString &button) { answer(button == QLatin1String("accept")); });
            return;
        }
        if (in->stage == Incoming::Await)
            return;
        if (in->stage == Incoming::Header) {
            const QByteArray l = takeLine(in->buf);
            if (l.isNull())
                return;
            const QJsonObject h = QJsonDocument::fromJson(l).object();
            const QString type = h.value(K("type")).toString();
            if (type == QLatin1String("done")) {
                in->sock->write(line({{K("type"), K("done")}, {K("count"), in->received.size()}}));
                finishIncoming(in, QStringLiteral("done"));
                return;
            }
            const qint64 size = qint64(h.value(K("size")).toDouble(-1));
            if (type != QLatin1String("file") || size < 0 || in->index >= in->files.size() ||
                size != qint64(in->files.at(in->index).toObject().value(K("size")).toDouble(-2))) {
                in->sock->write(line({{K("type"), K("error")}, {K("why"), K("unexpected file")}}));
                finishIncoming(in, QStringLiteral("protocol"));
                return;
            }
            in->outPath = uniquePath(in->dir, safeName(h.value(K("name")).toString()));
            in->out = new QFile(in->outPath);
            if (!in->out->open(QIODevice::WriteOnly)) {
                in->sock->write(line({{K("type"), K("error")}, {K("why"), K("cannot write")}}));
                finishIncoming(in, QStringLiteral("write"));
                return;
            }
            in->expected = h.value(K("sha256")).toString();
            in->hash.reset();
            in->remaining = size;
            in->stage = Incoming::Body;
            ++in->index;
        }
        if (in->stage == Incoming::Body) {
            const qint64 n = qMin<qint64>(in->remaining, in->buf.size());
            if (n > 0) {
                in->out->write(in->buf.constData(), n);
                in->hash.addData(QByteArrayView(in->buf.constData(), n));
                in->buf.remove(0, int(n));
                in->remaining -= n;
            }
            if (in->remaining > 0)
                return;
            in->out->close();
            delete in->out;
            in->out = nullptr;
            if (QString::fromLatin1(in->hash.result().toHex()) != in->expected) {
                QFile::remove(in->outPath);
                in->sock->write(line({{K("type"), K("error")}, {K("why"), K("checksum")}}));
                finishIncoming(in, QStringLiteral("checksum"));
                return;
            }
            in->received.append(in->outPath);
            in->stage = Incoming::Header;
        }
    }
}

void PetalDropService::finishIncoming(Incoming *in, const QString &outcome)
{
    if (in->stage == Incoming::Closed)
        return;
    in->stage = Incoming::Closed;
    if (in->out) {
        in->out->close();
        QFile::remove(in->outPath);
        delete in->out;
        in->out = nullptr;
    }
    if (outcome == QLatin1String("done") && !in->received.isEmpty()) {
        const int n = in->received.size();
        m_notifications->post(K("com.astra.files"), n == 1 ? QFileInfo(in->received.first()).fileName() : QStringLiteral("%1 files").arg(n),
                              QStringLiteral("From %1, with PetalDrop").arg(in->fromName.isEmpty() ? K("a device nearby") : in->fromName),
                              QJsonObject{{K("args"), QJsonObject{{K("action"), K("open")}, {K("files"), QJsonArray{in->received.first()}}}}});
        m_server->broadcast(K("petaldrop.received"), QJsonObject{{K("from"), in->fromName}, {K("files"), QJsonArray::fromStringList(in->received)}});
    }
    qCInfo(lcPetal) << "incoming from" << in->fromName << outcome;
    in->sock->flush();
    in->sock->disconnectFromHost();
    in->sock->deleteLater();
    delete in;
}

// ---- sending --------------------------------------------------------------------------------------

void PetalDropService::emitTransfer(const Transfer *t)
{
    m_server->broadcast(K("petaldrop.transfer"),
                        QJsonObject{{K("id"), t->id}, {K("peer"), t->peerName}, {K("state"), t->state}, {K("sent"), double(t->sent)},
                                    {K("total"), double(t->total)}, {K("error"), t->error}},
                        [](const Caller &c) { return c.isSystem() || c.can(QLatin1String(permissions::NEARBY_DEVICES)); });
}

void PetalDropService::startTransfer(Transfer *t)
{
    Peer peer;
    bool found = false;
    for (const QJsonValue &v : peerList()) {
        const QJsonObject o = v.toObject();
        if (o.value(K("id")).toString() == t->peerId) {
            peer.address = o.value(K("address")).toString();
            peer.port = quint16(o.value(K("port")).toInt());
            peer.name = o.value(K("name")).toString();
            found = true;
        }
    }
    if (!found) {
        t->state = K("failed");
        t->error = K("That device is not nearby any more.");
        emitTransfer(t);
        return;
    }
    t->peerName = peer.name;
    t->sock = new QTcpSocket(this);
    QJsonArray files;
    for (const Transfer::File &f : std::as_const(t->files))
        files.append(QJsonObject{{K("name"), f.name}, {K("size"), double(f.size)}});
    const QString id = selfId();
    QJsonObject offer{{K("type"), K("offer")}, {K("from"), QJsonObject{{K("id"), id}, {K("name"), deviceName()}, {K("kind"), deviceKind()}}},
                      {K("files"), files}};
    const QByteArray sig = sign(id, files);
    if (!sig.isEmpty())
        offer.insert(K("sig"), QString::fromLatin1(sig));
    connect(t->sock, &QTcpSocket::connected, this, [this, t, offer] {
        t->state = K("waiting");
        t->sock->write(line(offer));
        emitTransfer(t);
    });
    connect(t->sock, &QTcpSocket::readyRead, this, [this, t] {
        t->rx += t->sock->readAll();
        for (;;) {
            const QByteArray l = takeLine(t->rx);
            if (l.isNull())
                return;
            const QString type = QJsonDocument::fromJson(l).object().value(K("type")).toString();
            if (type == QLatin1String("accept") && !t->accepted) {
                t->accepted = true;
                t->state = K("sending");
                emitTransfer(t);
                pump(t);
            } else if (type == QLatin1String("decline")) {
                t->state = K("declined");
                t->finished = true;
                emitTransfer(t);
                t->sock->disconnectFromHost();
            } else if (type == QLatin1String("done")) {
                t->state = K("done");
                t->finished = true;
                emitTransfer(t);
                t->sock->disconnectFromHost();
            } else if (type == QLatin1String("error")) {
                t->state = K("failed");
                t->error = QJsonDocument::fromJson(l).object().value(K("why")).toString();
                t->finished = true;
                emitTransfer(t);
                t->sock->disconnectFromHost();
            }
        }
    });
    connect(t->sock, &QTcpSocket::bytesWritten, this, [this, t] { if (t->accepted && !t->finished) pump(t); });
    connect(t->sock, &QTcpSocket::errorOccurred, this, [this, t] {
        if (t->finished)
            return;
        t->state = K("failed");
        t->error = t->sock->errorString();
        t->finished = true;
        emitTransfer(t);
    });
    connect(t->sock, &QTcpSocket::disconnected, this, [this, t] {
        if (!t->finished) {
            t->state = K("failed");
            t->error = K("The connection was cut.");
            t->finished = true;
            emitTransfer(t);
        }
        if (t->current) {
            delete t->current;
            t->current = nullptr;
        }
    });
    QTimer::singleShot(8000, t->sock, [this, t] {
        if (t->state == QLatin1String("connecting") && !t->finished) {
            t->state = K("failed");
            t->error = K("The device did not answer.");
            t->finished = true;
            emitTransfer(t);
            t->sock->abort();
        }
    });
    t->sock->connectToHost(peer.address, peer.port);
}

// Feeds the socket while it has room: the next chunk of the file, then the next file.
void PetalDropService::pump(Transfer *t)
{
    while (t->sock->bytesToWrite() < 4 * kChunk && !t->finished) {
        if (!t->current) {
            if (t->index >= t->files.size()) {
                t->sock->write(line({{K("type"), K("done")}}));
                t->state = K("finishing");
                emitTransfer(t);
                return;
            }
            const Transfer::File &f = t->files.at(t->index);
            t->current = new QFile(f.path);
            if (!t->current->open(QIODevice::ReadOnly)) {
                t->state = K("failed");
                t->error = QStringLiteral("Cannot read %1.").arg(f.name);
                t->finished = true;
                emitTransfer(t);
                t->sock->abort();
                return;
            }
            t->sock->write(line({{K("type"), K("file")}, {K("name"), f.name}, {K("size"), double(f.size)}, {K("sha256"), f.sha}}));
        }
        const QByteArray chunk = t->current->read(kChunk);
        if (chunk.isEmpty()) {
            t->current->close();
            delete t->current;
            t->current = nullptr;
            ++t->index;
            continue;
        }
        t->sock->write(chunk);
        t->sent += chunk.size();
    }
    emitTransfer(t);
}

QJsonValue PetalDropService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::NEARBY_DEVICES));
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("peers"))
        return peerList();
    if (call == QLatin1String("cancel")) {
        Transfer *t = m_transfers.value(params.value(K("id")).toInt());
        if (!t)
            return false;
        t->state = K("cancelled");
        t->finished = true;
        if (t->sock)
            t->sock->abort();
        emitTransfer(t);
        return true;
    }
    if (call == QLatin1String("send")) {
        const QString peer = params.value(K("peer")).toString();
        const QJsonArray paths = params.value(K("files")).toArray();
        if (peer.isEmpty() || paths.isEmpty() || paths.size() > kMaxFiles)
            throw RpcError{protocol::InvalidParams, K("peer and files (1 to 500) are required")};
        // Only what the app may share: the shared storage and its own data directory.
        const QString media = QFileInfo(Paths::userMedia()).canonicalFilePath();
        const QString own = caller.isSystem() ? QString() : QFileInfo(Paths::dataData() + QLatin1Char('/') + caller.package).canonicalFilePath();
        auto *t = new Transfer;
        t->id = m_nextTransfer++;
        t->peerId = peer;
        t->package = caller.package;
        for (const QJsonValue &v : paths) {
            const QFileInfo info(v.toString());
            const QString canonical = info.canonicalFilePath();
            const bool allowed = caller.isSystem() || (!media.isEmpty() && canonical.startsWith(media + QLatin1Char('/'))) ||
                                 (!own.isEmpty() && canonical.startsWith(own + QLatin1Char('/')));
            if (canonical.isEmpty() || !info.isFile() || !allowed) {
                delete t;
                throw RpcError{protocol::PermissionDenied, QStringLiteral("cannot share %1").arg(v.toString())};
            }
            Transfer::File f;
            f.path = canonical;
            f.name = safeName(info.fileName());
            f.size = info.size();
            f.sha = sha256Of(canonical);
            t->total += f.size;
            t->files.append(f);
        }
        if (t->total > kMaxTotal) {
            delete t;
            throw RpcError{protocol::InvalidParams, K("too much to send at once")};
        }
        m_transfers.insert(t->id, t);
        startTransfer(t);
        return QJsonObject{{K("id"), t->id}};
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
