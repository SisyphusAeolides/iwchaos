// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — cfg80211 ABI shim
 */

#include <linux/kernel.h>
#include <net/cfg80211.h>
#include "iwchaos_shim.h"

static struct cfg80211_ops iwchaos_cfg_ops = {
    .scan            = (void *)iwchaos_cfg_scan,
    .connect         = (void *)iwchaos_cfg_connect,
    .disconnect      = (void *)iwchaos_cfg_disconnect,
};

struct cfg80211_ops *iwchaos_get_cfg80211_ops(void)
{
    return &iwchaos_cfg_ops;
}
