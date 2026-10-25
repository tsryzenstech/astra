// SPDX-License-Identifier: Apache-2.0
// Cross-checks the C++ package reader against packages built by apkgtool.py.
#include <astra/apkg.h>

#include <QFile>
#include <QJsonArray>
#include <QTemporaryDir>
#include <QTest>

class TestApkg : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void readsToolOutput()
    {
        astra::Apkg apkg;
        QVERIFY2(apkg.open(QStringLiteral(SETTINGS_APKG)), qPrintable(apkg.errorString()));
        QCOMPARE(apkg.manifest().value(QLatin1String("package")).toString(), QStringLiteral("com.astra.settings"));
        QVERIFY(apkg.manifest().value(QLatin1String("widgets")).toArray().size() >= 1);
        QVERIFY2(apkg.verify(), qPrintable(apkg.errorString()));
    }

    void extracts()
    {
        astra::Apkg apkg;
        QVERIFY(apkg.open(QStringLiteral(SETTINGS_APKG)));
        QTemporaryDir dir;
        QVERIFY(apkg.extractTo(dir.path() + QStringLiteral("/code")));
        QVERIFY(QFile::exists(dir.path() + QStringLiteral("/code/qml/Main.qml")));
        QVERIFY(QFile::exists(dir.path() + QStringLiteral("/code/icon.svg")));
    }

    void rejectsCorruption()
    {
        QFile in(QStringLiteral(SETTINGS_APKG));
        QVERIFY(in.open(QIODevice::ReadOnly));
        QByteArray blob = in.readAll();
        blob[blob.size() / 2] = char(blob[blob.size() / 2] ^ 0x5A);
        QTemporaryDir dir;
        const QString path = dir.path() + QStringLiteral("/bad.apkg");
        QFile out(path);
        QVERIFY(out.open(QIODevice::WriteOnly));
        out.write(blob);
        out.close();
        astra::Apkg apkg;
        QVERIFY(!apkg.open(path) || !apkg.verify());
    }
};

QTEST_GUILESS_MAIN(TestApkg)
#include "tst_apkg.moc"
