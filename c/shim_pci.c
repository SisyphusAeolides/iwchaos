// SPDX-License-Identifier: GPL-2.0-only
/*
 * iwchaos — PCIe shim
 *
 * pci_driver probe/remove callbacks. Delegates device lifetime to the
 * Rust RFL core after the PCI resource has been claimed.
 */

#include <linux/kernel.h>
#include <linux/pci.h>
#include "iwchaos_shim.h"

static const struct pci_device_id iwchaos_pci_ids[] = {
    { PCI_DEVICE(0x8086, 0x02f0) }, /* Intel Wi-Fi 6 AX201 */
    { PCI_DEVICE(0x8086, 0x2723) }, /* Intel Wi-Fi 6 AX200 */
    { }
};
MODULE_DEVICE_TABLE(pci, iwchaos_pci_ids);

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
