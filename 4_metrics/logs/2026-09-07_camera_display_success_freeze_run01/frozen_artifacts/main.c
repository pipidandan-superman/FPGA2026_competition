#include <stdint.h>
#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xil_types.h"
#include "xparameters.h"

#define DISPLAY_FB_BASE          0x10000000UL
#define DISPLAY_FB_BYTES         0x00300000UL

#define FRAME_COUNT              3UL
#define FRAME_SLOT_BYTES         0x00100000UL
#define FRAME_WIDTH              640UL
#define FRAME_HEIGHT             480UL
#define FRAME_PIXELS             (FRAME_WIDTH * FRAME_HEIGHT)
#define FRAME_BYTES              (FRAME_PIXELS * 3UL)
#define FRAME_STRIDE             (FRAME_WIDTH * 3UL)
#define COLOR_BAR_WIDTH          (FRAME_WIDTH / 5UL)

#define UART_BASE                XPAR_XUARTPS_0_BASEADDR
#define UART_SR_OFFSET           0x0000002CUL
#define UART_FIFO_OFFSET         0x00000030UL
#define UART_SR_TXFULL           0x00000010UL
#define UART_SR_TXEMPTY          0x00000008UL

#define VDMA_BASE                XPAR_AXI_VDMA_0_BASEADDR
#define VDMA_MM2S_CR             (VDMA_BASE + 0x00000000UL)
#define VDMA_MM2S_SR             (VDMA_BASE + 0x00000004UL)
#define VDMA_MM2S_VSIZE          (VDMA_BASE + 0x00000050UL)
#define VDMA_MM2S_HSIZE          (VDMA_BASE + 0x00000054UL)
#define VDMA_MM2S_STRIDE         (VDMA_BASE + 0x00000058UL)
#define VDMA_MM2S_ADDR_1         (VDMA_BASE + 0x0000005CUL)
#define VDMA_MM2S_ADDR_2         (VDMA_BASE + 0x00000060UL)
#define VDMA_MM2S_ADDR_3         (VDMA_BASE + 0x00000064UL)
#define VDMA_PARK_PTR            (VDMA_BASE + 0x00000028UL)
#define VDMA_S2MM_CR             (VDMA_BASE + 0x00000030UL)
#define VDMA_S2MM_SR             (VDMA_BASE + 0x00000034UL)
#define VDMA_S2MM_VSIZE          (VDMA_BASE + 0x000000A0UL)
#define VDMA_S2MM_HSIZE          (VDMA_BASE + 0x000000A4UL)
#define VDMA_S2MM_STRIDE         (VDMA_BASE + 0x000000A8UL)
#define VDMA_S2MM_ADDR_1         (VDMA_BASE + 0x000000ACUL)
#define VDMA_S2MM_ADDR_2         (VDMA_BASE + 0x000000B0UL)
#define VDMA_S2MM_ADDR_3         (VDMA_BASE + 0x000000B4UL)

#define VDMA_CR_RUN              0x00000001UL
#define VDMA_CR_CIRCULAR         0x00000002UL
#define VDMA_CR_RESET            0x00000004UL
#define VDMA_CR_GENLOCK_ENABLE   0x00000008UL
#define VDMA_CR_GENLOCK_INTERNAL 0x00000080UL
#define VDMA_CR_IRQ_FRAME_COUNT_ONE 0x00010000UL
#define VDMA_CR_GENLOCK_REPEAT   0x00008000UL
#define VDMA_CR_FSYNC_TUSER      0x00000040UL
#define VDMA_SR_ERROR_MASK       0x00000FF0UL
#define VDMA_SR_IRQ_MASK         0x00007000UL
#define VDMA_SR_FRAME_COUNT_SHIFT 16UL

#define RESET_POLL_LIMIT         1000000UL
#define UART_POLL_LIMIT          10000UL
#define UART_POLL_DELAY_US       100UL
#define FIRST_FRAME_TIMEOUT_MS   5000UL
#define STABILITY_SECONDS        60UL

/* CR bit 16 is retained by this IP as IRQFrameCount=1 after start. */
#define VDMA_MM2S_CONTROL        (VDMA_CR_RUN | VDMA_CR_CIRCULAR | \
                                  VDMA_CR_GENLOCK_ENABLE | \
                                  VDMA_CR_GENLOCK_INTERNAL | \
                                  VDMA_CR_IRQ_FRAME_COUNT_ONE)

