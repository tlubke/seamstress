#pragma once

#if __APPLE__
#include "device_monitor_macos.h"
#else
#include "device_monitor_linux.h"
#endif
