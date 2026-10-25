// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "global.h"

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QString>

namespace astra {

// Reader for astraOS application packages (.apkg). See docs/APKG.md.
class ASTRA_EXPORT Apkg
{
public:
    struct Entry {
        QString path;
        quint8 compression = 0;
        quint32 mode = 0644;
        quint64 offset = 0;
        quint64 storedSize = 0;
        quint64 size = 0;
        QByteArray sha256;
    };

    bool open(const QString &fileName);
    bool verify();
    bool extractTo(const QString &directory);

    QByteArray read(const Entry &entry);
    const QJsonObject &manifest() const { return m_manifest; }
    const QList<Entry> &entries() const { return m_entries; }
    QByteArray checksum() const; // sha256 of the whole package body
    QString errorString() const { return m_error; }

    // Validates the manifest fields every installed package must have.
    static bool validateManifest(const QJsonObject &manifest, QString *error);

private:
    bool fail(const QString &error);

    QByteArray m_blob;
    QJsonObject m_manifest;
    QList<Entry> m_entries;
    quint64 m_dataOffset = 0;
    QString m_error;
};

} // namespace astra
