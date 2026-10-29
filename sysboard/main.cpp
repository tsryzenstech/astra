// SPDX-License-Identifier: Apache-2.0
//
// SysBoard - the astraOS system shell.
//
// SysBoard is the Wayland compositor and owns everything that is always on
// screen: the status bar, lock screen, home screen (launcher - not
// replaceable), Control Center, Notification Center and the app window
// transitions driven by the AnimationEngine.

#include "host.h"

#include <astra/client.h>
#include <astra/localization.h>
#include <astra/paths.h>
#include <astra/properties.h>

#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

#include <csignal>
#include <unistd.h>

using astra::Paths;
using astra::Properties;

// A setting read straight from astrad's store: needed before the
// application object (and so the astrad connection) exists.
static QJsonValue userSetting(const QString &key)
{
    for (const QString &path : {Paths::dataSystem() + QStringLiteral("/settings.json"),
                                Paths::resolve(QStringLiteral("/vendor/etc/settings/defaults.json")),
                                Paths::resolve(QStringLiteral("/system/etc/settings/defaults.json"))}) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        if (o.contains(key))
            return o.value(key);
    }
    return {};
}

static void setDefaultEnv(const char *key, const QByteArray &value)
{
    if (!qEnvironmentVariableIsSet(key))
        qputenv(key, value);
}

int main(int argc, char **argv)
{
    // Restarted by the previous SysBoard: wait until it released the display.
    if (const qint64 previous = qEnvironmentVariableIntValue("ASTRA_SYSBOARD_WAIT_PID")) {
        for (int i = 0; i < 100 && ::kill(pid_t(previous), 0) == 0; ++i)
            ::usleep(50000);
        qunsetenv("ASTRA_SYSBOARD_WAIT_PID");
    }

    if (!Paths::isDevelopmentRoot()) {
        // On devices SysBoard drives the panel directly through KMS.
        setDefaultEnv("QT_QPA_PLATFORM", "eglfs");
        setDefaultEnv("QT_QPA_EGLFS_INTEGRATION", "eglfs_kms");
        setDefaultEnv("QT_QPA_EGLFS_KMS_ATOMIC", "1");
        setDefaultEnv("QT_QPA_EGLFS_HIDECURSOR", "1");
        setDefaultEnv("XDG_RUNTIME_DIR", QFile::encodeName(Paths::displayDir()));
        // Display size (Settings > Display): the device density times the
        // user's UI size; resolution and refresh rate from astrad's kms.json.
        const double density = Properties::get(QStringLiteral("ro.astra.ui.scale"), QStringLiteral("1")).toDouble();
        const double uiScale = qBound(0.8, userSetting(QStringLiteral("display.ui_scale")).toDouble(1.0), 1.3);
        if (density > 0)
            setDefaultEnv("QT_SCALE_FACTOR", QByteArray::number(density * uiScale, 'f', 3));
        // No GPU yet (firmware missing, driver not probed) or the last start
        // never drew a frame: render in software rather than crash-loop on
        // a black screen. Host removes the marker after the first frame.
        const QString marker = Paths::runtimeDir() + QStringLiteral("/sysboard.starting");
        if (!QFileInfo::exists(QStringLiteral("/dev/dri/renderD128")) || QFileInfo::exists(marker)) {
            qWarning("sysboard: using software rendering");
            setDefaultEnv("MESA_LOADER_DRIVER_OVERRIDE", "kms_swrast");
            setDefaultEnv("GALLIUM_DRIVER", "llvmpipe");
        }
        QDir().mkpath(Paths::runtimeDir());
        QFile(marker).open(QIODevice::WriteOnly);
        const QString kms = Paths::dataSystem() + QStringLiteral("/kms.json");
        if (QFileInfo::exists(kms))
            setDefaultEnv("QT_QPA_EGLFS_KMS_CONFIG", QFile::encodeName(kms));
    }
    setDefaultEnv("QT_WAYLAND_COMPOSITOR_NO_THROTTLE", "0");
    // The astraOS keyboard (sysboard/inputcontext + Keyboard.qml).
    setDefaultEnv("QT_IM_MODULE", "astra");
    const QByteArray plugins = QFile::encodeName(Paths::resolve(QStringLiteral("/system/lib/qt6/plugins")));
    qputenv("QT_PLUGIN_PATH", qEnvironmentVariableIsEmpty("QT_PLUGIN_PATH") ? plugins : plugins + ':' + qgetenv("QT_PLUGIN_PATH"));
    setDefaultEnv("QT_QUICK_CONTROLS_STYLE", "Basic");

    // The boot animation owns the display until we are about to show.
    SysBoardHost::stopBootAnimation();

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("SysBoard"));
    QGuiApplication::setDesktopFileName(QStringLiteral("sysboard"));

    const QDir fonts(Paths::fonts());
    for (const QString &f : fonts.entryList({QStringLiteral("*.ttf")}, QDir::Files)) {
        // Emoji come from the colour emoji font wherever a font lacks them.
        const int id = QFontDatabase::addApplicationFont(fonts.filePath(f));
        for (const QString &family : QFontDatabase::applicationFontFamilies(id))
            if (family.contains(QLatin1String("emoji"), Qt::CaseInsensitive))
                QFontDatabase::addApplicationFallbackFontFamily(QChar::Script_Common, family);
    }
    QGuiApplication::setFont(QFont(QStringLiteral("Poppins")));

    SysBoardHost::instance();
    auto *l10n = astra::Localization::instance();
    l10n->addDirectory(Paths::resolve(QStringLiteral("/system/etc/i18n/sysboard")));
    l10n->addDirectory(Paths::resolve(QStringLiteral("/system/framework/i18n")));

    QQmlApplicationEngine engine;
    QObject::connect(l10n, &astra::Localization::languageChanged, &engine, [&engine] { engine.retranslate(); });
    engine.addImportPath(Paths::frameworkQml());
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("SysBoard", "Main");
    return app.exec();
}