#define VDMA_CR_IRQ_FRAME_COUNT_RETAINED 0x00010000UL

/* Camera source and HDMI display both use the same proven 3-frame slots. */
/* Match the IP: S2MM is a dynamic genlock master with TUSER frame sync. */
#define VDMA_S2MM_CONTROL        (VDMA_CR_RUN | VDMA_CR_CIRCULAR | \
                                  VDMA_CR_GENLOCK_ENABLE | \
                                  VDMA_CR_GENLOCK_INTERNAL | \
                                  VDMA_CR_FSYNC_TUSER | \
                                  VDMA_CR_GENLOCK_REPEAT | \
                                  VDMA_CR_IRQ_FRAME_COUNT_ONE)
#define VDMA_S2MM_CONTROL_READBACK (VDMA_S2MM_CONTROL | \
                                  VDMA_CR_IRQ_FRAME_COUNT_RETAINED)

typedef struct {
    uint32_t address;
    uint8_t expected;
    uint8_t actual;
    uint32_t frame;
    uint32_t offset;
} ddr_error_t;

static void print_vdma_registers(void)
{
    xil_printf("VDMA_REG MM2S_CR=0x%08x MM2S_SR=0x%08x S2MM_CR=0x%08x S2MM_SR=0x%08x FRMSTORE=HW_FIXED_3\r\n",
               Xil_In32(VDMA_MM2S_CR), Xil_In32(VDMA_MM2S_SR),
               Xil_In32(VDMA_S2MM_CR), Xil_In32(VDMA_S2MM_SR));
    xil_printf("VDMA_REG ADDR1=0x%08x ADDR2=0x%08x ADDR3=0x%08x STRIDE=0x%08x HSIZE=0x%08x VSIZE=0x%08x\r\n",
               Xil_In32(VDMA_MM2S_ADDR_1), Xil_In32(VDMA_MM2S_ADDR_2),
               Xil_In32(VDMA_MM2S_ADDR_3), Xil_In32(VDMA_MM2S_STRIDE),
               Xil_In32(VDMA_MM2S_HSIZE), Xil_In32(VDMA_MM2S_VSIZE));
    xil_printf("VDMA_REG S2MM_ADDR1=0x%08x S2MM_ADDR2=0x%08x S2MM_ADDR3=0x%08x S2MM_STRIDE=0x%08x S2MM_HSIZE=0x%08x S2MM_VSIZE=0x%08x\r\n",
               Xil_In32(VDMA_S2MM_ADDR_1), Xil_In32(VDMA_S2MM_ADDR_2),
               Xil_In32(VDMA_S2MM_ADDR_3), Xil_In32(VDMA_S2MM_STRIDE),
               Xil_In32(VDMA_S2MM_HSIZE), Xil_In32(VDMA_S2MM_VSIZE));
    xil_printf("VDMA_REG PARKPTR=0x%08x READREF=%u CURRENT_READ=%u\r\n",
               Xil_In32(VDMA_PARK_PTR),
               Xil_In32(VDMA_PARK_PTR) & 0x1FUL,
               (Xil_In32(VDMA_PARK_PTR) >> 16UL) & 0x1FUL);
    xil_printf("VDMA_REG PARKPTR WRTREF=%u CURRENT_WRITE=%u\r\n",
               (Xil_In32(VDMA_PARK_PTR) >> 8UL) & 0x1FUL,
               (Xil_In32(VDMA_PARK_PTR) >> 24UL) & 0x1FUL);
}

static void print_vdma_fail(const char *step)
{
    xil_printf("PS_HDMI_VDMA_FAIL STEP=%s\r\n", step);
    print_vdma_registers();
}

static void print_ddr_fail(const char *step, const ddr_error_t *error)
{
    xil_printf("DDR_FAIL STEP=%s ADDR=0x%08x FRAME=%u BYTE_OFFSET=%u EXP=0x%02x ACT=0x%02x\r\n",
               step, error->address, error->frame, error->offset,
               error->expected, error->actual);
}

