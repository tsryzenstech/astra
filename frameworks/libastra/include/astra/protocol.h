// SPDX-License-Identifier: Apache-2.0
#pragma once

// astra IPC protocol (see docs/IPC.md)
//
// Transport: Unix stream socket /dev/socket/astrad, one compact JSON object
// per line.
//
//   request : {"id": 7, "method": "notifications.post", "params": {...}}
//   reply   : {"id": 7, "result": ...}
//             {"id": 7, "error": {"code": -32001, "message": "..."}}
//   event   : {"event": "notifications.posted", "data": ...}
//
// Clients receive events of the topics they subscribed to through
// "system.subscribe" {"topics": ["notifications", "media", ...]}.
// The caller identity (uid/pid) is taken from SO_PEERCRED, never from
// the payload.

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace astra::protocol {

enum ErrorCode {
    Failed = -32000,
    PermissionDenied = -32001,
    NotFound = -32004,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
};

inline QByteArray encode(const QJsonObject &message)
{
    return QJsonDocument(message).toJson(QJsonDocument::Compact) + '\n';
}

} // namespace astra::protocol
