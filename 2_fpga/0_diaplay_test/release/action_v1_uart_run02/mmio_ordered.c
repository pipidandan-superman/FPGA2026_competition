/* ARM device-MMIO access for the independent AXI-Lite test.
 * Compile on the board: cc -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared
 *                      mmio_ordered.c -o libmmio_ordered.so
 * PYNQ owns the mapping and keeps its array alive for these calls.
 */
#include <stdint.h>
#include <stddef.h>

#if !defined(__arm__) && !defined(__aarch64__)
#error "This library must be built for the target ARM board."
#endif

static inline void full_barrier(void)
{
    __asm__ volatile("dsb sy" ::: "memory");
}

uint32_t axilt_read32(void *base, uint32_t offset)
{
    full_barrier();
    uint32_t value = *(volatile uint32_t *)((uint8_t *)base + offset);
    full_barrier();
    return value;
}

void axilt_write32(void *base, uint32_t offset, uint32_t value)
{
    full_barrier();
    *(volatile uint32_t *)((uint8_t *)base + offset) = value;
    full_barrier();
}

void axilt_barrier(void)
{
    full_barrier();
}

