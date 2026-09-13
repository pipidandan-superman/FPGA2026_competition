#include <stdint.h>

#if defined(__aarch64__) || defined(__arm__)
static inline void io_barrier(void) {
    __asm__ volatile ("dmb sy" ::: "memory");
}
#else
static inline void io_barrier(void) {
    __sync_synchronize();
}
#endif

uint32_t axilt_read32(volatile void *base, uint32_t offset) {
    volatile uint32_t *address =
        (volatile uint32_t *)((volatile uint8_t *)base + offset);
    io_barrier();
    uint32_t value = *address;
    io_barrier();
    return value;
}

void axilt_write32(volatile void *base, uint32_t offset, uint32_t value) {
    volatile uint32_t *address =
        (volatile uint32_t *)((volatile uint8_t *)base + offset);
    io_barrier();
    *address = value;
    io_barrier();
}
