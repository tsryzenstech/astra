// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QFileInfo>
#include <QObject>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// File operations for apps (singleton "Files"), limited to the shared
// storage (/data/media/0, needs the MEDIA permission) and the app's own
// data directory. Paths are absolute.
//
//   Files.list(Files.home)  -> [{ name, path, url, dir, size, modified, mime, hidden }]
//   Files.copy([a, b], dir) / Files.move(...) / Files.remove([...]) / Files.mkdir(dir, "New")
class FileSystem : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Files)
    QML_SINGLETON

    Q_PROPERTY(QString home READ home CONSTANT)          // shared storage root
    Q_PROPERTY(QString appData READ appData CONSTANT)

public:
    explicit FileSystem(QObject *parent = nullptr);
    QString home() const;
    QString appData() const;

    Q_INVOKABLE bool allowed(const QString &path) const;
    Q_INVOKABLE QVariantList list(const QString &dir, bool showHidden = false) const;
    Q_INVOKABLE QVariantMap info(const QString &path) const;
    Q_INVOKABLE QVariantList search(const QString &root, const QString &query, int limit = 200) const;
    Q_INVOKABLE QVariantList recent(int limit = 40) const;
    Q_INVOKABLE QString mkdir(const QString &dir, const QString &name);   // returns the new path or ""
    Q_INVOKABLE QString rename(const QString &path, const QString &name);
    Q_INVOKABLE int remove(const QVariantList &paths);                  // returns how many were removed
    Q_INVOKABLE int copy(const QVariantList &paths, const QString &dir);
    Q_INVOKABLE int move(const QVariantList &paths, const QString &dir);
    Q_INVOKABLE QString readText(const QString &path, int maxBytes = 262144) const;
    Q_INVOKABLE bool writeText(const QString &path, const QString &text);
    Q_INVOKABLE QString mimeType(const QString &path) const;
    Q_INVOKABLE QVariantMap usage() const;                               // { total, free } of the storage

Q_SIGNALS:
    void changed(const QString &dir);

private:
    QVariantMap entry(const QFileInfo &f) const;
    QString uniqueName(const QString &dir, const QString &name) const;
};

} // namespace astra::qml
