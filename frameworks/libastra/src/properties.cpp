// SPDX-License-Identifier: Apache-2.0
#include "astra/properties.h"
#include "astra/paths.h"

#include <QFile>

namespace astra {

QHash<QString, QString> Properties::parse(const QByteArray &contents)
{
    QHash<QString, QString> out;
    for (const QByteArray &rawLine : contents.split('\n')) {
        const QByteArray line = rawLine.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        const int eq = line.indexOf('=');
        if (eq <= 0)
            continue;
        out.insert(QString::fromUtf8(line.left(eq).trimmed()), QString::fromUtf8(line.mid(eq + 1).trimmed()));
    }
    return out;
}

QHash<QString, QString> Properties::all()
{
    static const QHash<QString, QString> props = [] {
        QHash<QString, QString> merged;
        for (const char *file : {"/system/build.prop", "/vendor/build.prop", "/product/build.prop"}) {
            QFile f(Paths::resolve(QString::fromLatin1(file)));
            if (!f.open(QIODevice::ReadOnly))
                continue;
            merged.insert(parse(f.readAll()));
        }
        return merged;
    }();
    return props;
}

QString Properties::get(const QString &key, const QString &fallback)
{
    return all().value(key, fallback);
}

int Properties::getInt(const QString &key, int fallback)
{
    bool ok = false;
    const int v = get(key).toInt(&ok);
    return ok ? v : fallback;
}

double Properties::getReal(const QString &key, double fallback)
{
    bool ok = false;
    const double v = get(key).toDouble(&ok);
    return ok ? v : fallback;
}

bool Properties::getBool(const QString &key, bool fallback)
{
    const QString v = get(key).toLower();
    if (v == QLatin1String("1") || v == QLatin1String("true") || v == QLatin1String("yes"))
        return true;
    if (v == QLatin1String("0") || v == QLatin1String("false") || v == QLatin1String("no"))
        return false;
    return fallback;
}

} // namespace astra
