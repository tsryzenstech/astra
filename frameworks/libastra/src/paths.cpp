// SPDX-License-Identifier: Apache-2.0
#include "astra/paths.h"

#include <QDir>

namespace astra {

const char *version()
{
    return ASTRA_VERSION;
}

QString Paths::root()
{
    static const QString root = [] {
        QString r = qEnvironmentVariable("ASTRA_ROOT");
        if (r.isEmpty())
            return QString();
        return QDir(r).absolutePath();
    }();
    return root;
}

QString Paths::resolve(const QString &absolutePath)
{
    return root().isEmpty() ? absolutePath : root() + absolutePath;
}

bool Paths::isDevelopmentRoot()
{
    return !root().isEmpty();
}

} // namespace astra
