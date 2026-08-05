// Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
// SPDX-License-Identifier: Apache-2.0

//! Size-prefixed malloc/free backed by SP1's global allocator (embedded TLSF).
//! Overrides newlib when this crate is linked ahead of `-lc`.

use core::alloc::Layout;

const HEADER: usize = 16;

#[no_mangle]
pub unsafe extern "C" fn malloc(size: usize) -> *mut u8 {
    let size = if size == 0 { 1 } else { size };
    let total = size.saturating_add(HEADER);
    let Ok(layout) = Layout::from_size_align(total, HEADER) else {
        return core::ptr::null_mut();
    };
    let base = unsafe { alloc::alloc::alloc(layout) };
    if base.is_null() {
        return core::ptr::null_mut();
    }
    unsafe {
        (base as *mut usize).write(size);
        base.add(HEADER)
    }
}

#[no_mangle]
pub unsafe extern "C" fn calloc(nmemb: usize, size: usize) -> *mut u8 {
    let Some(bytes) = nmemb.checked_mul(size) else {
        return core::ptr::null_mut();
    };
    let ptr = unsafe { malloc(bytes) };
    if !ptr.is_null() {
        unsafe { core::ptr::write_bytes(ptr, 0, bytes) };
    }
    ptr
}

#[no_mangle]
pub unsafe extern "C" fn realloc(ptr: *mut u8, new_size: usize) -> *mut u8 {
    if ptr.is_null() {
        return unsafe { malloc(new_size) };
    }
    if new_size == 0 {
        unsafe { free(ptr) };
        return core::ptr::null_mut();
    }
    let old_size = unsafe { (ptr.sub(HEADER) as *const usize).read() };
    let new_ptr = unsafe { malloc(new_size) };
    if new_ptr.is_null() {
        return core::ptr::null_mut();
    }
    let n = old_size.min(new_size);
    unsafe { core::ptr::copy_nonoverlapping(ptr, new_ptr, n) };
    unsafe { free(ptr) };
    new_ptr
}

#[no_mangle]
pub unsafe extern "C" fn free(ptr: *mut u8) {
    if ptr.is_null() {
        return;
    }
    let base = unsafe { ptr.sub(HEADER) };
    let size = unsafe { (base as *const usize).read() };
    let total = size.saturating_add(HEADER);
    let Ok(layout) = Layout::from_size_align(total, HEADER) else {
        return;
    };
    unsafe { alloc::alloc::dealloc(base, layout) };
}
