/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Force-included after kconfig.h so out-of-tree builds do not depend on
 * in-tree iwlwifi tracepoint exports. Device tracing stays available via
 * vendor/iwlwifi/iwl-devtrace.c linked into this module.
 *
 * If you prefer stubs instead of embedding tracepoints, define
 * IWCHAOS_STUB_DEV_TRACING=1 on the make command line.
 */
#ifdef IWCHAOS_STUB_DEV_TRACING
#undef CONFIG_IWLWIFI_DEVICE_TRACING
#endif
