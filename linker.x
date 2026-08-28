INCLUDE memory.x

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
        *(.rodata .rodata.*)
    } > FLASH
}