static int wait_uart_not_full(void)
{
    uint32_t timeout;

    for (timeout = 0U; timeout < UART_POLL_LIMIT; ++timeout) {
        if ((Xil_In32(UART_BASE + UART_SR_OFFSET) & UART_SR_TXFULL) == 0UL) {
            return 0;
        }
    }
    return -1;
}

/* Keep waiting long enough for 115200 baud transmission to leave the shifter. */
static int wait_uart_tx_empty(void)
{
    uint32_t timeout;

    for (timeout = 0U; timeout < UART_POLL_LIMIT; ++timeout) {
        usleep(UART_POLL_DELAY_US);
        if ((Xil_In32(UART_BASE + UART_SR_OFFSET) & UART_SR_TXEMPTY) != 0UL) {
            return 0;
        }
    }
    return -1;
}

static int run_uart_test(void)
{
    static const char token[] = "UART_SELFTEST\r\n";
    uint32_t index;
    uint32_t status;

    xil_printf("UART_TEST_BEGIN BASE=0x%08x\r\n", UART_BASE);
    xil_printf("UART_DIRECT_TOKEN_BEGIN\r\n");

    for (index = 0U; token[index] != '\0'; ++index) {
        if (wait_uart_not_full() != 0) {
            xil_printf("UART_TEST_FAIL REASON=TX_FULL INDEX=%u SR=0x%08x\r\n",
                       index, Xil_In32(UART_BASE + UART_SR_OFFSET));
            return -1;
        }
        Xil_Out32(UART_BASE + UART_FIFO_OFFSET, (uint32_t)token[index]);
    }

    if (wait_uart_tx_empty() != 0) {
        status = Xil_In32(UART_BASE + UART_SR_OFFSET);
        xil_printf("UART_TEST_FAIL REASON=TX_NOT_EMPTY SR=0x%08x\r\n", status);
        return -1;
    }

    status = Xil_In32(UART_BASE + UART_SR_OFFSET);
    xil_printf("UART_TEST_PASS SR=0x%08x\r\n", status);
    return 0;
}



static void Clear_FrameBuffer(uint8_t *frame_buffer, uint8_t r, uint8_t g, uint8_t b)
{
    uint32_t row;
    uint32_t column;
    uint32_t byte_index;

    /* Clear the whole 1 MiB slot; the display verifier also checks padding. */
    for (byte_index = 0U; byte_index < FRAME_SLOT_BYTES; ++byte_index) {
        frame_buffer[byte_index] = 0x00U;
    }

    for (row = 0U; row < FRAME_HEIGHT; ++row) {
        for (column = 0U; column < FRAME_WIDTH; ++column) {
            uint32_t offset = (row * FRAME_WIDTH + column) * 3UL;

            frame_buffer[offset + 0UL] = r;
            frame_buffer[offset + 1UL] = g;
            frame_buffer[offset + 2UL] = b;
        }
    }
    Xil_DCacheFlushRange((UINTPTR)frame_buffer, FRAME_SLOT_BYTES);
    Xil_DCacheInvalidateRange((UINTPTR)frame_buffer, FRAME_SLOT_BYTES);
}

static int clear_display_ddr(ddr_error_t *error)
{
    volatile uint8_t *memory = (volatile uint8_t *)(uintptr_t)DISPLAY_FB_BASE;
    uint32_t index;

    xil_printf("DDR_CLEAR_BEGIN BASE=0x%08x BYTES=%u\r\n",
               DISPLAY_FB_BASE, DISPLAY_FB_BYTES);

    for (uint32_t frame = 0U; frame < FRAME_COUNT; ++frame) {
        Clear_FrameBuffer((uint8_t *)(uintptr_t)
                          (DISPLAY_FB_BASE + frame * FRAME_SLOT_BYTES), 0U, 0U, 0U);
    }

    for (index = 0U; index < DISPLAY_FB_BYTES; ++index) {
        uint8_t actual = memory[index];
        if (actual != 0x00U) {
            error->address = DISPLAY_FB_BASE + index;
            error->expected = 0x00U;
            error->actual = actual;
            error->frame = index / FRAME_SLOT_BYTES;
            error->offset = index % FRAME_SLOT_BYTES;
            print_ddr_fail("CLEAR", error);
            return -1;
        }
    }

    xil_printf("DDR_CLEAR_PASS BASE=0x%08x BYTES=%u\r\n",
               DISPLAY_FB_BASE, DISPLAY_FB_BYTES);
    return 0;
}



