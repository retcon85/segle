# z88dk-z80asm -l -b -m -O./build -o./build/segle.sms main.asm tiles.asm answers.asm

TARGET = segle.sms
TARGETDIR = ./build
CC = z88dk-z80asm
OPTIONS =  -l -b -m -O$(TARGETDIR) -o$(TARGETDIR)/$(TARGET)
FILES = main.asm tiles.asm answers.asm

build: pre-build
	$(CC) $(OPTIONS) $(FILES)

pre-build:
	-mkdir ./build

tiles:
	../retcon-util/img2tiles.py letters4x4.bmp > tiles-generated.asm

clean:
	rm $(TARGETDIR)/*
