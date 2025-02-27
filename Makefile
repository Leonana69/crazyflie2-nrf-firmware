#Put your personal build config in config.mk and DO NOT COMMIT IT!
-include config.mk

CLOAD_SCRIPT ?= python3 ./cfloader.py

S110 ?= 1     # SoftDevice flashed or not
BLE  ?= 1     # BLE mode activated or not. If disabled, CRTP mode is active

DEBUG_PRINT_ON_SEGGER_RTT ?= 0 # debug prints

PLATFORM ?= cf2

CROSS_COMPILE?=arm-none-eabi-

CC=$(CROSS_COMPILE)gcc
AS=$(CROSS_COMPILE)as
LD=$(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
SIZE = $(CROSS_COMPILE)size
GDB=$(CROSS_COMPILE)gdb

OPENOCD           ?= openocd
OPENOCD_DIR       ?=
OPENOCD_INTERFACE ?= $(OPENOCD_DIR)interface/stlink.cfg
OPENOCD_TARGET    ?= target/nrf51.cfg
OPENOCD_CMDS      ?=


NRF51_SDK ?= nrf51_sdk/nrf51822
NRF_S110 ?= s110

INCLUDES= -I Include -I Include/gcc -Iinterface

#CONFIG = -DRSSI_ACK_PACKET
BUILD_OPTION = -g3 -O0 -Wall -Werror -fsingle-precision-constant -ffast-math -std=gnu11
PERSONAL_DEFINES ?=

PROCESSOR = -mcpu=cortex-m0 -mthumb
NRF= -DNRF51
PROGRAM=$(PLATFORM)_nrf

CFLAGS+=$(PROCESSOR) $(NRF) $(PERSONAL_DEFINES) $(INCLUDES) $(CONFIG) $(BUILD_OPTION)
ASFLAGS=$(PROCESSOR)
LDFLAGS=$(PROCESSOR) -O0 --specs=nano.specs -Wl,-Map=$(PROGRAM).map# -Wl,--gc-sections
ifdef SEMIHOSTING
LDFLAGS+= --specs=rdimon.specs -lc -lrdimon
CFLAGS+= -DSEMIHOSTING
endif

ifeq ($(strip $(S110)), 1)
LDFLAGS += -T gcc_nrf51_s110_xxaa.ld
CFLAGS += -DS110=1
else
LDFLAGS += -T gcc_nrf51_blank_xxaa.ld
endif

ifeq ($(strip $(BLE)), 1)
CFLAGS += -DBLE=1
endif

OBJS += src/ble/ble.o
OBJS += src/ble/ble_crazyflies.o
OBJS += src/ble/timeslot.o

OBJS += $(NRF51_SDK)/Source/ble/ble_advdata.o
OBJS += $(NRF51_SDK)/Source/ble/ble_conn_params.o
OBJS += $(NRF51_SDK)/Source/ble/ble_services/ble_srv_common.o
OBJS += $(NRF51_SDK)/Source/ble/ble_services/ble_dis.o
OBJS += $(NRF51_SDK)/Source/sd_common/softdevice_handler.o
OBJS += $(NRF51_SDK)/Source/app_common/app_timer.o
OBJS += $(NRF51_SDK)/Source/app_common/pstorage.o
OBJS += $(NRF51_SDK)/Source/ble/device_manager/device_manager_peripheral.o

CFLAGS += -DBLE_STACK_SUPPORT_REQD -DNRF51
CFLAGS += -I$(NRF51_SDK)/Include/gcc
CFLAGS += -I$(NRF51_SDK)/Include/
CFLAGS += -I$(NRF51_SDK)/Include/ble/
CFLAGS += -I$(NRF51_SDK)/Include/ble/ble_services/
CFLAGS += -I$(NRF51_SDK)/Include/ble/device_manager/
CFLAGS += -I$(NRF_S110)/s110_nrf51822_7.3.0_API/include
CFLAGS += -I$(NRF_S110)/Include/
CFLAGS += -I$(NRF51_SDK)/Include/app_common/
CFLAGS += -I$(NRF51_SDK)/Include/sd_common/
CFLAGS += -I$(NRF51_SDK)/Include/sdk/

OBJS += src/main.o gcc_startup_nrf51.o system_nrf51.o src/uart.o \
        src/syslink.o src/pm.o src/systick.o src/button.o src/swd.o src/ow.o \
        src/ow/owlnk.o src/ow/ownet.o src/ow/owtran.o \
        src/ow/crcutil.o src/ds2431.o src/ds28e05.o src/esb.o src/memory.o \
		src/platform.o src/platform_$(PLATFORM).o src/debug.o src/shutdown.o

ifeq ($(strip $(DEBUG_PRINT_ON_SEGGER_RTT)), 1)
	INCLUDES += -I src/lib/Segger_RTT/RTT
	OBJS += src/lib/Segger_RTT/RTT/SEGGER_RTT.o src/lib/Segger_RTT/RTT/SEGGER_RTT_printf.o
	CFLAGS += -DDEBUG_PRINT_ON_SEGGER_RTT
endif


all: $(PROGRAM).elf $(PROGRAM).bin $(PROGRAM).hex
	$(SIZE) $(PROGRAM).elf
ifeq ($(strip $(S110)),1)
	@echo "S110 Activated"
else
	@echo "S110 Disabled"
endif
ifeq ($(strip $(BLE)),1)
	@echo "BLE  Activated"
else
	@echo "BLE  Disabled"
endif
	@echo "Built for platform $(PLATFORM)"

$(PROGRAM).hex: $(PROGRAM).elf
	$(OBJCOPY) $^ -O ihex $@

$(PROGRAM).bin: $(PROGRAM).elf
	$(OBJCOPY) $^ -O binary $@

$(PROGRAM).elf: $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

# The '|' denotes Include/version.h as an order-only prerequisite, it will not
# force a rebuild the file is updated, but makes sure that the file exists
# before we start generating the object files.
$(OBJS): | Include/version.h

# Dummy target to force re-generation of version.h eacn run.
#
# If a rule has no prerequisites or recipe, and the target of the rule is a
# nonexistent file, then make imagines this target to have been updated
# whenever its rule is run. This implies that all targets depending on this one
# will always have their recipe run.
FORCE:

Include/version.h: FORCE
	python3 tools/build/generateVersionHeader.py --crazyflie-base $(abspath .) --output $@

clean:
	rm -f $(PROGRAM).bin $(PROGRAM).elf $(OBJS)


## Flash and debug targets

flash: $(PROGRAM).hex
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET)  -c init -c targets -c "reset halt" \
                 -c "flash write_image erase $(PROGRAM).hex" -c "verify_image $(PROGRAM).hex" \
                 -c "reset run" -c shutdown

