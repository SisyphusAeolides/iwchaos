// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — PCIe shim (claims bus, delegates to Rust)
 */

#include <linux/kernel.h>
#include <linux/pci.h>
#include <linux/firmware.h>
#include <linux/leds.h>
#include <linux/slab.h>
#include "iwchaos_shim.h"

struct iwchaos_led {
	struct led_classdev cdev;
	void *rust_ctx;
};

static void iwchaos_led_brightness_set(struct led_classdev *cdev,
				       enum led_brightness brightness)
{
	struct iwchaos_led *led = container_of(cdev, struct iwchaos_led, cdev);

	iwchaos_led_set_rust(led->rust_ctx, brightness);
}

static const struct pci_device_id iwchaos_pci_ids[] = {
	{ PCI_DEVICE(0x8086, 0x02f0) }, /* Intel Wi-Fi 6 AX201 */
	{ PCI_DEVICE(0x8086, 0x2723) }, /* Intel Wi-Fi 6 AX200 */
	{ }
};
MODULE_DEVICE_TABLE(pci, iwchaos_pci_ids);

struct iwchaos_pci_priv {
	struct ieee80211_hw *hw;
	struct iwchaos_led *led;
	void __iomem *mmio;
};

static int iwchaos_pci_probe(struct pci_dev *pdev, const struct pci_device_id *id);
static void iwchaos_pci_remove(struct pci_dev *pdev);

int iwchaos_pci_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct ieee80211_hw *hw;
	struct iwchaos_pci_priv *priv;
	void *rust_ctx;
	const struct firmware *fw;
	int err;

	priv = kzalloc(sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	err = pci_enable_device(pdev);
	if (err)
		goto err_free_priv;

	pci_set_master(pdev);

	err = pci_request_regions(pdev, "iwchaos");
	if (err)
		goto err_disable;

	priv->mmio = pci_ioremap_bar(pdev, 0);
	if (!priv->mmio) {
		err = -ENOMEM;
		goto err_regions;
	}

	hw = iwchaos_mac80211_alloc(&pdev->dev);
	if (!hw) {
		err = -ENOMEM;
		goto err_iounmap;
	}
	priv->hw = hw;

	rust_ctx = iwchaos_core_alloc(hw, priv->mmio, &pdev->dev);
	if (!rust_ctx) {
		err = -ENOMEM;
		goto err_hw;
	 }

	pci_set_drvdata(pdev, priv);

	/* Intel AX200 production ucode (same image iwlwifi loads) */
	err = request_firmware(&fw, "iwlwifi-cc-a0-77.ucode", &pdev->dev);
	if (err) {
		pr_err("iwchaos: firmware iwlwifi-cc-a0-77.ucode missing (%d)\n", err);
		goto err_rust;
	}

	err = iwchaos_core_load_firmware(rust_ctx, fw->data, fw->size);
	release_firmware(fw);
	if (err) {
		pr_err("iwchaos: firmware load failed %d\n", err);
		goto err_rust;
	}

	err = iwchaos_mac80211_register(rust_ctx, hw);
	if (err)
		goto err_rust;

	priv->led = kzalloc(sizeof(*priv->led), GFP_KERNEL);
	if (priv->led) {
		priv->led->rust_ctx = rust_ctx;
		priv->led->cdev.name = "iwchaos-led";
		priv->led->cdev.default_trigger = "phy0-tx";
		priv->led->cdev.brightness_set = iwchaos_led_brightness_set;
		priv->led->cdev.max_brightness = 255;
		if (led_classdev_register(&pdev->dev, &priv->led->cdev)) {
			kfree(priv->led);
			priv->led = NULL;
		}
	}

	pr_info("iwchaos: AX200 ready (Rust chaos core, PCI %04x:%04x)\n",
		id->vendor, id->device);
	return 0;

err_rust:
	iwchaos_core_free(rust_ctx);
err_hw:
	ieee80211_free_hw(hw);
err_iounmap:
	pci_iounmap(pdev, priv->mmio);
err_regions:
	pci_release_regions(pdev);
err_disable:
	pci_disable_device(pdev);
err_free_priv:
	kfree(priv);
	return err;
}

void iwchaos_pci_remove(struct pci_dev *pdev)
{
	struct iwchaos_pci_priv *priv = pci_get_drvdata(pdev);
	struct ieee80211_hw *hw;
	void **hw_priv;
	void *rust_ctx;

	if (!priv)
		return;

	if (priv->led) {
		led_classdev_unregister(&priv->led->cdev);
		kfree(priv->led);
	}

	hw = priv->hw;
	if (hw) {
		hw_priv = hw->priv;
		rust_ctx = hw_priv ? *hw_priv : NULL;
		iwchaos_mac80211_unregister(hw);
		iwchaos_core_free(rust_ctx);
	}

	if (priv->mmio)
		pci_iounmap(pdev, priv->mmio);

	pci_release_regions(pdev);
	pci_disable_device(pdev);
	kfree(priv);
}

static struct pci_driver iwchaos_pci_driver = {
	.name     = "iwchaos",
	.id_table = iwchaos_pci_ids,
	.probe    = iwchaos_pci_probe,
	.remove   = iwchaos_pci_remove,
};

int iwchaos_pci_register(void)
{
	return pci_register_driver(&iwchaos_pci_driver);
}

void iwchaos_pci_unregister(void)
{
	pci_unregister_driver(&iwchaos_pci_driver);
}

MODULE_FIRMWARE("iwlwifi-cc-a0-77.ucode");
