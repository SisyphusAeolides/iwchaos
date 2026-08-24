// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — cfg80211 ABI shim
 */

#include <linux/kernel.h>
#include <net/cfg80211.h>
#include "iwchaos_shim.h"

/*
 * cfg80211 op: initiate a scan.
 */
int iwchaos_cfg_scan(struct wiphy *wiphy,
                     struct cfg80211_scan_request *request)
{
    return -EOPNOTSUPP;
}

/*
 * cfg80211 op: connect to an AP.
 */
int iwchaos_cfg_connect(struct wiphy *wiphy, struct net_device *dev,
                        struct cfg80211_connect_params *sme)
{
    return -EOPNOTSUPP;
}

/*
 * cfg80211 op: disconnect from an AP.
 */
int iwchaos_cfg_disconnect(struct wiphy *wiphy, struct net_device *dev,
                           u16 reason_code)
{
    return -EOPNOTSUPP;
}

static struct cfg80211_ops iwchaos_cfg_ops = {
    .scan       = iwchaos_cfg_scan,
    .connect    = iwchaos_cfg_connect,
    .disconnect = iwchaos_cfg_disconnect,
};

struct cfg80211_ops *iwchaos_get_cfg80211_ops(void)
{
    return &iwchaos_cfg_ops;
}
