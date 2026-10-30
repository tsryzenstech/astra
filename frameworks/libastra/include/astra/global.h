// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QtCore/qglobal.h>

#if defined(ASTRA_BUILD_LIBRARY)
#define ASTRA_EXPORT Q_DECL_EXPORT
#else
#define ASTRA_EXPORT Q_DECL_IMPORT
#endif

namespace astra {

// Well known user ids (Android compatible numbering).
constexpr uint AID_ROOT = 0;
constexpr uint AID_SYSTEM = 1000;
constexpr uint AID_GRAPHICS = 1003;
constexpr uint AID_INPUT = 1004;
constexpr uint AID_AUDIO = 1005;
constexpr uint AID_INET = 3003;
constexpr uint AID_VIDEO = 1040;
constexpr uint AID_APP_START = 20000; // 10000 is the postmarketOS user

ASTRA_EXPORT const char *version();

} // namespace astra
