// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — chaos-informed channel selection shim
 *
 * Uses the Rössler attractor's channel outputs (from the ChaosParams snapshot)
 * to select an 802.11 operating channel via cfg80211.
 *
 * Channel selection strategy:
 *
 *   The Rössler attractor provides:
 *     - channel_24ghz: IEEE 802.11 2.4 GHz channel number [1, 14]
 *     - channel_5ghz:  IEEE 802.11 5 GHz channel number (36–165, step 4)
 *
 *   Band selection is controlled by prefer_5ghz. When true, the 5 GHz
 *   Rössler output is used; when false, the 2.4 GHz output.
 *
 *   The Lyapunov exponent gates channel changes:
 *     - High λ₁ (> 1.0): allow frequent channel hops (high chaos → high uncertainty)
 *     - Low λ₁ (< 0.5):  suppress hops (attractor approaching periodic orbit)
 *
 *   This means the driver is more willing to hop channels when the RF
 *   environment itself is highly chaotic (many conflicting signals), and
 *   more conservative when the environment is stable.
 */

#include <linux/kernel.h>
#include <linux/types.h>
#include <net/cfg80211.h>
#include "iwchaos_shim.h"

/*
 * iwchaos_channel_select - select an 802.11 channel via the Rössler attractor
 *
 * @wiphy:       kernel wireless PHY handle
 * @cp:          chaos parameter snapshot (from iwchaos_update_all)
 * @prefer_5ghz: if true, select 5 GHz channel; otherwise 2.4 GHz
 *
 * Returns 0 on success, -EINVAL if the channel is not available on this PHY,
 * -EPERM if the Lyapunov exponent is too low to justify a channel hop.
 *
 * The caller (mac80211 scan / connect path) must hold the wiphy mutex.
 */
int iwchaos_channel_select(struct wiphy *wiphy,
                            const struct iwchaos_chaos_params *cp,
                            bool prefer_5ghz)
{
    struct ieee80211_channel *chan;
    int freq_mhz;
    u32 ch_num;

    if (!wiphy || !cp)
        return -EINVAL;

    /*
     * Lyapunov gate: suppress channel hop when the chaos engine is in a
     * near-periodic state (λ₁ < 0.5). This prevents spurious channel changes
     * during transient dynamics at driver startup.
     */
    if (cp->lyapunov_est < 0.5 && cp->lyapunov_est > 0.0)
        return -EPERM;

    if (prefer_5ghz) {
        /*
         * 5 GHz: channel_5ghz holds the actual channel number (e.g. 36, 40, …)
         * IEEE 5 GHz frequency formula: freq = 5000 + channel * 5  (MHz)
         */
        ch_num   = cp->channel_5ghz;
        freq_mhz = 5000 + (int)ch_num * 5;
    } else {
        /*
         * 2.4 GHz: channel_24ghz holds the channel number [1, 14]
         * IEEE 2.4 GHz frequency formula: freq = 2407 + channel * 5  (MHz)
         * Exception: channel 14 is at 2484 MHz (Japan only).
         */
        ch_num   = cp->channel_24ghz;
        if (ch_num == 14)
            freq_mhz = 2484;
        else
            freq_mhz = 2407 + (int)ch_num * 5;
    }

    chan = ieee80211_get_channel(wiphy, freq_mhz);
    if (!chan) {
        /* Channel not available on this PHY — not a driver error. */
        return -EINVAL;
    }

    if (chan->flags & IEEE80211_CHAN_DISABLED)
        return -EINVAL;

    /*
     * Channel validated. The actual switch is performed by the mac80211
     * scan or connect path using ieee80211_request_channel_switch().
     * We return 0 to indicate the chaos engine has approved this frequency.
     */
    return 0;
}
