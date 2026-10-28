// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <astra/paths.h>

#include <QByteArray>
#include <QFile>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace astrad {

// Sends a request to init's control socket: "start <svc>", "stop <svc>",
// "restart <svc>", "reboot [bootloader|recovery]", "poweroff".
inline bool sendToInit(const QByteArray &command)
{
    const int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
    if (fd < 0)
        return false;
    sockaddr_un addr {};
    addr.sun_family = AF_UNIX;
    const QByteArray path = QFile::encodeName(astra::Paths::initSocket());
    qstrncpy(addr.sun_path, path.constData(), sizeof(addr.sun_path));
    const bool ok = sendto(fd, command.constData(), size_t(command.size()), 0,
                           reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) == command.size();
    close(fd);
    return ok;
}

} // namespace astrad
