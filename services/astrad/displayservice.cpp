// SPDX-License-Identifier: Apache-2.0
#include "displayservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QFile>
#include <QJsonDocument>
#include <QSaveFile>
#include <QSet>

#include <fcntl.h>
#include <unistd.h>

#if ASTRA_HAVE_LIBDRM
#include <xf86drm.h>
#include <xf86drmMode.h>
#endif

namespace astrad {

using namespace astra;

DisplayService::DisplayService(SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_settings(settings)
{
    probe();
    writeKmsConfig();
    connect(settings, &SettingsService::changed, this, [this](const QString &key) {
        if (key == QLatin1String("display.mode"))
            writeKmsConfig();
    });
}

void DisplayService::writeKmsConfig()
{
    const QString path = Paths::dataSystem() + QStringLiteral("/kms.json");
    const QString mode = m_settings->value(QStringLiteral("display.mode")).toString();
    const QString output = m_info.value(QLatin1String("output")).toString();
    if (mode.isEmpty() || output.isEmpty()) {
        QFile::remove(path);
        return;
    }
    const QJsonObject config{
        {QStringLiteral("hwcursor"), false},
        {QStringLiteral("outputs"), QJsonArray{QJsonObject{{QStringLiteral("name"), output}, {QStringLiteral("mode"), mode}}}},
    };
    QSaveFile f(path);
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(config).toJson());
        f.commit();
    }
}

void DisplayService::probe()
{
    m_modes = {};
    m_info = {};
#if ASTRA_HAVE_LIBDRM
    for (int card = 0; card < 4 && m_modes.isEmpty(); ++card) {
        const QByteArray path = "/dev/dri/card" + QByteArray::number(card);
        const int fd = ::open(path.constData(), O_RDONLY | O_CLOEXEC);
        if (fd < 0)
            continue;
        drmModeRes *res = drmModeGetResources(fd);
        for (int i = 0; res && i < res->count_connectors && m_modes.isEmpty(); ++i) {
            drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[i]);
            if (!conn)
                continue;
            if (conn->connection == DRM_MODE_CONNECTED && conn->count_modes > 0) {
                QSet<QString> seen;
                drmModeEncoder *enc = conn->encoder_id ? drmModeGetEncoder(fd, conn->encoder_id) : nullptr;
                drmModeCrtc *crtc = enc && enc->crtc_id ? drmModeGetCrtc(fd, enc->crtc_id) : nullptr;
                for (int m = 0; m < conn->count_modes; ++m) {
                    const drmModeModeInfo &mode = conn->modes[m];
                    const QString key = QStringLiteral("%1x%2@%3").arg(mode.hdisplay).arg(mode.vdisplay).arg(mode.vrefresh);
                    if (seen.contains(key))
                        continue;
                    seen.insert(key);
                    const bool current = crtc && crtc->mode_valid && crtc->mode.hdisplay == mode.hdisplay &&
                                         crtc->mode.vdisplay == mode.vdisplay && crtc->mode.vrefresh == mode.vrefresh;
                    m_modes.append(QJsonObject{{QStringLiteral("width"), int(mode.hdisplay)},
                                               {QStringLiteral("height"), int(mode.vdisplay)},
                                               {QStringLiteral("refresh"), int(mode.vrefresh)},
                                               {QStringLiteral("preferred"), bool(mode.type & DRM_MODE_TYPE_PREFERRED)},
                                               {QStringLiteral("current"), current}});
                }
                // Qt names outputs <type><type id>, e.g. "DSI1".
                const QString type = QString::fromLatin1(drmModeGetConnectorTypeName(conn->connector_type));
                m_info = {{QStringLiteral("connector"), type},
                          {QStringLiteral("output"), type + QString::number(conn->connector_type_id)},
                          {QStringLiteral("physicalWidth"), int(conn->mmWidth)},
                          {QStringLiteral("physicalHeight"), int(conn->mmHeight)},
                          };
                drmModeFreeCrtc(crtc);
                drmModeFreeEncoder(enc);
            }
            drmModeFreeConnector(conn);
        }
        drmModeFreeResources(res);
        ::close(fd);
    }
#endif
    for (const QJsonValue &v : std::as_const(m_modes))
        if (v.toObject().value(QLatin1String("current")).toBool() || v.toObject().value(QLatin1String("preferred")).toBool()) {
            m_info.insert(QStringLiteral("width"), v.toObject().value(QLatin1String("width")));
            m_info.insert(QStringLiteral("height"), v.toObject().value(QLatin1String("height")));
            m_info.insert(QStringLiteral("refresh"), v.toObject().value(QLatin1String("refresh")));
        }
}

QJsonValue DisplayService::handle(const QString &call, const QJsonObject &, const Caller &)
{
    if (call == QLatin1String("modes")) {
        probe();
        return m_modes;
    }
    if (call == QLatin1String("info")) {
        QJsonObject info = m_info;
        info.insert(QStringLiteral("modes"), m_modes);
        return info;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
