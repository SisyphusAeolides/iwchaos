# SPDX-License-Identifier: GPL-2.0-only
#
# iwchaos — complete iwlwifi + iwlmvm replacement (single module)
#

obj-$(CONFIG_IWCHAOS) += iwchaos.o

IWL := vendor/iwlwifi
MVM := $(IWL)/mvm
PCIE := $(IWL)/pcie
CFG := $(IWL)/cfg
FW := $(IWL)/fw

iwchaos-y := \
	$(IWL)/iwl-io.o \
	$(IWL)/iwl-drv.o \
	$(IWL)/iwl-debug.o \
	$(IWL)/iwl-nvm-utils.o \
	$(IWL)/iwl-utils.o \
	$(IWL)/iwl-phy-db.o \
	$(IWL)/iwl-nvm-parse.o \
	$(PCIE)/ctxt-info.o \
	$(PCIE)/ctxt-info-v2.o \
	$(PCIE)/drv.o \
	$(PCIE)/utils.o \
	$(PCIE)/gen1_2/rx.o \
	$(PCIE)/gen1_2/tx.o \
	$(PCIE)/gen1_2/trans.o \
	$(PCIE)/gen1_2/trans-gen2.o \
	$(PCIE)/gen1_2/tx-gen2.o \
	$(CFG)/7000.o \
	$(CFG)/8000.o \
	$(CFG)/9000.o \
	$(CFG)/22000.o \
	$(CFG)/ax210.o \
	$(CFG)/bz.o \
	$(CFG)/sc.o \
	$(CFG)/dr.o \
	$(CFG)/5000.o \
	$(CFG)/6000.o \
	$(CFG)/2000.o \
	$(CFG)/1000.o \
	$(CFG)/rf-jf.o \
	$(CFG)/rf-hr.o \
	$(CFG)/rf-gf.o \
	$(CFG)/rf-fm.o \
	$(CFG)/rf-wh.o \
	$(CFG)/rf-pe.o \
	$(IWL)/iwl-dbg-tlv.o \
	$(IWL)/iwl-devtrace.o \
	$(IWL)/iwl-trans.o \
	$(FW)/img.o \
	$(FW)/notif-wait.o \
	$(FW)/rs.o \
	$(FW)/dbg.o \
	$(FW)/dbg-old.o \
	$(FW)/pnvm.o \
	$(FW)/dump.o \
	$(FW)/regulatory.o \
	$(FW)/paging.o \
	$(FW)/smem.o \
	$(FW)/init.o \
	$(FW)/acpi.o \
	$(FW)/uefi.o \
	$(FW)/debugfs.o \
	$(MVM)/fw.o \
	$(MVM)/mac80211.o \
	$(MVM)/nvm.o \
	$(MVM)/ops.o \
	$(MVM)/phy-ctxt.o \
	$(MVM)/mac-ctxt.o \
	$(MVM)/utils.o \
	$(MVM)/rx.o \
	$(MVM)/rxmq.o \
	$(MVM)/tx.o \
	$(MVM)/binding.o \
	$(MVM)/quota.o \
	$(MVM)/sta.o \
	$(MVM)/sf.o \
	$(MVM)/scan.o \
	$(MVM)/time-event.o \
	$(MVM)/rs.o \
	$(MVM)/rs-fw.o \
	$(MVM)/power.o \
	$(MVM)/coex.o \
	$(MVM)/tt.o \
	$(MVM)/offloading.o \
	$(MVM)/tdls.o \
	$(MVM)/ftm-responder.o \
	$(MVM)/ftm-initiator.o \
	$(MVM)/rfi.o \
	$(MVM)/mld-key.o \
	$(MVM)/mld-mac.o \
	$(MVM)/link.o \
	$(MVM)/mld-sta.o \
	$(MVM)/mld-mac80211.o \
	$(MVM)/ptp.o \
	$(MVM)/time-sync.o \
	$(MVM)/debugfs.o \
	$(MVM)/debugfs-vif.o \
	$(MVM)/led.o \
	$(MVM)/d3.o \
	c/shim_module.o \
	c/shim_chaos.o \
	idris/generated/firmware_sm.o \
	idris/generated/dma_linear.o \
	rust/libiwchaos_core.prebuilt.o

CFLAGS_vendor/iwlwifi/pcie/drv.o := -Wno-override-init

OBJECT_FILES_NON_STANDARD_rust/libiwchaos_core.prebuilt.o := y

ccflags-y := -I$(src)/include \
             -I$(src)/vendor/iwlwifi \
             -I$(src)/vendor/iwlwifi/mvm \
             -include $(src)/include/iwchaos_kconfig.h \
             -DCONFIG_IWLMVM \
             -DCONFIG_IWLWIFI \
             -DIWCHAOS_MONOLITHIC \
             -DCONFIG_IWLWIFI_DEBUGFS \
             -DCONFIG_IWLWIFI_LEDS \
             -DCONFIG_MAC80211_LEDS \
             -DCONFIG_PM_SLEEP \
             -DCONFIG_ACPI \
             -DCONFIG_EFI \
             -DCONFIG_IWLWIFI_DEBUG
