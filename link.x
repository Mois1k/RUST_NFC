INCLUDE memory.x
ENTRY(Reset);

_estack = ORIGIN(RAM) + LENGTH(RAM);
_sidata = LOADADDR(.data);

SECTIONS
{
    .vector_table ORIGIN(FLASH) :
    {
        KEEP(*(.vector_table));
    } > FLASH

    .text :
    {
        *(.text .text.*);
    } > FLASH

    .rodata :
    {
        *(.rodata .rodata.*);
    } > FLASH

    .data : 
    {
        _sdata = .;
        *(.data .data.*);
        _edata = .;
    } > RAM AT> FLASH

    .bss : 
    {
        _sbss = .;
        *(.bss .bss.*);
        _ebss = .;
    } > RAM
}
