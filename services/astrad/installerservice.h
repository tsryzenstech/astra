// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonObject>
#include <QPointer>

class QProcess;

namespace astrad {

// The disks of the machine and the installation of astraOS Desktop: what the Installer and Disk Utility of the
// recovery environment (the live ISO, docs/DESKTOP.md) use. Only there: the service refuses everything but
// `state` on an installed system, where nothing may erase a disk, and when a disk holds the running live medium.
//
//   installer.state                       -> {live, installing, disks: [...]}
//   installer.disks                       -> [{path, name, model, size, removable, partitionTable, live, partitions: [{path, name,
//                                              size, fstype, label, mountpoint}], free: bytes}]
//   installer.erase {path, format, label}     format a partition (ext4, fat32, exfat, ntfs, swap), or a whole disk (a new GPT
//                                              with one partition of that format)
//   installer.createPartition {disk, size, format, label}   in the free space; size in bytes, 0 for all of it
//   installer.deletePartition {path}
//   installer.mount {path} -> {mountpoint}     installer.unmount {path}
//   installer.install {disk | root, esp?, user?, hostname?}    runs /usr/lib/astra/installer/install.sh; events "installer.progress"
//                                              {percent, text}, "installer.finished", "installer.error" {message}
//   installer.cancel
// Needs astra.permission.MANAGE_DISKS (privileged: the Installer and Disk Utility of the system).
class InstallerService : public Service
{
    Q_OBJECT
public:
    InstallerService(Server *server, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    bool live() const;

private:
    QJsonArray disks() const;
    bool knownDevice(const QString &path) const;
    static bool validPath(const QString &path);
    void runShell(const QString &script, const PendingReply &pending, const QJsonValue &result);
    QJsonObject state() const;

    Server *m_server;
    QPointer<QProcess> m_install;
};

} // namespace astrad
