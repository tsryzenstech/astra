// SPDX-License-Identifier: Apache-2.0
// astrad's NFC: messages, and tags made of memory that answer as real ones do.
#include "nfc/ndef.h"

#include <QJsonObject>
#include <QTest>

using namespace astrad::nfc;

namespace {

// An NTAG: pages of four bytes, READ gives four pages, WRITE takes one.
class Type2Tag : public TagLink
{
public:
    explicit Type2Tag(int dataBytes, bool formatted = true)
        : pages(4 + dataBytes / 4 + 5, QByteArray(4, '\0'))
        , size(dataBytes)
    {
        pages[0] = QByteArray::fromHex("04a1b2c3");
        if (formatted) {
            pages[3] = QByteArray::fromHex("e11000 00");
            pages[3][2] = char(dataBytes / 8);
            // As NXP ships them: a lock control block, then an empty message.
            pages[4] = QByteArray::fromHex("0103a00c");
            pages[5] = QByteArray::fromHex("340300fe");
        }
    }

    bool transceive(const QByteArray &command, QByteArray *response) override
    {
        exchanges++;
        if (failAfter >= 0 && exchanges > failAfter)
            return false;
        const quint8 op = quint8(command.at(0));
        if (op == 0x30 && command.size() == 2) {
            const int page = quint8(command.at(1));
            if (page >= pages.size()) {
                *response = QByteArray(1, '\0'); // NAK
                return true;
            }
            response->clear();
            for (int i = 0; i < 4; ++i)
                response->append(pages.at((page + i) % pages.size())); // it wraps, as the chip does
            return true;
        }
        if (op == 0xA2 && command.size() == 6) {
            const int page = quint8(command.at(1));
            if (readOnly || page < 3 || page >= 4 + size / 4) {
                *response = QByteArray(1, '\0');
                return true;
            }
            pages[page] = command.mid(2, 4);
            *response = QByteArray(1, char(0x0a));
            return true;
        }
        if (op == 0x60) {
            *response = QByteArray::fromHex("0004040201000f03"); // NTAG 213
            return true;
        }
        return false;
    }

    QByteArray data() const
    {
        QByteArray out;
        for (int i = 4; i < 4 + size / 4; ++i)
            out.append(pages.at(i));
        return out;
    }

    QList<QByteArray> pages;
    int size;
    int exchanges = 0;
    int failAfter = -1;
    bool readOnly = false;
};

// A Type 4 card: an application with two files, read with APDUs.
class Type4Tag : public TagLink
{
public:
    explicit Type4Tag(const QByteArray &message, int maxRead = 0x3b)
    {
        cc = QByteArray::fromHex("000f20") + QByteArray(1, char(maxRead >> 8)) + QByteArray(1, char(maxRead))
           + QByteArray::fromHex("0034" "0406" "e104" "0800" "00" "00");
        ndef.append(char(message.size() >> 8)).append(char(message.size())).append(message);
    }

    bool transceive(const QByteArray &c, QByteArray *response) override
    {
        const QByteArray ok = QByteArray::fromHex("9000"), no = QByteArray::fromHex("6a82");
        if (c.startsWith(QByteArray::fromHex("00a40400"))) {
            selectedApp = c.mid(5, 7) == QByteArray::fromHex("d2760000850101");
            *response = selectedApp ? ok : no;
        } else if (c.startsWith(QByteArray::fromHex("00a4000c02")) && selectedApp) {
            const int id = (quint8(c.at(5)) << 8) | quint8(c.at(6));
            current = id == 0xe103 ? &cc : id == 0xe104 ? &ndef : nullptr;
            *response = current ? ok : no;
        } else if (c.startsWith(QByteArray::fromHex("00b0")) && current) {
            const int offset = (quint8(c.at(2)) << 8) | quint8(c.at(3)), count = quint8(c.at(4));
            *response = current->mid(offset, count) + ok;
        } else {
            *response = QByteArray::fromHex("6d00");
        }
        return true;
    }

    QByteArray cc, ndef;
    const QByteArray *current = nullptr;
    bool selectedApp = false;
};

QJsonObject first(const QByteArray &message)
{
    return parseMessage(message).at(0).toObject();
}

} // namespace

