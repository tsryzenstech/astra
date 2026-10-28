// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>
#include <QJsonArray>

#include <functional>

namespace astrad {

class PackageManager;

// System dialogs: the bottom sheets SysBoard shows above everything
// (permission prompts, USB debugging authorization, app confirmations).
//
//   dialogs.show {title, message, icon?, buttons: [{id, label, style}]}
//       -> resolves with the id of the button the user pressed
//   dialogs.answer {id, button}   (SysBoard)
//   dialogs.pending               (SysBoard, after a restart)
class DialogService : public Service
{
    Q_OBJECT
public:
    using Callback = std::function<void(const QString &button)>;

    DialogService(Server *server, PackageManager *packages, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    // Shows a dialog on behalf of a package ("" for the system). The
    // callback receives the pressed button, or cancelButton if nobody can
    // show the dialog or it is dismissed.
    int show(const QString &package, const QJsonObject &content, const QString &cancelButton, Callback callback);

private:
    struct Pending {
        QJsonObject dialog;
        QString cancelButton;
        Callback callback;
    };
    void finish(int id, const QString &button);

    Server *m_server;
    PackageManager *m_packages;
    QHash<int, Pending> m_pending;
    QList<int> m_order;
    int m_nextId = 1;
};

} // namespace astrad