flash_s110: $(NRF_S110)/s110_nrf51822_7.3.0_softdevice.hex
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "nrf51 mass_erase" \
                 -c "flash write_image erase s110/s110_nrf51822_7.3.0_softdevice.hex" \
                 -c "reset run" -c shutdown

flash_mbs: bootloaders/nrf_mbs_cf21.hex
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "flash write_image erase $^" -c "verify_image $^" -c "reset halt" \
	               -c "mww 0x4001e504 0x01" -c "mww 0x10001014 0x3F000" \
	               -c "reset run" -c shutdown

flash_cload: bootloaders/cload_nrf_cf21.hex
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "flash write_image erase $^" -c "verify_image $^" -c "reset halt" \
	               -c "mww 0x4001e504 0x01" -c "mww 0x10001014 0x3F000" \
	               -c "mww 0x4001e504 0x01" -c "mww 0x10001080 0x3A000" -c "reset run" -c shutdown

mass_erase:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c "reset halt" \
                 -c "nrf51 mass_erase" -c shutdown

reset:
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets \
	               -c reset -c shutdown

openocd: $(PROGRAM).elf
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets


semihosting: $(PROGRAM).elf
	$(OPENOCD) -d2 -f $(OPENOCD_INTERFACE) $(OPENOCD_CMDS) -f $(OPENOCD_TARGET) -c init -c targets -c reset -c "arm semihosting enable" -c reset

gdb: $(PROGRAM).elf
	$(GDB) -ex "target remote localhost:3333" -ex "monitor reset halt" $^

flash_jlink:
	JLinkExe -if swd -device NRF51822 flash.jlink

cload: $(PROGRAM).bin
ifeq ($(strip $(S110)), 1)
	$(CLOAD_SCRIPT) flash $(PROGRAM).bin nrf51-fw
else
	@echo "Only S110 build can be bootloaded. Launch build and cload with S110=1"
endif

factory_reset_21:
	make mass_erase
ifeq ($(strip $(S110)),1)
	make flash_s110
	make flash_mbs
	make flash_cload
endif
	make flash
