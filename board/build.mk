CFLAGS += -I inc -I ../ -nostdlib -fno-builtin -std=gnu11 -O0
CFLAGS += -Tstm32_flash.ld

CC = arm-none-eabi-gcc
OBJCOPY = arm-none-eabi-objcopy
OBJDUMP = arm-none-eabi-objdump

ifeq ($(RELEASE),1)
  CERT = ../../pandaextra/certs/release
else
  # enable the debug cert
  CERT = ../certs/debug
  CFLAGS += "-DALLOW_DEBUG"
endif

DFU_UTIL = "dfu-util"

# this no longer pushes the bootstub
flash: obj/$(PROJ_NAME).bin
	python -c "from panda import Panda; Panda().flash('obj/$(PROJ_NAME).bin')"

ota: obj/$(PROJ_NAME).bin
	curl http://192.168.0.10/stupdate --upload-file $<

bin: obj/$(PROJ_NAME).bin

# this flashes everything
recover: obj/bootstub.$(PROJ_NAME).bin obj/$(PROJ_NAME).bin
	-python -c "from panda import Panda; Panda().reset(enter_bootloader=True)"
	sleep 0.5
	$(DFU_UTIL) -a 0 -s 0x08004000 -D obj/$(PROJ_NAME).bin
	$(DFU_UTIL) -a 0 -s 0x08000000:leave -D obj/bootstub.$(PROJ_NAME).bin

ifneq ($(wildcard ../.git/HEAD),)
obj/gitversion.h: ../.git/HEAD ../.git/index
	echo "const uint8_t gitversion[] = \"$(shell git rev-parse HEAD)\";" > $@
else
ifneq ($(wildcard ../../.git/modules/panda/HEAD),)
obj/gitversion.h: ../../.git/modules/panda/HEAD ../../.git/modules/panda/index
	echo "const uint8_t gitversion[] = \"$(shell git rev-parse HEAD)\";" > $@
else
obj/gitversion.h:
	echo "const uint8_t gitversion[] = \"RELEASE\";" > $@
endif
endif

obj/cert.h: ../crypto/getcertheader.py
	../crypto/getcertheader.py ../certs/debug.pub ../certs/release.pub > $@

obj/%.$(PROJ_NAME).o: %.c obj/cert.h obj/gitversion.h config.h drivers/*.h gpio.h provision.h
	$(CC) $(CFLAGS) -o $@ -c $<

obj/%.$(PROJ_NAME).o: ../crypto/%.c
	$(CC) $(CFLAGS) -o $@ -c $<

obj/$(STARTUP_FILE).o: $(STARTUP_FILE).s
	$(CC) $(CFLAGS) -o $@ -c $<

obj/$(PROJ_NAME).bin: obj/$(STARTUP_FILE).o obj/main.$(PROJ_NAME).o
  # hack
	$(CC) -Wl,--section-start,.isr_vector=0x8004000 $(CFLAGS) -o obj/$(PROJ_NAME).elf $^
	$(OBJCOPY) -v -O binary obj/$(PROJ_NAME).elf obj/code.bin
	SETLEN=1 ../crypto/sign.py obj/code.bin $@ $(CERT)

obj/bootstub.$(PROJ_NAME).bin: obj/$(STARTUP_FILE).o obj/bootstub.$(PROJ_NAME).o obj/sha.$(PROJ_NAME).o obj/rsa.$(PROJ_NAME).o
	$(CC) $(CFLAGS) -o obj/bootstub.$(PROJ_NAME).elf $^
	$(OBJCOPY) -v -O binary obj/bootstub.$(PROJ_NAME).elf $@

clean:
	@rm -f obj/*