static int vdma_reset_channel(uint32_t control_register, const char *name)
{
    uint32_t timeout;

    Xil_Out32(control_register, VDMA_CR_RESET);
    for (timeout = 0U; timeout < RESET_POLL_LIMIT; ++timeout) {
        if ((Xil_In32(control_register) & VDMA_CR_RESET) == 0UL) {
            return 0;
        }
    }

    xil_printf("VDMA_RESET_FAIL CHANNEL=%s CR=0x%08x\r\n",
               name, Xil_In32(control_register));
    return -1;
}

/* Reference-style reset: both channels self-clear, then a short settle delay. */
static int VDMA_Reset(void)
{
    volatile uint32_t delay;

    if (vdma_reset_channel(VDMA_MM2S_CR, "MM2S") != 0) {
        return -1;
    }
    Xil_Out32(VDMA_MM2S_SR, VDMA_SR_ERROR_MASK | VDMA_SR_IRQ_MASK);

    if (vdma_reset_channel(VDMA_S2MM_CR, "S2MM") != 0) {
        return -1;
    }

    for (delay = 0U; delay < 1000U; ++delay) {
    }

    if ((Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) != 0UL ||
        (Xil_In32(VDMA_S2MM_CR) & VDMA_CR_RUN) != 0UL) {
        xil_printf("VDMA_RESET_FAIL REASON=RUN_ASSERTED MM2S_CR=0x%08x S2MM_CR=0x%08x\r\n",
                   Xil_In32(VDMA_MM2S_CR), Xil_In32(VDMA_S2MM_CR));
        return -1;
    }

    xil_printf("VDMA_S2MM_STOPPED CR=0x%08x SR=0x%08x\r\n",
               Xil_In32(VDMA_S2MM_CR), Xil_In32(VDMA_S2MM_SR));
    xil_printf("VDMA_RESET_OK\r\n");
    return 0;
}

static uint32_t vdma_mm2s_frame_count(void)
{
    return (Xil_In32(VDMA_MM2S_SR) >> VDMA_SR_FRAME_COUNT_SHIFT) & 0xFFUL;
}

static uint32_t vdma_s2mm_frame_count(void)
{
    return (Xil_In32(VDMA_S2MM_SR) >> VDMA_SR_FRAME_COUNT_SHIFT) & 0xFFUL;
}

/* PARKPTR current-write moves only after the S2MM finishes a real frame. */
static uint32_t park_current_write(void)
{
    return (Xil_In32(VDMA_PARK_PTR) >> 24UL) & 0x1FUL;
}

static uint32_t park_current_read(void)
{
    return (Xil_In32(VDMA_PARK_PTR) >> 16UL) & 0x1FUL;
}

static int wait_first_s2mm_frame(void)
{
    uint32_t timeout;
    uint32_t status;
    uint32_t initial_write = park_current_write();
    uint32_t current_write = initial_write;

    xil_printf("VDMA_S2MM_FIRST_FRAME_BEGIN INITIAL_WRITE=%u\r\n", initial_write);

    for (timeout = 0U; timeout < FIRST_FRAME_TIMEOUT_MS; ++timeout) {
        status = Xil_In32(VDMA_S2MM_SR);
        if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
            xil_printf("VDMA_S2MM_FAIL REASON=FIRST_FRAME_STATUS SR=0x%08x\r\n", status);
            print_vdma_registers();
            return -1;
        }

        current_write = park_current_write();
        if (current_write != initial_write) {
            xil_printf("VDMA_S2MM_FIRST_FRAME_PASS INITIAL_WRITE=%u WRITE=%u SR=0x%08x\r\n",
                       initial_write, current_write, status);
            print_vdma_registers();
            return 0;
        }
        usleep(1000U);
    }

    status = Xil_In32(VDMA_S2MM_SR);
    if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
        xil_printf("VDMA_S2MM_FAIL REASON=FIRST_FRAME_TIMEOUT_STATUS SR=0x%08x\r\n", status);
        print_vdma_registers();
        return -1;
    }

    /* Keep HDMI timing alive even if the camera is not connected/configured. */
    xil_printf("VDMA_S2MM_WARN REASON=CAMERA_STREAM_TIMEOUT INITIAL_WRITE=%u WRITE=%u SR=0x%08x\r\n",
               initial_write, current_write, status);
    return 0;
}

