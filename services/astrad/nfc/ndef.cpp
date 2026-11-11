// SPDX-License-Identifier: Apache-2.0
#include "ndef.h"

#include <QJsonObject>
#include <QStringDecoder>

namespace astrad::nfc {

namespace {

QString K(const char *s) { return QString::fromLatin1(s); }

// NFC Forum URI record: the first byte of the payload stands for one of these.
const char *const kUriPrefixes[] = {
    "", "http://www.", "https://www.", "http://", "https://", "tel:", "mailto:",
    "ftp://anonymous:anonymous@", "ftp://ftp.", "ftps://", "sftp://", "smb://", "nfs://", "ftp://",
    "dav://", "news:", "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:", "tftp:",
    "btspp://", "btl2cap://", "btgoep://", "tcpobex://", "irdaobex://", "file://", "urn:epc:id:",
    "urn:epc:tag:", "urn:epc:pat:", "urn:epc:raw:", "urn:epc:", "urn:nfc:",
};
constexpr int kUriPrefixCount = int(sizeof(kUriPrefixes) / sizeof(kUriPrefixes[0]));

constexpr int kMaxText = 4000;      // characters of a record given to the apps
constexpr int kMaxMessage = 8192;   // bytes read from a tag

quint8 at(const QByteArray &b, int i) { return quint8(b.at(i)); }

void parseInto(const QByteArray &m, QJsonArray &out, int depth)
{
    int pos = 0;
    while (pos + 3 <= m.size()) {
        const quint8 flags = at(m, pos++);
        const int tnf = flags & 0x07;
        const bool chunked = flags & 0x20, shortRecord = flags & 0x10, hasId = flags & 0x08, last = flags & 0x40;
        const int typeLength = at(m, pos++);
        qint64 payloadLength = 0;
        if (shortRecord) {
            payloadLength = at(m, pos++);
        } else {
            if (pos + 4 > m.size())
                return;
            payloadLength = (qint64(at(m, pos)) << 24) | (at(m, pos + 1) << 16) | (at(m, pos + 2) << 8) | at(m, pos + 3);
            pos += 4;
        }
        int idLength = 0;
        if (hasId) {
            if (pos >= m.size())
                return;
            idLength = at(m, pos++);
        }
        if (chunked || pos + typeLength + idLength + payloadLength > m.size())
            return; // chunked records are not used by tags; a cut record ends the message
        const QByteArray type = m.mid(pos, typeLength);
        pos += typeLength + idLength;
        const QByteArray payload = m.mid(pos, int(payloadLength));
        pos += int(payloadLength);

        if (tnf == 1 && type == "U" && !payload.isEmpty()) {
            const int code = at(payload, 0);
            const QString prefix = code < kUriPrefixCount ? K(kUriPrefixes[code]) : QString();
            out.append(QJsonObject{{K("kind"), K("uri")},
                                   {K("value"), (prefix + QString::fromUtf8(payload.mid(1))).left(kMaxText)}});
        } else if (tnf == 1 && type == "T" && !payload.isEmpty()) {
            const int status = at(payload, 0);
            const int langLength = status & 0x3f;
            if (1 + langLength <= payload.size()) {
                const QByteArray body = payload.mid(1 + langLength);
                QString text;
                if (status & 0x80) {
                    QStringDecoder utf16(QStringDecoder::Utf16BE); // with a byte order mark it follows the mark
                    text = utf16.decode(body);
                } else {
                    text = QString::fromUtf8(body);
                }
                out.append(QJsonObject{{K("kind"), K("text")}, {K("value"), text.left(kMaxText)},
                                       {K("language"), QString::fromLatin1(payload.mid(1, langLength))}});
            }
        } else if (tnf == 1 && type == "Sp" && depth < 2) {
            parseInto(payload, out, depth + 1);
        } else if (tnf == 2) {
            const QString mime = QString::fromLatin1(type).toLower();
            const bool text = mime.startsWith(QLatin1String("text/")) || mime.endsWith(QLatin1String("json"));
            out.append(QJsonObject{{K("kind"), K("mime")}, {K("type"), mime},
                                   {K("value"), text ? QString::fromUtf8(payload).left(kMaxText) : QString()},
                                   {K("size"), int(payload.size())}});
        } else if (tnf == 3) {
            out.append(QJsonObject{{K("kind"), K("uri")}, {K("value"), QString::fromUtf8(type).left(kMaxText)}});
        } else if (tnf == 4) {
            out.append(QJsonObject{{K("kind"), K("app")}, {K("type"), QString::fromLatin1(type)},
                                   {K("value"), QString::fromUtf8(payload).left(kMaxText)}});
        } else if (tnf != 0) {
            out.append(QJsonObject{{K("kind"), K("other")}, {K("type"), QString::fromLatin1(type)},
                                   {K("size"), int(payload.size())}});
        }
        if (last)
            return;
    }
}

QByteArray record(char type, const QByteArray &payload)
{
    QByteArray out;
    const bool isShort = payload.size() < 256;
    out.append(char(0xC1 | (isShort ? 0x10 : 0))); // first and last record, well-known type
    out.append(char(1));
    if (isShort) {
        out.append(char(payload.size()));
    } else {
        const quint32 n = quint32(payload.size());
        out.append(char(n >> 24)).append(char(n >> 16)).append(char(n >> 8)).append(char(n));
    }
    out.append(type);
    out.append(payload);
    return out;
}

// ---- Type 2 --------------------------------------------------------------------

constexpr char kRead = 0x30;
constexpr char kWrite = char(0xA2);
constexpr char kGetVersion = 0x60;

// Sixteen bytes from a page on (four pages).
bool readPages(TagLink &link, int page, QByteArray *out)
{
    QByteArray response;
    if (!link.transceive(QByteArray(1, kRead).append(char(page)), &response) || response.size() < 16)
        return false;
    *out = response.left(16);
    return true;
}

bool writePage(TagLink &link, int page, const QByteArray &four)
{
    QByteArray response;
    if (!link.transceive(QByteArray(1, kWrite).append(char(page)).append(four), &response))
        return false;
    // The tag acknowledges with four bits, 1010; anything else refuses.
    return response.isEmpty() || (at(response, 0) & 0x0f) == 0x0a;
}

// The whole data area up to the message's end. present says whether it has one.
bool readArea(TagLink &link, const QByteArray &first, int capacity, QByteArray *area, int *offset, int *length, bool *present)
{
    *area = first.mid(4).left(capacity);
    while (!findNdefTlv(*area, offset, length, present)) {
        if (area->size() >= capacity) {
            *present = false; // no end mark: an area without a message
            *length = 0;
            return true;
        }
        QByteArray more;
        if (!readPages(link, 4 + int(area->size()) / 4, &more))
            return false;
        area->append(more);
        area->truncate(capacity);
    }
    return true;
}

// Where the message's block starts, or would: after the blocks that describe
// the tag's lock bits and reserved memory, which stay.
int ndefStart(const QByteArray &area)
{
    int pos = 0;
    while (pos < area.size()) {
        const int t = at(area, pos);
        if ((t != 0x01 && t != 0x02) || pos + 1 >= area.size() || at(area, pos + 1) == 0xff)
            break;
        pos += 2 + at(area, pos + 1);
    }
    return qMin(pos, int(area.size()));
}

// A blank NTAG or Ultralight says how large it is; 0 when it is neither.
int blankCapacity(TagLink &link)
{
    QByteArray v;
    if (!link.transceive(QByteArray(1, kGetVersion), &v) || v.size() < 8 || at(v, 1) != 0x04)
        return 0;
    const int product = at(v, 2), size = at(v, 6);
    if (product == 0x04) // NTAG 213, 215, 216
        return size == 0x0f ? 144 : size == 0x11 ? 496 : size == 0x13 ? 872 : 0;
    if (product == 0x03) // MIFARE Ultralight EV1
        return size == 0x0b ? 48 : size == 0x0e ? 128 : 0;
    return 0;
}

// ---- Type 4 --------------------------------------------------------------------

// The answer without its status, when the status says "done" (90 00).
bool apdu(TagLink &link, const QByteArray &command, QByteArray *data)
{
    QByteArray response;
    if (!link.transceive(command, &response) || response.size() < 2)
        return false;
    if (at(response, int(response.size()) - 2) != 0x90 || at(response, int(response.size()) - 1) != 0x00)
        return false;
    *data = response.left(response.size() - 2);
    return true;
}

QByteArray selectFile(int id)
{
    return QByteArray::fromHex("00a4000c02").append(char(id >> 8)).append(char(id));
}

QByteArray readBinary(int offset, int count)
{
    return QByteArray::fromHex("00b0").append(char(offset >> 8)).append(char(offset)).append(char(count));
}

} // namespace

QJsonArray parseMessage(const QByteArray &message)
{
    QJsonArray out;
    parseInto(message, out, 0);
    return out;
}

QString summary(const QJsonArray &records)
{
    for (const char *kind : {"uri", "text"})
        for (const QJsonValue &r : records)
            if (r.toObject().value(K("kind")).toString() == QLatin1String(kind))
                return r.toObject().value(K("value")).toString();
    return {};
}

QByteArray uriMessage(const QString &uri)
{
    int best = 0;
    for (int i = 1; i < kUriPrefixCount; ++i)
        if (uri.startsWith(QLatin1String(kUriPrefixes[i]), Qt::CaseInsensitive) &&
            qstrlen(kUriPrefixes[i]) > qstrlen(kUriPrefixes[best]))
            best = i;
    QByteArray payload;
    payload.append(char(best));
    payload.append(uri.mid(int(qstrlen(kUriPrefixes[best]))).toUtf8());
    return record('U', payload);
}

QByteArray textMessage(const QString &text, const QString &language)
{
    const QByteArray lang = language.toLatin1().left(0x3f);
    QByteArray payload;
    payload.append(char(lang.size()));
    payload.append(lang);
    payload.append(text.toUtf8());
    return record('T', payload);
}

bool findNdefTlv(const QByteArray &area, int *offset, int *length, bool *present)
{
    int pos = 0;
    while (pos < area.size()) {
        const int t = at(area, pos);
        if (t == 0x00) {
            pos++;
            continue;
        }
        if (t == 0xfe) {
            *present = false;
            *length = 0;
            return true;
        }
        if (pos + 1 >= area.size())
            return false;
        int len = at(area, pos + 1), header = 2;
        if (len == 0xff) {
            if (pos + 3 >= area.size())
                return false;
            len = (at(area, pos + 2) << 8) | at(area, pos + 3);
            header = 4;
        }
        if (t == 0x03) {
            *offset = pos + header;
            *length = len;
            *present = true;
            return pos + header + len <= area.size();
        }
        pos += header + len;
    }
    return false;
}

bool readType2(TagLink &link, QByteArray *message, Type2Info *info, QString *error)
{
    message->clear();
    QByteArray first;
    if (!readPages(link, 3, &first)) {
        *error = K("The tag moved away");
        return false;
    }
    info->formatted = at(first, 0) == 0xe1;
    if (!info->formatted)
        return true; // a blank tag: nothing to read, maybe something to write
    info->capacity = at(first, 2) * 8;
    info->writable = (at(first, 3) & 0x0f) == 0;
    if (info->capacity < 12 || info->capacity > kMaxMessage) {
        *error = K("The tag's size is not valid");
        return false;
    }
    QByteArray area;
    int offset = 0, length = 0;
    bool present = false;
    if (!readArea(link, first, info->capacity, &area, &offset, &length, &present)) {
        *error = K("The tag moved away");
        return false;
    }
    if (present)
        *message = area.mid(offset, length);
    return true;
}

bool writeType2(TagLink &link, const QByteArray &message, QString *error)
{
    QByteArray first;
    if (!readPages(link, 3, &first)) {
        *error = K("The tag moved away");
        return false;
    }
    int capacity = at(first, 2) * 8;
    if (at(first, 0) != 0xe1) {
        // A tag never used: its first write says what it holds, once and for all.
        capacity = first.left(4) == QByteArray(4, '\0') ? blankCapacity(link) : 0;
        if (!capacity) {
            *error = K("This tag cannot hold a message");
            return false;
        }
        if (!writePage(link, 3, QByteArray::fromHex("e110").append(char(capacity / 8)).append('\0'))) {
            *error = K("The tag could not be prepared");
            return false;
        }
        first = first.left(4) + QByteArray(12, '\0');
    } else if ((at(first, 3) & 0x0f) != 0) {
        *error = K("This tag is read-only");
        return false;
    }

    QByteArray block;
    block.append(char(0x03));
    if (message.size() < 0xff) {
        block.append(char(message.size()));
    } else {
        block.append(char(0xff)).append(char(message.size() >> 8)).append(char(message.size()));
    }
    block.append(message);
    block.append(char(0xfe));

    const QByteArray head = first.mid(4);       // pages 4 to 6 as they are
    const int start = ndefStart(head);
    if (start + block.size() > capacity) {
        *error = K("The message does not fit on this tag (%1 of %2 bytes)").arg(start + block.size()).arg(capacity);
        return false;
    }
    QByteArray data = head.left(start) + block;
    while (data.size() % 4)
        data.append('\0');
    // From the page the block starts in; what precedes it in that page is rewritten as it was.
    for (int i = (start / 4) * 4; i < data.size(); i += 4) {
        if (!writePage(link, 4 + i / 4, data.mid(i, 4))) {
            *error = K("The tag moved away while it was written: hold it still and try again");
            return false;
        }
    }
    QByteArray written;
    Type2Info info;
    QString ignored;
    if (!readType2(link, &written, &info, &ignored) || written != message) {
        *error = K("The tag did not keep the message");
        return false;
    }
    return true;
}

bool readType4(TagLink &link, QByteArray *message, QString *error)
{
    message->clear();
    QByteArray data;
    // The NDEF application, its capability container, then the file that names.
    if (!apdu(link, QByteArray::fromHex("00a4040007d276000085010100"), &data)) {
        *error = K("This card holds no message");
        return false;
    }
    if (!apdu(link, selectFile(0xe103), &data) || !apdu(link, readBinary(0, 15), &data) || data.size() < 15 ||
        at(data, 7) != 0x04) {
        *error = K("This card holds no message");
        return false;
    }
    const int maxRead = qBound(1, (at(data, 3) << 8) | at(data, 4), 0xf0);
    const int file = (at(data, 9) << 8) | at(data, 10);
    if (at(data, 13) != 0x00) {
        *error = K("This card's message is protected");
        return false;
    }
    if (!apdu(link, selectFile(file), &data) || !apdu(link, readBinary(0, 2), &data) || data.size() < 2) {
        *error = K("The card moved away");
        return false;
    }
    const int length = (at(data, 0) << 8) | at(data, 1);
    if (length > kMaxMessage) {
        *error = K("The card's message is too large");
        return false;
    }
    while (message->size() < length) {
        const int count = qMin(maxRead, length - int(message->size()));
        if (!apdu(link, readBinary(2 + int(message->size()), count), &data) || data.isEmpty()) {
            *error = K("The card moved away");
            return false;
        }
        message->append(data);
    }
    message->truncate(length);
    return true;
}

} // namespace astrad::nfc
