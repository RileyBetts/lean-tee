/*
 * Copyright © 2026 Riley Betts Ltd (rileybetts.ai)
 * SPDX-License-Identifier: Apache-2.0
 */

/* SP1 guest shims for Lean runtime (adapted from Anoma risc0-lean-example). */
#include <stddef.h>
#include <stdint.h>
#include <sys/time.h>

int _gettimeofday(struct timeval *__p, void *__tz) {
  (void)__p;
  (void)__tz;
  return -1;
}

unsigned int __atomic_fetch_sub_4(volatile void *ptr, unsigned int val, int memorder) {
  (void)memorder;
  uint32_t *p = (uint32_t *)ptr;
  unsigned int old = *p;
  *p = old - val;
  return old;
}

unsigned int __atomic_fetch_add_4(volatile void *ptr, unsigned int val, int memorder) {
  (void)memorder;
  uint32_t *p = (uint32_t *)ptr;
  unsigned int old = *p;
  *p = old + val;
  return old;
}

_Bool __atomic_compare_exchange_4(volatile void *ptr, void *expected, unsigned int desired,
                                  _Bool weak, int success_memorder, int failure_memorder) {
  (void)weak;
  (void)success_memorder;
  (void)failure_memorder;
  uint32_t *p = (uint32_t *)ptr;
  uint32_t *e = (uint32_t *)expected;
  if (*p == *e) {
    *p = desired;
    return 1;
  }
  *e = *p;
  return 0;
}

unsigned long long __atomic_exchange_8(volatile void *ptr, unsigned long long val, int memorder) {
  (void)memorder;
  uint64_t *p = (uint64_t *)ptr;
  uint64_t old = *p;
  *p = val;
  return old;
}

/* libstdc++ globals want this under freestanding links. */
void *__dso_handle = (void *)0;

#define SBRK_MAX_HEAP (4 * 1024)
static unsigned char sbrk_heap[SBRK_MAX_HEAP];
static ptrdiff_t sbrk_bkrp = 0;

void *_sbrk(ptrdiff_t incr) {
  ptrdiff_t free = sbrk_bkrp;
  if (incr < 0)
    return (void *)-1;
  if (sbrk_bkrp + incr > SBRK_MAX_HEAP)
    return (void *)-1;
  sbrk_bkrp += incr;
  return &sbrk_heap[free];
}

void _Unwind_Resume(void) {}
void _Unwind_RaiseException(void) {}
void _Unwind_Resume_or_Rethrow(void) {}
void _Unwind_GetTextRelBase(void) {}
void _Unwind_GetDataRelBase(void) {}
void _Unwind_DeleteException(void) {}
void _Unwind_GetRegionStart(void) {}
void _Unwind_GetLanguageSpecificData(void) {}
void _Unwind_GetIPInfo(void) {}
void _Unwind_SetGR(void) {}
void _Unwind_GetGR(void) {}
void _Unwind_SetIP(void) {}

int _kill(int pid, int sig) {
  (void)pid;
  (void)sig;
  return -1;
}
int _getpid(void) { return 1; }
void _exit(int status) {
  (void)status;
  for (;;) {
  }
}
int _fstat(void) { return -1; }
int _isatty(void) { return -1; }
int _lseek(void) { return -1; }
int _read(void) { return -1; }
int _write(void) { return -1; }
int _open(void) { return -1; }
int _close(void) { return -1; }
