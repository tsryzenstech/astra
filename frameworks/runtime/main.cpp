// SPDX-License-Identifier: Apache-2.0
//
// astra-app - application runtime.
//
// Started by astrad's ActivityManager inside the app sandbox (own uid,
// private HOME). Loads the package's main QML component and shows it as a
// fullscreen Wayland window whose app_id is the package name, which is how
// SysBoard matches windows to launcher icons.

#include <astra/client.h>
#include <astra/localization.h>
#include <astra/paths.h>

#include <QDir>
#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlEngine>
#include <QQuickView>

using astra::Paths;

static void loadSystemFonts()
{
    const QDir fonts(Paths::fonts());
    for (const QString &f : fonts.entryList({QStringLiteral("*.ttf"), QStringLiteral("*.otf")}, QDir::Files))
        QFontDatabase::addApplicationFont(fonts.filePath(f));
    QFont font(QStringLiteral("Poppins"));
    font.setStyleStrategy(QFont::PreferAntialias);
    QGuiApplication::setFont(font);
}

static QJsonObject packageInfo(const QString &package)
{
    QString error;
    const QJsonValue info = astra::Client::instance()->callSync(QStringLiteral("packages.get"),
                                                                {{QStringLiteral("package"), package}}, &error);
    if (info.isObject())
        return info.toObject();

    // astrad unavailable: fall back to the extracted package on disk.
    qWarning("astra-app: %s, reading the package from disk", qPrintable(error));
    const QString code = Paths::dataApp() + QLatin1Char('/') + package + QStringLiteral("/code");
    QFile f(code + QStringLiteral("/app.json"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonObject m = QJsonDocument::fromJson(f.readAll()).object();
    return {{QStringLiteral("package"), package},
            {QStringLiteral("name"), m.value(QLatin1String("name"))},
            {QStringLiteral("background"), m.value(QLatin1String("background"))},
            {QStringLiteral("codePath"), code},
            {QStringLiteral("main"), code + QLatin1Char('/') + m.value(QLatin1String("main")).toString()}};
}

int main(int argc, char **argv)
{
    QString package = qEnvironmentVariable("ASTRA_PACKAGE");
    for (int i = 1; i + 1 < argc; ++i)
        if (qstrcmp(argv[i], "--package") == 0)
            package = QString::fromLocal8Bit(argv[i + 1]);
    if (package.isEmpty()) {
        fprintf(stderr, "usage: astra-app --package <name>\n");
        return 2;
    }
    qputenv("ASTRA_PACKAGE", package.toUtf8());

    QGuiApplication app(argc, argv);
    // app_id on Wayland: SysBoard uses it to find the window of a package.
    QGuiApplication::setDesktopFileName(package);
    QGuiApplication::setOrganizationName(QStringLiteral("astra"));
    loadSystemFonts();

    const QJsonObject info = packageInfo(package);
    if (info.isEmpty()) {
        qCritical("astra-app: unknown package %s", qPrintable(package));
        return 1;
    }
    QGuiApplication::setApplicationName(info.value(QLatin1String("name")).toString());
    QGuiApplication::setApplicationDisplayName(info.value(QLatin1String("name")).toString());

    // The app's own strings first, then the framework's; English otherwise.
    auto *l10n = astra::Localization::instance();
    l10n->addDirectory(info.value(QLatin1String("codePath")).toString() + QStringLiteral("/i18n"));
    l10n->addDirectory(Paths::resolve(QStringLiteral("/system/framework/i18n")));

    QQuickView view;
    QObject::connect(l10n, &astra::Localization::languageChanged, view.engine(), [&view] { view.engine()->retranslate(); });
    view.engine()->addImportPath(Paths::frameworkQml());
    view.engine()->addImportPath(info.value(QLatin1String("codePath")).toString() + QStringLiteral("/qml"));
    view.setColor(QColor(info.value(QLatin1String("background")).toString(QStringLiteral("#000000"))));
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.setTitle(QGuiApplication::applicationDisplayName());
    QObject::connect(view.engine(), &QQmlEngine::quit, &app, &QGuiApplication::quit);

    view.setSource(QUrl::fromLocalFile(info.value(QLatin1String("main")).toString()));
    if (view.status() == QQuickView::Error) {
        for (const QQmlError &e : view.errors())
            qCritical("%s", qPrintable(e.toString()));
        return 1;
    }
    view.showFullScreen();
    return app.exec();
}
