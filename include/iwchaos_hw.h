/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * iwchaos — MMIO / DMA ABI (C-only kernel primitives)
 */

#ifndef IWCHAOS_HW_H
#define IWCHAOS_HW_H

#include <linux/types.h>
#include <linux/skbuff.h>
#include <net/mac80211.h>

struct device;

int  iwchaos_hw_reset(void __iomem *mmio);
int  iwchaos_hw_load_image(void __iomem *mmio, const u8 *fw, size_t len);
int  iwchaos_hw_set_channel(void __iomem *mmio, u32 freq_mhz);
int  iwchaos_hw_tx_submit(struct device *dev, void __iomem *mmio,
			  struct sk_buff *skb, u32 doorbell);
void iwchaos_hw_rx_poll(void __iomem *mmio);

void iwchaos_scan_done(struct ieee80211_hw *hw, bool aborted);

#endif /* IWCHAOS_HW_H */
