// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

class QSocketNotifier;

namespace astrad {

// The shell behind the Terminal app of astraOS Desktop: a pseudo terminal with the user's shell on it, run as that user
// (the one that owns the home directory), not as the app's sandbox uid. The app draws the terminal (a VT100/xterm
// emulator, Astra.Desktop's TerminalView) and speaks to this service.
//
//   terminal.open {cols, rows}   -> {id}
//   terminal.write {id, data}       data in base64
//   terminal.resize {id, cols, rows}
//   terminal.close {id}
// Events (to the apps that hold astra.permission.TERMINAL): "terminal.data" {id, data (base64)}, "terminal.exit" {id}.
class TerminalService : public Service
{
    Q_OBJECT
public:
    TerminalService(Server *server, QObject *parent = nullptr);
    ~TerminalService() override;
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    struct Session {
        int id = 0;
        int fd = -1;
        pid_t pid = 0;
        QString owner;                 // the package that opened it
        QSocketNotifier *notifier = nullptr;
    };
    void closeSession(int id, bool kill);

    Server *m_server;
    QHash<int, Session> m_sessions;
    int m_next = 1;
};

} // namespace astrad
