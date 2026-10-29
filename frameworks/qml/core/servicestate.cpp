// SPDX-License-Identifier: Apache-2.0
#include "servicestate.h"
#include "common.h"

#include <astra/client.h>
#include <astra/localization.h>
#include <astra/paths.h>

#include <QDir>
#include <QFontDatabase>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>

namespace astra::qml {

static QJsonObject toJson(const QVariantMap &m)
{
    return QJsonObject::fromVariantMap(m);
}

namespace {
QList<ServiceState *> &allStates()
{
    static QList<ServiceState *> list;
    return list;
}
}

ServiceState::ServiceState(const QString &service, const QString &stateMethod, const QString &stateEvent, QObject *parent)
    : QObject(parent)
    , m_service(service)
    , m_stateMethod(stateMethod)
    , m_stateEvent(stateEvent)
{
    allStates().append(this);
    Client *c = Client::instance();
    c->subscribe({service});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (!name.startsWith(m_service + QLatin1Char('.')))
            return;
        onEvent(name, data);
        ++m_revision;
        Q_EMIT revisionChanged();
        Q_EMIT event(name.mid(m_service.size() + 1), data.toVariant());
    });
    // Subclasses are not constructed yet: defer the virtual reload().
    QTimer::singleShot(0, this, [this] {
        if (Client::instance()->isConnected())
            reload();
    });
}

ServiceState::~ServiceState()
{
    allStates().removeOne(this);
}

void ServiceState::reloadAll()
{
    for (ServiceState *state : std::as_const(allStates()))
        state->reload();
}

void ServiceState::call(const QString &method, const QVariantMap &params, const QJSValue &callback)
{
    Client::instance()->call(m_service + QLatin1Char('.') + method, toJson(params),
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void ServiceState::reload()
{
    if (m_stateMethod.isEmpty())
        return;
    Client::instance()->call(m_service + QLatin1Char('.') + m_stateMethod, {}, [this](const QJsonValue &r, const QString &) {
        if (r.isObject())
            setState(r.toObject().toVariantMap());
    });
}

void ServiceState::onEvent(const QString &name, const QJsonValue &data)
{
    if (!m_stateEvent.isEmpty() && name == m_stateEvent && data.isObject())
        setState(data.toObject().toVariantMap());
}

void ServiceState::setState(const QVariantMap &state)
{
    m_state = state;
    m_ready = true;
    Q_EMIT stateChanged();
}

// Fetches one method's result into state[key].
void ServiceState::fetch(const QString &method, const QString &key)
{
    Client::instance()->call(m_service + QLatin1Char('.') + method, {}, [this, key](const QJsonValue &r, const QString &) {
        QVariantMap s = state();
        s.insert(key, r.toVariant());
        setState(s);
    });
}

NetworkState::NetworkState(QObject *parent)
    : ServiceState(QStringLiteral("network"), QStringLiteral("state"), QStringLiteral("network.changed"), parent)
{
}

LocationState::LocationState(QObject *parent)
    : ServiceState(QStringLiteral("location"), QStringLiteral("state"), QStringLiteral("location.changed"), parent)
{
}

void LocationState::onEvent(const QString &name, const QJsonValue &data)
{
    Q_UNUSED(name)
    QVariantMap s = state();
    s.insert(QStringLiteral("fix"), data.toObject().toVariantMap());
    s.insert(QStringLiteral("enabled"), true);
    setState(s);
}

CalendarState::CalendarState(QObject *parent)
    : ServiceState(QStringLiteral("calendar"), {}, {}, parent)
{
}

AccountState::AccountState(QObject *parent)
    : ServiceState(QStringLiteral("account"), QStringLiteral("state"), QStringLiteral("account.changed"), parent)
{
}

CloudyState::CloudyState(QObject *parent)
    : ServiceState(QStringLiteral("cloudy"), QStringLiteral("state"), QStringLiteral("cloudy.changed"), parent)
{
}

TelephonyState::TelephonyState(QObject *parent)
    : ServiceState(QStringLiteral("telephony"), {}, {}, parent)
{
}

void TelephonyState::reload()
{
    fetch(QStringLiteral("calls"), QStringLiteral("calls"));
}

void TelephonyState::onEvent(const QString &name, const QJsonValue &data)
{
    if (name == QLatin1String("telephony.calls")) {
        QVariantMap s = state();
        s.insert(QStringLiteral("calls"), data.toVariant());
        setState(s);
    } else if (name == QLatin1String("telephony.incoming")) {
        Q_EMIT incoming(data.toObject().toVariantMap());
    } else if (name == QLatin1String("telephony.message")) {
        Q_EMIT message(data.toObject().toVariantMap());
    }
}

ContactsState::ContactsState(QObject *parent)
    : ServiceState(QStringLiteral("contacts"), {}, {}, parent)
{
    connect(this, &ServiceState::revisionChanged, this, &ContactsState::reload);
}

void ContactsState::reload()
{
    fetch(QStringLiteral("list"), QStringLiteral("contacts"));
}

AlarmsState::AlarmsState(QObject *parent)
    : ServiceState(QStringLiteral("alarms"), {}, {}, parent)
{
}

void AlarmsState::reload()
{
    Client *c = Client::instance();
    c->call(QStringLiteral("alarms.list"), {}, [this](const QJsonValue &alarms, const QString &) {
        Client::instance()->call(QStringLiteral("alarms.timers"), {}, [this, alarms](const QJsonValue &timers, const QString &) {
            Client::instance()->call(QStringLiteral("alarms.next"), {}, [this, alarms, timers](const QJsonValue &next, const QString &) {
                QVariantMap s = state();
                s.insert(QStringLiteral("alarms"), alarms.toVariant());
                s.insert(QStringLiteral("timers"), timers.toVariant());
                s.insert(QStringLiteral("next"), next.toVariant());
                setState(s);
            });
        });
    });
    fetch(QStringLiteral("ringing"), QStringLiteral("ringing"));
}

void AlarmsState::onEvent(const QString &name, const QJsonValue &data)
{
    QVariantMap s = state();
    if (name == QLatin1String("alarms.changed")) {
        const QVariantMap d = data.toObject().toVariantMap();
        for (auto it = d.cbegin(); it != d.cend(); ++it)
            s.insert(it.key(), it.value());
    } else if (name == QLatin1String("alarms.fired")) {
        s.insert(QStringLiteral("ringing"), data.toVariant());
    } else if (name == QLatin1String("alarms.stopped")) {
        s.insert(QStringLiteral("ringing"), QVariant());
    } else {
        return;
    }
    setState(s);
}

DisplayState::DisplayState(QObject *parent)
    : ServiceState(QStringLiteral("display"), QStringLiteral("info"), QStringLiteral("display.changed"), parent)
{
}

UpdateState::UpdateState(QObject *parent)
    : ServiceState(QStringLiteral("update"), QStringLiteral("info"), QStringLiteral("update.changed"), parent)
{
}

DeveloperState::DeveloperState(QObject *parent)
    : ServiceState(QStringLiteral("developer"), QStringLiteral("state"), QStringLiteral("developer.changed"), parent)
{
}

// ---------------------------------------------------------------------------

PermissionsState::PermissionsState(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("packages")});
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &) {
        if (name.startsWith(QLatin1String("packages."))) {
            ++m_revision;
            Q_EMIT changed();
        }
    });
}

