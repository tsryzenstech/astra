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

// The DRM device driving the panel: the card with a connected connector
// (/sys/class/drm/cardN-DSI-1/status). Its number is not always 0 (a boot
// framebuffer driver may have taken card0 before the display driver), and
// the display driver may still be probing when SysBoard starts: wait for it.
static QString displayCard(int timeoutMs)
{
    for (int waited = 0;; waited += 100) {
        const QDir drm(QStringLiteral("/sys/class/drm"));
        // First priority: the internal panel (DSI/eDP).
        for (const QString &pattern : {QStringLiteral("card*-DSI-*"), QStringLiteral("card*-eDP-*")}) {
            for (const QString &entry : drm.entryList({pattern}, QDir::Dirs | QDir::System, QDir::Name)) {
                QFile status(drm.filePath(entry) + QStringLiteral("/status"));
                if (status.open(QIODevice::ReadOnly) && status.readAll().trimmed() == "connected") {
                    const QString card = QStringLiteral("/dev/dri/") + entry.section(QLatin1Char('-'), 0, 0);
                    if (QFileInfo::exists(card))
                        return card;
                }
            }
        }
        // Second priority: any connected connector that is not a boot framebuffer (Unknown).
        for (const QString &entry : drm.entryList({QStringLiteral("card*-*")}, QDir::Dirs | QDir::System, QDir::Name)) {
            if (entry.contains(QLatin1String("Unknown")))
                continue;
            QFile status(drm.filePath(entry) + QStringLiteral("/status"));
            if (status.open(QIODevice::ReadOnly) && status.readAll().trimmed() == "connected") {
                const QString card = QStringLiteral("/dev/dri/") + entry.section(QLatin1Char('-'), 0, 0);
                if (QFileInfo::exists(card))
                    return card;
            }
        }
        if (waited >= timeoutMs)
            return {};
        ::usleep(100000);
    }
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
        // Wait for the panel's DRM device first: the GPU check below would
        // otherwise see a display driver that is still probing as "no GPU".
        const QString card = displayCard(15000);
        if (card.isEmpty())
            qWarning("sysboard: no display with a connected panel yet");
        // Wait for GPU render node if it hasn't appeared yet.
        for (int i = 0; i < 50 && !QFileInfo::exists(QStringLiteral("/dev/dri/renderD128")); ++i)
            ::usleep(100000);
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
        // eglfs_kms config: astrad's kms.json (mode chosen in Settings) plus
        // the device to open, which Qt would otherwise guess as card0.
        QJsonObject kms;
        QFile saved(Paths::dataSystem() + QStringLiteral("/kms.json"));
        if (saved.open(QIODevice::ReadOnly))
            kms = QJsonDocument::fromJson(saved.readAll()).object();
        if (!card.isEmpty())
            kms.insert(QStringLiteral("device"), card);
        kms.insert(QStringLiteral("hwcursor"), false);
        QFile runtime(Paths::runtimeDir() + QStringLiteral("/kms.json"));
        if (runtime.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            runtime.write(QJsonDocument(kms).toJson());
            runtime.close();
            setDefaultEnv("QT_QPA_EGLFS_KMS_CONFIG", QFile::encodeName(runtime.fileName()));
        }
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
