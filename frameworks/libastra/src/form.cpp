// SPDX-License-Identifier: Apache-2.0
#include "astra/form.h"
#include "astra/properties.h"

namespace astra {

QString Form::current()
{
    static const QString form = [] {
        QString f = qEnvironmentVariable("ASTRA_FORM");
        if (f.isEmpty())
            f = Properties::get(QStringLiteral("ro.astra.form"), QStringLiteral("phone"));
        return f.trimmed().toLower() == QLatin1String("desktop") ? QStringLiteral("desktop") : QStringLiteral("phone");
    }();
    return form;
}

bool Form::isDesktop()
{
    return current() == QLatin1String("desktop");
}

QString Form::normalizeTarget(const QString &target)
{
    return target == QLatin1String("desktop") ? QStringLiteral("desktop") : QStringLiteral("mobile");
}

bool Form::runsHere(const QString &target)
{
    return normalizeTarget(target) == QLatin1String("mobile") || isDesktop();
}

} // namespace astra