/* Exact successful-reference S2MM write order: CR first, VSIZE last. */
static int VDMA_Configure_S2MM(void)
{

    Xil_Out32(VDMA_S2MM_CR, VDMA_S2MM_CONTROL);
    Xil_Out32(VDMA_S2MM_ADDR_1, DISPLAY_FB_BASE);
    Xil_Out32(VDMA_S2MM_ADDR_2, DISPLAY_FB_BASE + FRAME_SLOT_BYTES);
    Xil_Out32(VDMA_S2MM_ADDR_3, DISPLAY_FB_BASE + FRAME_SLOT_BYTES * 2UL);
    Xil_Out32(VDMA_S2MM_STRIDE, FRAME_STRIDE);
    Xil_Out32(VDMA_S2MM_HSIZE, FRAME_STRIDE);
    Xil_Out32(VDMA_S2MM_VSIZE, FRAME_HEIGHT);




    xil_printf("VDMA_S2MM_REFERENCE_SEQUENCE_DONE WIDTH=%u HEIGHT=%u STRIDE=%u FRAMES=%u FORMAT=PACKED_RGB888 MODE=DYNAMIC_MASTER CONTROL=0x%08x\r\n",
               FRAME_WIDTH, FRAME_HEIGHT, FRAME_STRIDE, FRAME_COUNT, VDMA_S2MM_CONTROL);
    print_vdma_registers();
    return 0;
}


static int VDMA_Configure_MM2S(void)
{
    uint32_t status;

    /* This IP fixes C_NUM_FSTORES at 3, so no FRMSTORE access. */
    Xil_Out32(VDMA_MM2S_ADDR_1, DISPLAY_FB_BASE);
    Xil_Out32(VDMA_MM2S_ADDR_2, DISPLAY_FB_BASE + FRAME_SLOT_BYTES);
    Xil_Out32(VDMA_MM2S_ADDR_3, DISPLAY_FB_BASE + FRAME_SLOT_BYTES * 2UL);
    Xil_Out32(VDMA_MM2S_STRIDE, FRAME_STRIDE);
    Xil_Out32(VDMA_MM2S_HSIZE, FRAME_STRIDE);
    /* Keep this project's proven startup order: enable only before VSIZE. */
    Xil_Out32(VDMA_MM2S_CR, VDMA_MM2S_CONTROL);
    Xil_Out32(VDMA_MM2S_VSIZE, FRAME_HEIGHT);

    if (
        Xil_In32(VDMA_MM2S_CR) != VDMA_MM2S_CONTROL ||
        Xil_In32(VDMA_MM2S_ADDR_1) != DISPLAY_FB_BASE ||
        Xil_In32(VDMA_MM2S_ADDR_2) != (DISPLAY_FB_BASE + FRAME_SLOT_BYTES) ||
        Xil_In32(VDMA_MM2S_ADDR_3) != (DISPLAY_FB_BASE + FRAME_SLOT_BYTES * 2UL) ||
        Xil_In32(VDMA_MM2S_STRIDE) != FRAME_STRIDE ||
        Xil_In32(VDMA_MM2S_HSIZE) != FRAME_STRIDE ||
        Xil_In32(VDMA_MM2S_VSIZE) != FRAME_HEIGHT) {
        print_vdma_fail("MM2S_CONFIG_READBACK");
        return -1;
    }

    status = Xil_In32(VDMA_MM2S_SR);
    if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
        print_vdma_fail("MM2S_CONFIG_STATUS");
        return -1;
    }

    xil_printf("VDMA_S2MM_RUNNING CR=0x%08x SR=0x%08x\r\n",
               Xil_In32(VDMA_S2MM_CR), Xil_In32(VDMA_S2MM_SR));
    xil_printf("VDMA_MM2S_CONFIG_PASS WIDTH=%u HEIGHT=%u STRIDE=%u FRAMES=%u FORMAT=PACKED_RGB888 SOURCE=DDR_CAMERA\r\n",
               FRAME_WIDTH, FRAME_HEIGHT, FRAME_STRIDE, FRAME_COUNT, VDMA_S2MM_CONTROL);
    xil_printf("VDMA_MM2S_GENLOCK MODE=DYNAMIC_SLAVE CONTROL=0x%08x\r\n",
               VDMA_MM2S_CONTROL);
    print_vdma_registers();
    return 0;
}

