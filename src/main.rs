#![no_std]
#![no_main]

use core::{panic::PanicInfo};

#[panic_handler]
fn panic_handler(_info: &PanicInfo<'_>) -> ! {
    loop {}
}
