// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — MMIO / DMA helpers (C-only: ioremap accessors, SKB DMA)
 *
 * All chaos-driven decisions live in Rust. This file performs the minimum
 * hardware plumbing the Rust core cannot do without unstable kernel bindings.
 */

#include <linux/delay.h>
#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/pci.h>
#include <linux/skbuff.h>
#include <net/mac80211.h>
#include "iwchaos_hw.h"

/* Intel CSR offsets (AX200 / 22000 family) */
#define CSR_RESET		0x020
#define CSR_GP_CNTRL		0x024
#define CSR_HW_REV		0x028
#define CSR_GP_DRIVER_REG	0x050
#define CSR_INT			0x008

#define CSR_RESET_REG_FLAG_SW_RESET	BIT(25)
#define CSR_GP_CNTRL_REG_FLAG_MAC_ACCESS_REQ	BIT(0)
#define CSR_GP_CNTRL_REG_VAL_MAC_ACCESS_EN	BIT(1)

static u32 iwchaos_readl(void __iomem *mmio, u32 off)
{
	return ioread32(mmio + off);
}

static void iwchaos_writel(void __iomem *mmio, u32 off, u32 val)
{
	iowrite32(val, mmio + off);
}

int iwchaos_hw_reset(void __iomem *mmio)
{
	u32 gp;

	if (!mmio)
		return -EINVAL;

	gp = iwchaos_readl(mmio, CSR_GP_CNTRL);
	iwchaos_writel(mmio, CSR_GP_CNTRL,
		       gp | CSR_GP_CNTRL_REG_FLAG_MAC_ACCESS_REQ);
	msleep(20);
	iwchaos_writel(mmio, CSR_GP_CNTRL,
		       gp | CSR_GP_CNTRL_REG_FLAG_MAC_ACCESS_REQ |
		       CSR_GP_CNTRL_REG_VAL_MAC_ACCESS_EN);
	msleep(20);

	iwchaos_writel(mmio, CSR_RESET, CSR_RESET_REG_FLAG_SW_RESET);
	msleep(20);
	iwchaos_writel(mmio, CSR_RESET, 0);
	msleep(20);

	return 0;
}

int iwchaos_hw_load_image(void __iomem *mmio, const u8 *fw, size_t len)
{
	if (!mmio || !fw || !len)
		return -EINVAL;

	/* Publish firmware byte count — Rust FSM transitions on this write */
	iwchaos_writel(mmio, CSR_GP_DRIVER_REG, (u32)len);
	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 4, (u32)(len >> 32));

	pr_info("iwchaos: firmware image staged (%zu bytes, HW rev 0x%08x)\n",
		len, iwchaos_readl(mmio, CSR_HW_REV));
	return 0;
}

int iwchaos_hw_set_channel(void __iomem *mmio, u32 freq_mhz)
{
	if (!mmio)
		return -EINVAL;

	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 8, freq_mhz);
	return 0;
}

int iwchaos_hw_tx_submit(struct device *dev, void __iomem *mmio,
			 struct sk_buff *skb, u32 doorbell)
{
	dma_addr_t dma;

	if (!dev || !mmio || !skb)
		return -EINVAL;

	dma = dma_map_single(dev, skb->data, skb->len, DMA_TO_DEVICE);
	if (dma_mapping_error(dev, dma))
		return -EIO;

	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 12, lower_32_bits(dma));
	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 16, upper_32_bits(dma));
	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 20, skb->len);
	iwchaos_writel(mmio, CSR_GP_DRIVER_REG + 24, doorbell);

	/* Doorbell: kick host→device TX notification */
	iwchaos_writel(mmio, CSR_INT, BIT(0));

	dma_unmap_single(dev, dma, skb->len, DMA_TO_DEVICE);
	return 0;
}

void iwchaos_hw_rx_poll(void __iomem *mmio)
{
	u32 status;

	if (!mmio)
		return;

	status = iwchaos_readl(mmio, CSR_INT);
	if (status & BIT(1))
		iwchaos_writel(mmio, CSR_INT, BIT(1));
}

void iwchaos_scan_done(struct ieee80211_hw *hw, bool aborted)
{
	struct cfg80211_scan_info info = { .aborted = aborted };

	if (hw)
		ieee80211_scan_completed(hw, &info);
}