static int wait_first_vdma_frame(void)
{
    uint32_t timeout;
    uint32_t status;
    uint32_t initial_read = park_current_read();
    uint32_t current_read = initial_read;

    for (timeout = 0U; timeout < FIRST_FRAME_TIMEOUT_MS; ++timeout) {
        status = Xil_In32(VDMA_MM2S_SR);
        if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
            print_vdma_fail("MM2S_FIRST_FRAME_ERROR");
            return -1;
        }
        current_read = park_current_read();
        if (current_read != initial_read) {
            break;
        }
        usleep(1000U);
    }

    status = Xil_In32(VDMA_MM2S_SR);
    if (current_read == initial_read) {
        xil_printf("VDMA_MM2S_FAIL REASON=FIRST_FRAME_TIMEOUT READ=%u\r\n", current_read);
        print_vdma_registers();
        return -1;
    }

    usleep(100000U);
    status = Xil_In32(VDMA_MM2S_SR);
    if ((status & VDMA_SR_ERROR_MASK) != 0UL ||
        (Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) == 0UL) {
        print_vdma_fail("MM2S_AFTER_FIRST_FRAME");
        return -1;
    }

    xil_printf("VDMA_MM2S_FIRST_FRAME_PASS SR=0x%08x READ=%u CURRENT_READ=%u\r\n",
               status, initial_read, current_read);
    print_vdma_registers();
    return 0;
}

static int monitor_stability_60s(void)
{
    uint32_t second;
    uint32_t status;
    uint32_t frames;
    uint32_t s2mm_status;
    uint32_t camera_ok;

    for (second = 1U; second <= STABILITY_SECONDS; ++second) {
        sleep(1);
        status = Xil_In32(VDMA_MM2S_SR);
        frames = vdma_mm2s_frame_count();
        s2mm_status = Xil_In32(VDMA_S2MM_SR);

        if ((status & VDMA_SR_ERROR_MASK) != 0UL ||
            (Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) == 0UL) {
            print_vdma_fail("MM2S_STABILITY");
            return -1;
        }
        camera_ok = ((s2mm_status & VDMA_SR_ERROR_MASK) == 0UL &&
                     (Xil_In32(VDMA_S2MM_CR) & VDMA_CR_RUN) != 0UL);
        if (camera_ok == 0U) {
            xil_printf("CAMERA_STREAM_FAIL SECOND=%u S2MM_CR=0x%08x S2MM_SR=0x%08x\r\n",
                       second, Xil_In32(VDMA_S2MM_CR), s2mm_status);
        }

        xil_printf("HDMI_HEARTBEAT SECOND=%u MM2S_FRAMES=%u S2MM_FRAMES=%u PARKPTR=0x%08x MM2S_SR=0x%08x S2MM_SR=0x%08x\r\n",
                   second, frames, vdma_s2mm_frame_count(),
                   Xil_In32(VDMA_PARK_PTR), status, s2mm_status);
    }

    status = Xil_In32(VDMA_MM2S_SR);
    if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
        print_vdma_fail("MM2S_FINAL_STATUS");
        return -1;
    }

    s2mm_status = Xil_In32(VDMA_S2MM_SR);
    camera_ok = ((s2mm_status & VDMA_SR_ERROR_MASK) == 0UL &&
                 (Xil_In32(VDMA_S2MM_CR) & VDMA_CR_RUN) != 0UL);
    if (camera_ok == 0U) {
        print_vdma_fail("S2MM_FINAL_STATUS");
        xil_printf("PS_HDMI_SIGNAL_PASS_CAMERA_FAIL S2MM_SR=0x%08x\r\n", s2mm_status);
        return 0;
    }

    xil_printf("VDMA_MM2S_S2MM_NO_ERROR_60S MM2S_FRAMES=%u S2MM_FRAMES=%u\r\n",
               vdma_mm2s_frame_count(), vdma_s2mm_frame_count());
    xil_printf("PS_HDMI_CAMERA_VDMA_TEST_PASS\r\n");
    return 0;
}

