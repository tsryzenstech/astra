// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QByteArray>
#include <QJsonArray>
#include <QString>

// What NFC tags hold, and how it is read from them and written to them. Nothing
// here touches the radio: a TagLink carries the commands (the kernel's NFC
// socket on the phone, a tag made of memory in the tests).
namespace astrad::nfc {

// One exchange with the tag in front of the phone.
class TagLink
{
public:
    virtual ~TagLink() = default;
    // False when the tag did not answer (it moved away).
    virtual bool transceive(const QByteArray &command, QByteArray *response) = 0;
};

// ---- NDEF: the message a tag carries -----------------------------------------

// The records of a message, each {kind, value, ...}:
//   {kind: "uri",  value: "https://..."}                  also tel:, mailto:...
//   {kind: "text", value, language}
//   {kind: "mime", type: "text/vcard", value: text or "", size}
//   {kind: "app",  type: "android.com:pkg", value}
//   {kind: "other", type, size}
// A smart poster gives its own records (its address and titles).
QJsonArray parseMessage(const QByteArray &message);
// The first address in the records, else the first text; "" when neither.
QString summary(const QJsonArray &records);

QByteArray uriMessage(const QString &uri);
QByteArray textMessage(const QString &text, const QString &language = QStringLiteral("en"));

// ---- Type 2 tags (NTAG, MIFARE Ultralight: most stickers and cards) -----------

struct Type2Info {
    int capacity = 0;     // bytes of the data area
    bool writable = false;
    bool formatted = false; // it has the NDEF capability container
};

// The NDEF message of the tag ("" when it has none). False when the tag stopped
// answering or is not an NDEF tag (error says which).
bool readType2(TagLink &link, QByteArray *message, Type2Info *info, QString *error);
bool writeType2(TagLink &link, const QByteArray &message, QString *error);

// ---- Type 4 tags (ISO-DEP: DESFire, NTAG 424, cards that answer APDUs) ---------

bool readType4(TagLink &link, QByteArray *message, QString *error);

// Where the NDEF message is in a Type 2 tag's data area (TLV blocks). False
// while more of the area has to be read; a missing message gives length 0.
bool findNdefTlv(const QByteArray &area, int *offset, int *length, bool *present);

} // namespace astrad::nfc
