// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — channel selection ABI stub (logic in Rust)
 */

#include <net/cfg80211.h>
#include "iwchaos_shim.h"

int iwchaos_channel_select(void *rust_ctx, struct wiphy *wiphy, bool prefer_5ghz)
{
	return iwchaos_channel_select_rust(rust_ctx, wiphy, prefer_5ghz);
}