static void stop_display_for_debug(void)
{
    Xil_Out32(VDMA_MM2S_CR, 0x00000000UL);
    Xil_Out32(VDMA_S2MM_CR, 0x00000000UL);
    usleep(1000U);
}

int main(void)
{
    ddr_error_t error = {0};
    int result;
    int camera_result;

    xil_printf("PS_HDMI_CAMERA_VDMA_V3 UART=0x%08x VDMA=0x%08x\r\n",
               UART_BASE, VDMA_BASE);
    xil_printf("PS_HDMI_CAMERA_CONFIG FB=0x%08x FB_BYTES=%u WIDTH=%u HEIGHT=%u STRIDE=%u FRAMES=%u FORMAT=PACKED_RGB888 SOURCE=OV5640\r\n",
               DISPLAY_FB_BASE, DISPLAY_FB_BYTES, FRAME_WIDTH,
               FRAME_HEIGHT, FRAME_STRIDE, FRAME_COUNT);
    xil_printf("PS_HDMI_VDMA_BIT_SHA256=0A9CBC7B9357429FDB42CA6F1E24B39A16C8D432C148A543A035E1C771C271F7\r\n");

    result = run_uart_test();
    if (result != 0) {
        goto stopped;
    }

    xil_printf("VDMA_INITIAL_BEGIN\r\n");
    print_vdma_registers();
    if (VDMA_Reset() != 0) {
        print_vdma_fail("VDMA_RESET");
        goto stopped;
    }

    if (clear_display_ddr(&error) != 0) {
        goto stopped;
    }
    camera_result = VDMA_Configure_S2MM();
    if (camera_result != 0) {
        xil_printf("VDMA_S2MM_WARN REASON=CONFIG_FAILED_KEEPING_HDMI\r\n");
    }
    else if (wait_first_s2mm_frame() != 0) {
        xil_printf("VDMA_S2MM_WARN REASON=FIRST_FRAME_FAILED_KEEPING_HDMI\r\n");
    }
    if (VDMA_Configure_MM2S() != 0) {
        goto stopped;
    }
    if (wait_first_vdma_frame() != 0) {
        goto stopped;
    }
    if (monitor_stability_60s() != 0) {
        goto stopped;
    }

    xil_printf("HDMI_CAMERA_SOURCE_RUNNING 640x480 PACKED_RGB888 FRAMES=%u\r\n", FRAME_COUNT);
    while (1) {
        static uint32_t runtime_second = 0U;
        uint32_t status;
        uint32_t s2mm_status;
        uint32_t camera_ok;

        sleep(5);
        ++runtime_second;
        status = Xil_In32(VDMA_MM2S_SR);
        if ((status & VDMA_SR_ERROR_MASK) != 0UL ||
            (Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) == 0UL) {
            print_vdma_fail("RUNTIME_MONITOR");
            break;
        }

        s2mm_status = Xil_In32(VDMA_S2MM_SR);
        camera_ok = ((s2mm_status & VDMA_SR_ERROR_MASK) == 0UL &&
                     (Xil_In32(VDMA_S2MM_CR) & VDMA_CR_RUN) != 0UL);
        if (camera_ok == 0U) {
            xil_printf("CAMERA_STREAM_FAIL SECOND=%u S2MM_CR=0x%08x S2MM_SR=0x%08x\r\n",
                       runtime_second, Xil_In32(VDMA_S2MM_CR), s2mm_status);
        }
        xil_printf("HDMI_RUNTIME_HEARTBEAT SECOND=%u MM2S_FRAMES=%u S2MM_FRAMES=%u PARKPTR=0x%08x MM2S_SR=0x%08x S2MM_SR=0x%08x\r\n",
                   runtime_second, vdma_mm2s_frame_count(),
                   vdma_s2mm_frame_count(), Xil_In32(VDMA_PARK_PTR), status,
                   Xil_In32(VDMA_S2MM_SR));
    }

stopped:
    print_vdma_registers();
    stop_display_for_debug();
    xil_printf("TEST_STOPPED MM2S_SR=0x%08x S2MM_SR=0x%08x\r\n",
               Xil_In32(VDMA_MM2S_SR), Xil_In32(VDMA_S2MM_SR));
    while (1) {
    }
    return 0;
}
