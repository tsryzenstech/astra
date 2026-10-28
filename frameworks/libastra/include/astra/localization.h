// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <astra/global.h>

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QStringList>
#include <QTranslator>

namespace astra {

// Translations are plain JSON files, one per language, keyed by the English
// source string:
//
//   i18n/it.json  { "Wi-Fi": "Wi-Fi", "Settings": "Impostazioni",
//                   "%n apps": { "one": "%n app", "other": "%n app" },
//                   "Lock Screen|title": "Schermata di blocco" }
//
// A "source|disambiguation" key wins over the plain key. Missing strings
// fall back to the English source.
class ASTRA_EXPORT JsonTranslator : public QTranslator
{
    Q_OBJECT
public:
    explicit JsonTranslator(QObject *parent = nullptr);
    bool load(const QString &file, const QString &language);
    bool isEmpty() const override { return m_strings.isEmpty(); }
    QString language() const { return m_language; }
    QString translate(const char *context, const char *sourceText, const char *disambiguation, int n) const override;

private:
    QJsonObject m_strings;
    QString m_language;
};

// Follows the "system.language" setting: loads <dir>/<language>.json from
// every registered directory, sets the default QLocale and announces the
// change so QML engines can retranslate.
class ASTRA_EXPORT Localization : public QObject
{
    Q_OBJECT
public:
    static Localization *instance();

    // Directories holding <language>.json files, most specific first
    // (an app's own i18n/ before the framework's).
    void addDirectory(const QString &dir);
    QString language() const { return m_language; }
    void setLanguage(const QString &language);

    struct Language {
        QString code;
        QString name;    // in its own language
        QString english; // in English
    };
    static QList<Language> available();
    static QString systemDefault() { return QStringLiteral("en"); }

Q_SIGNALS:
    void languageChanged(const QString &language);

private:
    Localization();
    void reload();

    QStringList m_dirs;
    QString m_language = systemDefault();
    QList<JsonTranslator *> m_translators;
};

} // namespace astra
