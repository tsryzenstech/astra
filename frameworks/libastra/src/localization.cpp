// SPDX-License-Identifier: Apache-2.0
#include <astra/client.h>
#include <astra/localization.h>
#include <astra/paths.h>

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QLocale>

namespace astra {

JsonTranslator::JsonTranslator(QObject *parent)
    : QTranslator(parent)
{
}

bool JsonTranslator::load(const QString &file, const QString &language)
{
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly))
        return false;
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &error);
    if (!doc.isObject()) {
        qWarning("astra: %s: %s", qPrintable(file), qPrintable(error.errorString()));
        return false;
    }
    m_strings = doc.object();
    m_language = language;
    return true;
}

QString JsonTranslator::translate(const char *, const char *sourceText, const char *disambiguation, int n) const
{
    const QString source = QString::fromUtf8(sourceText);
    QJsonValue v(QJsonValue::Undefined);
    if (disambiguation && *disambiguation)
        v = m_strings.value(source + QLatin1Char('|') + QString::fromUtf8(disambiguation));
    if (v.isUndefined() || v.isNull())
        v = m_strings.value(source);
    if (v.isString())
        return v.toString();
    if (v.isObject()) {
        // Plural forms: "one" for exactly one, "other" for the rest (enough
        // for the languages astraOS ships; "zero"/"few"/"many" when given).
        const QJsonObject forms = v.toObject();
        QString key = QStringLiteral("other");
        if (n == 0 && forms.contains(QLatin1String("zero")))
            key = QStringLiteral("zero");
        else if (n == 1)
            key = QStringLiteral("one");
        return forms.value(key).toString(forms.value(QLatin1String("other")).toString());
    }
    return {};
}

Localization *Localization::instance()
{
    static auto *self = new Localization;
    return self;
}

Localization::Localization()
    : QObject(QCoreApplication::instance())
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("settings")});
    auto fetch = [this] {
        Client::instance()->call(QStringLiteral("settings.get"), {{QStringLiteral("key"), QStringLiteral("system.language")}},
                                 [this](const QJsonValue &r, const QString &) {
                                     if (r.isString())
                                         setLanguage(r.toString());
                                 });
    };
    connect(c, &Client::connectedChanged, this, [fetch](bool up) {
        if (up)
            fetch();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("settings.changed") &&
            data.toObject().value(QLatin1String("key")).toString() == QLatin1String("system.language"))
            setLanguage(data.toObject().value(QLatin1String("value")).toString());
    });
    // The language is known before the first frame: no flash of English.
    QString error;
    const QJsonValue v = c->callSync(QStringLiteral("settings.get"), {{QStringLiteral("key"), QStringLiteral("system.language")}}, &error);
    if (v.isString())
        m_language = v.toString();
    QLocale::setDefault(QLocale(m_language));
}

void Localization::addDirectory(const QString &dir)
{
    if (m_dirs.contains(dir))
        return;
    m_dirs.append(dir);
    reload();
}

void Localization::setLanguage(const QString &language)
{
    const QString lang = language.isEmpty() ? systemDefault() : language;
    if (lang == m_language)
        return;
    m_language = lang;
    QLocale::setDefault(QLocale(lang));
    reload();
    Q_EMIT languageChanged(lang);
}

void Localization::reload()
{
    for (JsonTranslator *t : std::as_const(m_translators)) {
        QCoreApplication::removeTranslator(t);
        delete t;
    }
    m_translators.clear();
    // English sources need no translation, but en.json may still give the
    // plural forms ("%n items" -> "1 item").
    // installTranslator() searches the most recently installed first, so
    // install the generic directories first and the specific ones last.
    for (auto it = m_dirs.crbegin(); it != m_dirs.crend(); ++it) {
        auto *t = new JsonTranslator(this);
        if (t->load(*it + QLatin1Char('/') + m_language + QStringLiteral(".json"), m_language)) {
            QCoreApplication::installTranslator(t);
            m_translators.append(t);
        } else {
            delete t;
        }
    }
}

QList<Localization::Language> Localization::available()
{
    return {
        {QStringLiteral("en"), QStringLiteral("English"), QStringLiteral("English")},
        {QStringLiteral("it"), QStringLiteral("Italiano"), QStringLiteral("Italian")},
    };
}

} // namespace astra
