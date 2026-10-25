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
#include <astra/paths.h>
#include <astra/properties.h>

#include <QDir>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>

using astra::Paths;
using astra::Properties;

static void setDefaultEnv(const char *key, const QByteArray &value)
{
    if (!qEnvironmentVariableIsSet(key))
        qputenv(key, value);
}

int main(int argc, char **argv)
{
    if (!Paths::isDevelopmentRoot()) {
        // On devices SysBoard drives the panel directly through KMS.
        setDefaultEnv("QT_QPA_PLATFORM", "eglfs");
        setDefaultEnv("QT_QPA_EGLFS_INTEGRATION", "eglfs_kms");
        setDefaultEnv("QT_QPA_EGLFS_KMS_ATOMIC", "1");
        setDefaultEnv("QT_QPA_EGLFS_HIDECURSOR", "1");
        setDefaultEnv("QT_IM_MODULE", "qtvirtualkeyboard");
        setDefaultEnv("XDG_RUNTIME_DIR", QFile::encodeName(Paths::displayDir()));
        const QString scale = Properties::get(QStringLiteral("ro.astra.ui.scale"));
        if (!scale.isEmpty())
            setDefaultEnv("QT_SCALE_FACTOR", scale.toLatin1());
    }
    setDefaultEnv("QT_WAYLAND_COMPOSITOR_NO_THROTTLE", "0");
    setDefaultEnv("QT_QUICK_CONTROLS_STYLE", "Basic");

    // The boot animation owns the display until we are about to show.
    SysBoardHost::stopBootAnimation();

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("SysBoard"));
    QGuiApplication::setDesktopFileName(QStringLiteral("sysboard"));

    const QDir fonts(Paths::fonts());
    for (const QString &f : fonts.entryList({QStringLiteral("*.ttf")}, QDir::Files))
        QFontDatabase::addApplicationFont(fonts.filePath(f));
    QGuiApplication::setFont(QFont(QStringLiteral("Poppins")));

    SysBoardHost::instance();
    QQmlApplicationEngine engine;
    engine.addImportPath(Paths::frameworkQml());
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("SysBoard", "Main");
    return app.exec();
}