void PermissionsState::check(const QString &permission, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.checkPermission"), {{QStringLiteral("permission"), permission}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r.toBool(), e); });
}

void PermissionsState::request(const QString &permission, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.requestPermission"), {{QStringLiteral("permission"), permission}},
                             [this, callback](const QJsonValue &r, const QString &e) {
        const QJsonObject o = r.toObject();
        const bool granted = r.isBool() ? r.toBool() : o.value(QLatin1String("granted")).toBool();
        // astrad gives a running app the access of a new permission group
        // (ACLs), so the app keeps running; what the app couldn't read
        // before is fetched again.
        if (granted)
            ServiceState::reloadAll();
        invokeCallback(this, callback, granted, e);
    });
}

void PermissionsState::catalog(const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.permissionCatalog"), {},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void PermissionsState::forPackage(const QString &package, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.permissions"), {{QStringLiteral("package"), package}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void PermissionsState::apps(const QString &permission, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.permissionApps"), {{QStringLiteral("permission"), permission}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void PermissionsState::set(const QString &package, const QString &permission, const QString &state, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.setPermission"),
                             {{QStringLiteral("package"), package}, {QStringLiteral("permission"), permission},
                              {QStringLiteral("state"), state}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

// ---------------------------------------------------------------------------

DialogsState::DialogsState(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("dialogs")});
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("dialogs.show"))
            Q_EMIT shown(data.toObject().toVariantMap());
        else if (name == QLatin1String("dialogs.closed"))
            Q_EMIT closed(data.toObject().value(QLatin1String("id")).toInt());
    });
}

void DialogsState::show(const QVariantMap &dialog, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("dialogs.show"), toJson(dialog),
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void DialogsState::answer(int id, const QString &button)
{
    Client::instance()->call(QStringLiteral("dialogs.answer"), {{QStringLiteral("id"), id}, {QStringLiteral("button"), button}});
}

void DialogsState::pending(const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("dialogs.pending"), {},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

// ---------------------------------------------------------------------------

LanguageState::LanguageState(QObject *parent)
    : QObject(parent)
{
    connect(Localization::instance(), &Localization::languageChanged, this, &LanguageState::changed);
}

QString LanguageState::current() const
{
    return Localization::instance()->language();
}

QVariantList LanguageState::available() const
{
    QVariantList out;
    for (const Localization::Language &l : Localization::available())
        out.append(QVariantMap{{QStringLiteral("code"), l.code}, {QStringLiteral("name"), l.name},
                               {QStringLiteral("english"), l.english}});
    return out;
}

void LanguageState::set(const QString &code)
{
    Client::instance()->call(QStringLiteral("settings.set"), {{QStringLiteral("key"), QStringLiteral("system.language")},
                                                              {QStringLiteral("value"), code}});
}

QString LanguageState::nameOf(const QString &code) const
{
    for (const Localization::Language &l : Localization::available())
        if (l.code == code)
            return l.name;
    return code;
}

// ---------------------------------------------------------------------------

FontsState::FontsState(QObject *parent)
    : QObject(parent)
{
    const QDir dir(Paths::fonts());
    for (const QString &f : dir.entryList({QStringLiteral("*.ttf"), QStringLiteral("*.otf")}, QDir::Files)) {
        const int id = QFontDatabase::addApplicationFont(dir.filePath(f)); // already loaded: returns the same id
        for (const QString &family : QFontDatabase::applicationFontFamilies(id))
            if (!family.startsWith(QLatin1String("Poppins")) && !family.contains(QLatin1String("emoji"), Qt::CaseInsensitive)
                && !m_families.contains(family))
                m_families.append(family);
    }
    m_families.sort(Qt::CaseInsensitive);
}

} // namespace astra::qml