class TestNfc : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void uriRecords()
    {
        // "https://www." is one byte on the tag.
        const QByteArray m = uriMessage(QStringLiteral("https://www.astraos.org/hello"));
        QCOMPARE(m, QByteArray::fromHex("d1011255 02") + QByteArray("astraos.org/hello"));
        QCOMPARE(first(m).value(QLatin1String("kind")).toString(), QStringLiteral("uri"));
        QCOMPARE(first(m).value(QLatin1String("value")).toString(), QStringLiteral("https://www.astraos.org/hello"));
        QCOMPARE(first(uriMessage(QStringLiteral("tel:+39021234"))).value(QLatin1String("value")).toString(),
                 QStringLiteral("tel:+39021234"));
        QCOMPARE(first(uriMessage(QStringLiteral("geo:45.46,9.19"))).value(QLatin1String("value")).toString(),
                 QStringLiteral("geo:45.46,9.19"));
    }

    void textRecords()
    {
        const QByteArray m = textMessage(QStringLiteral("Ciao, città"), QStringLiteral("it"));
        const QJsonObject r = first(m);
        QCOMPARE(r.value(QLatin1String("kind")).toString(), QStringLiteral("text"));
        QCOMPARE(r.value(QLatin1String("value")).toString(), QStringLiteral("Ciao, città"));
        QCOMPARE(r.value(QLatin1String("language")).toString(), QStringLiteral("it"));
        QCOMPARE(summary(parseMessage(m)), QStringLiteral("Ciao, città"));
    }

    void longRecord()
    {
        const QString text = QString(700, QLatin1Char('x'));
        const QByteArray m = textMessage(text);
        QCOMPARE(quint8(m.at(0)), quint8(0xC1)); // not a short record
        QCOMPARE(first(m).value(QLatin1String("value")).toString(), text);
    }

    void severalRecordsAndSmartPoster()
    {
        // A smart poster with an address and a title, then a vCard.
        QByteArray uri = QByteArray::fromHex("9101 0c 55 04") + "example.com";  // first of two
        QByteArray title = QByteArray::fromHex("5101 08 54 02") + "enHello";    // last of two
        const QByteArray inner = uri + title;
        QByteArray m = QByteArray::fromHex("9102") + QByteArray(1, char(inner.size())) + "Sp" + inner;
        const QByteArray card = "BEGIN:VCARD\nFN:Ada\nEND:VCARD";
        m += QByteArray::fromHex("520a") + QByteArray(1, char(card.size())) + "text/vcard" + card;
        const QJsonArray records = parseMessage(m);
        QCOMPARE(records.size(), 3);
        QCOMPARE(records.at(0).toObject().value(QLatin1String("value")).toString(), QStringLiteral("https://example.com"));
        QCOMPARE(records.at(1).toObject().value(QLatin1String("value")).toString(), QStringLiteral("Hello"));
        QCOMPARE(records.at(2).toObject().value(QLatin1String("type")).toString(), QStringLiteral("text/vcard"));
        QCOMPARE(summary(records), QStringLiteral("https://example.com"));
    }

    void brokenMessages()
    {
        // Cut anywhere, a message gives what is whole and never reads past its end.
        const QByteArray m = uriMessage(QStringLiteral("https://example.com/a/long/path"));
        for (int i = 0; i < m.size(); ++i)
            QCOMPARE(parseMessage(m.left(i)).size(), 0);
        QCOMPARE(parseMessage(QByteArray::fromHex("c101ffffffff55")).size(), 0);
        QCOMPARE(parseMessage(QByteArray(64, char(0xff))).size(), 0);
    }

    void factoryTagIsEmpty()
    {
        Type2Tag tag(144);
        QByteArray message;
        Type2Info info;
        QString error;
        QVERIFY2(readType2(tag, &message, &info, &error), qPrintable(error));
        QVERIFY(info.formatted);
        QVERIFY(info.writable);
        QCOMPARE(info.capacity, 144);
        QVERIFY(message.isEmpty());
    }

    void writesAndReadsBack_data()
    {
        QTest::addColumn<int>("size");
        QTest::addColumn<int>("length");
        QTest::newRow("NTAG213 short") << 144 << 20;
        QTest::newRow("NTAG213 nearly full") << 144 << 110;
        QTest::newRow("NTAG215 long") << 496 << 400;   // a three byte length
        QTest::newRow("NTAG216 254") << 872 << 245;
    }
    void writesAndReadsBack()
    {
        QFETCH(int, size);
        QFETCH(int, length);
        Type2Tag tag(size);
        const QString text = QString(length, QLatin1Char('a'));
        const QByteArray message = textMessage(text);
        QString error;
        QVERIFY2(writeType2(tag, message, &error), qPrintable(error));
        // The lock control block NXP wrote is still there, the message after it.
        QCOMPARE(tag.data().left(5), QByteArray::fromHex("0103a00c34"));
        QCOMPARE(quint8(tag.data().at(5)), quint8(0x03));

        QByteArray read;
        Type2Info info;
        QVERIFY2(readType2(tag, &read, &info, &error), qPrintable(error));
        QCOMPARE(read, message);
        QCOMPARE(first(read).value(QLatin1String("value")).toString(), text);
    }

    void overwritesALongerMessage()
    {
        Type2Tag tag(144);
        QString error;
        QVERIFY(writeType2(tag, textMessage(QString(90, QLatin1Char('z'))), &error));
        QVERIFY(writeType2(tag, uriMessage(QStringLiteral("https://astraos.org")), &error));
        QByteArray read;
        Type2Info info;
        QVERIFY(readType2(tag, &read, &info, &error));
        QCOMPARE(parseMessage(read).size(), 1);
        QCOMPARE(summary(parseMessage(read)), QStringLiteral("https://astraos.org"));
    }

    void refusesWhatDoesNotFit()
    {
        Type2Tag tag(48);
        const QByteArray before = tag.data();
        QString error;
        QVERIFY(!writeType2(tag, textMessage(QString(80, QLatin1Char('a'))), &error));
        QVERIFY(error.contains(QLatin1String("does not fit")));
        QCOMPARE(tag.data(), before);
    }

    void refusesReadOnlyTags()
    {
        Type2Tag tag(144);
        tag.pages[3][3] = 0x0f;
        QString error;
        QVERIFY(!writeType2(tag, uriMessage(QStringLiteral("https://astraos.org")), &error));
        QVERIFY(error.contains(QLatin1String("read-only")));
        QByteArray read;
        Type2Info info;
        QVERIFY(readType2(tag, &read, &info, &error));
        QVERIFY(!info.writable);
    }

    void preparesABlankTag()
    {
        Type2Tag tag(144, false);
        QByteArray read;
        Type2Info info;
        QString error;
        QVERIFY(readType2(tag, &read, &info, &error));
        QVERIFY(!info.formatted);
        QVERIFY2(writeType2(tag, uriMessage(QStringLiteral("https://astraos.org")), &error), qPrintable(error));
        QCOMPARE(tag.pages.at(3), QByteArray::fromHex("e1101200"));
        QVERIFY(readType2(tag, &read, &info, &error));
        QCOMPARE(summary(parseMessage(read)), QStringLiteral("https://astraos.org"));
    }

    void aTagThatMovesAway()
    {
        for (int after = 0; after < 6; ++after) {
            Type2Tag tag(496);
            QString error;
            QVERIFY(writeType2(tag, textMessage(QString(300, QLatin1Char('q'))), &error));
            tag.exchanges = 0;
            tag.failAfter = after;
            QByteArray read;
            Type2Info info;
            QVERIFY(!readType2(tag, &read, &info, &error));
            QVERIFY(!error.isEmpty());
        }
        Type2Tag tag(144);
        tag.failAfter = 3;
        QString error;
        QVERIFY(!writeType2(tag, textMessage(QString(60, QLatin1Char('q'))), &error));
    }

    void garbageInTheDataArea()
    {
        // No end mark and lengths that point outside: nothing is read, nothing loops.
        Type2Tag tag(144);
        for (int i = 4; i < 4 + 36; ++i)
            tag.pages[i] = QByteArray::fromHex("03ffffff");
        QByteArray read;
        Type2Info info;
        QString error;
        QVERIFY(readType2(tag, &read, &info, &error));
        QVERIFY(read.isEmpty());
        QVERIFY(tag.exchanges < 20);
    }

    void tlvBlocks()
    {
        int offset = 0, length = 0;
        bool present = false;
        QVERIFY(findNdefTlv(QByteArray::fromHex("0103a00c34 0303d1 0100 fe"), &offset, &length, &present));
        QVERIFY(present);
        QCOMPARE(offset, 7);
        QCOMPARE(length, 3);
        QVERIFY(findNdefTlv(QByteArray::fromHex("0000fe"), &offset, &length, &present));
        QVERIFY(!present);
        QVERIFY(!findNdefTlv(QByteArray::fromHex("0310d101"), &offset, &length, &present)); // more to read
        QVERIFY(!findNdefTlv(QByteArray::fromHex("03ff01"), &offset, &length, &present));
    }

    void type4_data()
    {
        QTest::addColumn<int>("length");
        QTest::addColumn<int>("maxRead");
        QTest::newRow("short") << 30 << 0x3b;
        QTest::newRow("several reads") << 500 << 0x3b;
        QTest::newRow("large reads") << 500 << 0xff;
    }
    void type4()
    {
        QFETCH(int, length);
        QFETCH(int, maxRead);
        const QByteArray message = textMessage(QString(length, QLatin1Char('k')));
        Type4Tag tag(message, maxRead);
        QByteArray read;
        QString error;
        QVERIFY2(readType4(tag, &read, &error), qPrintable(error));
        QCOMPARE(read, message);
    }

    void type4WithoutNdef()
    {
        // A payment card: it answers, but not to the NDEF application.
        class Card : public TagLink {
            bool transceive(const QByteArray &, QByteArray *response) override
            {
                *response = QByteArray::fromHex("6a82");
                return true;
            }
        } card;
        QByteArray read;
        QString error;
        QVERIFY(!readType4(card, &read, &error));
        QVERIFY(read.isEmpty());
    }
};

QTEST_APPLESS_MAIN(TestNfc)
#include "tst_nfc.moc"
