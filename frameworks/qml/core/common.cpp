// SPDX-License-Identifier: Apache-2.0
#include "common.h"

#include <QQmlEngine>

namespace astra::qml {

void invokeCallback(QObject *context, const QJSValue &callback, const QJsonValue &result, const QString &error)
{
    if (!callback.isCallable())
        return;
    QJSEngine *engine = qjsEngine(context);
    if (!engine)
        return;
    QJSValue cb = callback;
    const QJSValue r = engine->toScriptValue(result.toVariant());
    const QJSValue out = cb.call({r, error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error)});
    if (out.isError())
        qWarning("astra: callback error: %s", qPrintable(out.toString()));
}

} // namespace astra::qml
