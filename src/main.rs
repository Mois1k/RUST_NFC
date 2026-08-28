#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic_handler(_info: &PanicInfo<'_>) -> ! {
    loop {}
}

unsafe extern "C" {
    static _estack: u32;
}

#[repr(C)]
struct VectorTable {
    stack_pointer: *const u32,
    reset: unsafe extern "C" fn() -> !,
}

unsafe impl Sync for VectorTable{}

#[used]
#[unsafe(link_section = ".vector_table")]
static VECTOR: VectorTable = VectorTable {
    stack_pointer: unsafe { &_estack as *const u32 },
    reset: Reset,
};

#[unsafe(no_mangle)]
pub extern "C" fn Reset() -> ! {
    loop {}
}
