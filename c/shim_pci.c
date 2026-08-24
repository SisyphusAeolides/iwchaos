// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — PCIe shim
 *
 * pci_driver probe/remove callbacks. Delegates device lifetime to the
 * Rust RFL core after the PCI resource has been claimed.
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
};

int iwchaos_pci_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
    struct ieee80211_hw *hw;
    struct iwchaos_pci_priv *priv;
    void __iomem *mmio_base;
    void *rust_ctx;
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

    mmio_base = pci_ioremap_bar(pdev, 0);
    if (!mmio_base) {
        err = -ENOMEM;
        goto err_regions;
    }

    hw = iwchaos_mac80211_alloc(&pdev->dev);
    if (!hw) {
        err = -ENOMEM;
        goto err_iounmap;
    }
    priv->hw = hw;

    /* Allocate the Rust Core (Chaos Engine + DMA rings) */
    rust_ctx = iwchaos_core_alloc(hw, mmio_base);
    if (!rust_ctx) {
        err = -ENOMEM;
        goto err_hw;
    }

    /* Save priv pointer for remove */
    pci_set_drvdata(pdev, priv);

    /* Request firmware (scaffolding for replacing iwlwifi ucode) */
    {
        const struct firmware *fw;
        err = request_firmware(&fw, "iwchaos-firmware.ucode", &pdev->dev);
        if (err) {
            pr_err("iwchaos: failed to load firmware %d\n", err);
            goto err_rust;
        }
        pr_info("iwchaos: loaded firmware %zu bytes\n", fw->size);
        release_firmware(fw);
    }

    err = iwchaos_mac80211_register(rust_ctx, hw);
    if (err)
        goto err_rust;

    /* Register LED classdev for ThinkPad Wi-Fi LED */
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

    pr_info("iwchaos: PCIe device initialized successfully\n");
    return 0;

err_rust:
    iwchaos_core_free(rust_ctx);
err_hw:
    ieee80211_free_hw(hw);
err_iounmap:
    pci_iounmap(pdev, mmio_base);
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
        rust_ctx = *hw_priv;
        iwchaos_mac80211_unregister(hw);
        iwchaos_core_free(rust_ctx);
    }

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

MODULE_FIRMWARE("iwchaos-firmware.ucode");
