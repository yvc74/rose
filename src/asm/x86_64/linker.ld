STARTUP(../../../build/x86_64/kernel/obj/startup.o)
ENTRY (boot)

SECTIONS
{
    . = 0xC0100000;
    _ld_start = .;

    _ld_text = .;
    .text : AT(ADDR(.text) - 0xC0000000) {
        *(.text)
    }

    _ld_rodata = .;
    .rodata ALIGN (0x1000) : AT(ADDR(.rodata) - 0xC0000000) {
        *(.rodata)
    }

    _ld_data = .;
    .data ALIGN (0x1000) : AT(ADDR(.data) - 0xC0000000){
        *(.data)
    }

    . = ALIGN(0x1000);

    KernPageDir = .;
    . = . + 4096;

    _ld_bss = .;
    .bss : AT(ADDR(.bss) - 0xC0000000){
        *(COMMON)
        *(.bss)
    }

    _ld_note = .;
    .note : AT(ADDR(.note) - 0xC0000000) {
          *(.note)
    }

    _ld_debug = .;
    .debug : AT(ADDR(.note) - 0xC0000000) {
          *(.debug)
    }

    _ld_end = .;
}
