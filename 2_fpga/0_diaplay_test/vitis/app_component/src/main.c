#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#define DDR_TEST_BASE            0x10000000UL
#define DDR_TEST_BYTES           0x00300000UL
#define DDR_TEST_WORDS           (DDR_TEST_BYTES / 4UL)

#define FRAME_COUNT              3UL
#define FRAME_SPACING            0x00100000UL
#define FRAME_WIDTH              640UL
#define FRAME_HEIGHT             480UL
#define FRAME_BYTES              (FRAME_WIDTH * FRAME_HEIGHT * 3UL)
#define FRAME_PIXELS             (FRAME_WIDTH * FRAME_HEIGHT)
#define FRAME_STRIDE             (FRAME_WIDTH * 3UL)

#define VDMA_BASE                XPAR_AXI_VDMA_0_BASEADDR
#define VDMA_MM2S_CR             (VDMA_BASE + 0x00000000UL)
#define VDMA_MM2S_SR             (VDMA_BASE + 0x00000004UL)
#define VDMA_MM2S_VSIZE          (VDMA_BASE + 0x00000050UL)
#define VDMA_MM2S_HSIZE          (VDMA_BASE + 0x00000054UL)
#define VDMA_MM2S_STRIDE         (VDMA_BASE + 0x00000058UL)
#define VDMA_MM2S_ADDR_1         (VDMA_BASE + 0x0000005CUL)
#define VDMA_MM2S_ADDR_2         (VDMA_BASE + 0x00000060UL)
#define VDMA_MM2S_ADDR_3         (VDMA_BASE + 0x00000064UL)
#define VDMA_S2MM_CR             (VDMA_BASE + 0x00000030UL)
#define VDMA_S2MM_SR             (VDMA_BASE + 0x00000034UL)

#define VDMA_CR_RUN              0x00000001UL
#define VDMA_CR_CIRCULAR         0x00000002UL
#define VDMA_CR_RESET            0x00000004UL
#define VDMA_CR_FRAME_COUNT      0x00000010UL
#define VDMA_CR_FRAME_COUNT_ONE  (1UL << 16UL)
#define VDMA_SR_ERROR_MASK       0x00000FF0UL
#define VDMA_SR_IRQ_MASK         0x00007000UL
#define VDMA_SR_HALTED           0x00000001UL
#define VDMA_SR_FRAME_COUNT_SHIFT 16UL

typedef struct {
    uint32_t bad_address;
    uint32_t expected;
    uint32_t actual;
    uint32_t pattern;
    uint32_t round;
} ddr_error_t;

static uint32_t ddr_pattern(uint32_t index, uint32_t pattern)
{
    switch (pattern) {
        case 0U:  return 0x00000000UL;
        case 1U:  return 0xFFFFFFFFUL;
        case 2U:  return 0xAAAAAAAAUL;
        case 3U:  return 0x5555AAAAUL;
        case 4U:  return (DDR_TEST_BASE + index * 4UL) ^ 0xA5A5A5A5UL;
        default:  return index ^ (index << 7UL) ^ 0x13579BDFUL;
    }
}

static void print_ddr_error(const char *phase, const ddr_error_t *error)
{
    xil_printf("DDR_FAIL PHASE=%s PATTERN=%u ROUND=%u ADDR=0x%08x EXP=0x%08x ACT=0x%08x\r\n",
               phase, error->pattern, error->round,
               error->bad_address, error->expected, error->actual);
}

static int run_ddr_write_read(ddr_error_t *error)
{
    volatile uint32_t *memory = (volatile uint32_t *)(uintptr_t)DDR_TEST_BASE;
    uint32_t pattern;
    uint32_t round;
    uint32_t index;

    for (pattern = 0U; pattern < 6U; ++pattern) {
        for (round = 0U; round < 3U; ++round) {
            xil_printf("DDR_ROUND PATTERN=%u ROUND=%u\r\n", pattern, round);
            for (index = 0U; index < DDR_TEST_WORDS; ++index) {
                memory[index] = ddr_pattern(index, pattern);
            }
            Xil_DCacheFlushRange(DDR_TEST_BASE, DDR_TEST_BYTES);
            Xil_DCacheInvalidateRange(DDR_TEST_BASE, DDR_TEST_BYTES);

            for (index = 0U; index < DDR_TEST_WORDS; ++index) {
                uint32_t actual = memory[index];
                uint32_t expected = ddr_pattern(index, pattern);
                if (actual != expected) {
                    error->bad_address = DDR_TEST_BASE + index * 4UL;
                    error->expected = expected;
                    error->actual = actual;
                    error->pattern = pattern;
                    error->round = round;
                    return -1;
                }
            }
        }
    }
    return 0;
}

static int run_ddr_hold_test(uint32_t seconds, ddr_error_t *error)
{
    volatile uint32_t *memory = (volatile uint32_t *)(uintptr_t)DDR_TEST_BASE;
    uint32_t index;
    uint32_t elapsed;

    xil_printf("DDR_HOLD_BEGIN SECONDS=%u\r\n", seconds);
    for (index = 0U; index < DDR_TEST_WORDS; ++index) {
        memory[index] = ddr_pattern(index, 4U);
    }
    Xil_DCacheFlushRange(DDR_TEST_BASE, DDR_TEST_BYTES);

    for (elapsed = 1U; elapsed <= seconds; ++elapsed) {
        sleep(1);
        Xil_DCacheInvalidateRange(DDR_TEST_BASE, DDR_TEST_BYTES);
        for (index = 0U; index < DDR_TEST_WORDS; ++index) {
            uint32_t actual = memory[index];
            uint32_t expected = ddr_pattern(index, 4U);
            if (actual != expected) {
                error->bad_address = DDR_TEST_BASE + index * 4UL;
                error->expected = expected;
                error->actual = actual;
                error->pattern = 4U;
                error->round = elapsed;
                print_ddr_error("HOLD", error);
                return -1;
            }
        }
        xil_printf("DDR_HOLD_OK SECOND=%u\r\n", elapsed);
    }
    return 0;
}

static void fill_colorbars(void)
{
    static const uint8_t colors[8][3] = {
        {0xFFU, 0xFFU, 0xFFU}, {0xFFU, 0xFFU, 0x00U},
        {0x00U, 0xFFU, 0xFFU}, {0x00U, 0xFFU, 0x00U},
        {0xFFU, 0x00U, 0xFFU}, {0xFFU, 0x00U, 0x00U},
        {0x00U, 0x00U, 0xFFU}, {0x00U, 0x00U, 0x00U},
    };
    uint8_t *memory = (uint8_t *)(uintptr_t)DDR_TEST_BASE;
    uint32_t frame;
    uint32_t row;
    uint32_t column;
    uint32_t channel;

    for (frame = 0U; frame < FRAME_COUNT; ++frame) {
        uint8_t *destination = memory + frame * FRAME_SPACING;
        for (row = 0U; row < FRAME_HEIGHT; ++row) {
            for (column = 0U; column < FRAME_WIDTH; ++column) {
                const uint8_t *color = colors[column / (FRAME_WIDTH / 8U)];
                for (channel = 0U; channel < 3U; ++channel) {
                    destination[(row * FRAME_WIDTH + column) * 3UL + channel] =
                        color[channel];
                }
            }
        }
    }
    Xil_DCacheFlushRange(DDR_TEST_BASE, FRAME_SPACING * FRAME_COUNT);
}

static int verify_colorbars(void)
{
    static const uint8_t expected[8][3] = {
        {0xFFU, 0xFFU, 0xFFU}, {0xFFU, 0xFFU, 0x00U},
        {0x00U, 0xFFU, 0xFFU}, {0x00U, 0xFFU, 0x00U},
        {0xFFU, 0x00U, 0xFFU}, {0xFFU, 0x00U, 0x00U},
        {0x00U, 0x00U, 0xFFU}, {0x00U, 0x00U, 0x00U},
    };
    const uint8_t *memory = (const uint8_t *)(uintptr_t)DDR_TEST_BASE;
    uint32_t frame;
    uint32_t bar;
    uint32_t row;

    Xil_DCacheInvalidateRange(DDR_TEST_BASE, FRAME_SPACING * FRAME_COUNT);
    for (frame = 0U; frame < FRAME_COUNT; ++frame) {
        for (bar = 0U; bar < 8U; ++bar) {
            uint32_t column = bar * 80UL + 40UL;
            for (row = 0U; row < FRAME_HEIGHT; row += 240U) {
                uintptr_t offset = frame * FRAME_SPACING +
                                   row * FRAME_STRIDE + column * 3UL;
                if (memory[offset + 0UL] != expected[bar][0] ||
                    memory[offset + 1UL] != expected[bar][1] ||
                    memory[offset + 2UL] != expected[bar][2]) {
                    xil_printf("COLORBAR_FAIL FRAME=%u ROW=%u BAR=%u\r\n",
                               frame, row, bar);
                    return -1;
                }
            }
        }
    }
    return 0;
}

static void vdma_reset_channel(uint32_t control_register)
{
    Xil_Out32(control_register, VDMA_CR_RESET);
    while ((Xil_In32(control_register) & VDMA_CR_RESET) != 0UL) {
    }
}

static uint32_t vdma_frame_count(void)
{
    return (Xil_In32(VDMA_MM2S_SR) >> VDMA_SR_FRAME_COUNT_SHIFT) & 0xFFUL;
}

static void vdma_print_registers(void)
{
    xil_printf("VDMA_REG MM2S_CR=0x%08x MM2S_SR=0x%08x ADDR1=0x%08x STRIDE=0x%08x HSIZE=0x%08x VSIZE=0x%08x\r\n",
               Xil_In32(VDMA_MM2S_CR), Xil_In32(VDMA_MM2S_SR),
               Xil_In32(VDMA_MM2S_ADDR_1), Xil_In32(VDMA_MM2S_STRIDE),
               Xil_In32(VDMA_MM2S_HSIZE), Xil_In32(VDMA_MM2S_VSIZE));
}

static int run_vdma_hdmi_test(void)
{
    uint32_t status;
    uint32_t frame_count;
    uint32_t timeout;

    vdma_reset_channel(VDMA_S2MM_CR);
    Xil_Out32(VDMA_S2MM_SR, VDMA_SR_ERROR_MASK | VDMA_SR_IRQ_MASK);
    vdma_reset_channel(VDMA_MM2S_CR);
    Xil_Out32(VDMA_MM2S_SR, VDMA_SR_ERROR_MASK | VDMA_SR_IRQ_MASK);
    xil_printf("VDMA_RESET_OK\r\n");

    fill_colorbars();
    if (verify_colorbars() != 0) {
        xil_printf("VDMA_MM2S_FAIL REASON=COLORBAR_VERIFY\r\n");
        return -1;
    }
    xil_printf("COLORBAR_FILLED FRAMES=%u BASE=0x%08x BYTES=%u\r\n",
               FRAME_COUNT, DDR_TEST_BASE, FRAME_BYTES);

    Xil_Out32(VDMA_MM2S_ADDR_1, DDR_TEST_BASE);
    Xil_Out32(VDMA_MM2S_ADDR_2, DDR_TEST_BASE + FRAME_SPACING);
    Xil_Out32(VDMA_MM2S_ADDR_3, DDR_TEST_BASE + FRAME_SPACING * 2UL);
    Xil_Out32(VDMA_MM2S_STRIDE, FRAME_STRIDE);
    Xil_Out32(VDMA_MM2S_HSIZE, FRAME_STRIDE);
    Xil_Out32(VDMA_MM2S_CR, VDMA_CR_RUN | VDMA_CR_FRAME_COUNT | VDMA_CR_FRAME_COUNT_ONE);
    Xil_Out32(VDMA_MM2S_VSIZE, FRAME_HEIGHT);
    xil_printf("VDMA_MM2S_ONE_FRAME_START WIDTH=%u HEIGHT=%u STRIDE=%u\r\n",
               FRAME_WIDTH, FRAME_HEIGHT, FRAME_STRIDE);
    vdma_print_registers();

    for (timeout = 0U; timeout < 5000U; ++timeout) {
        status = Xil_In32(VDMA_MM2S_SR);
        frame_count = vdma_frame_count();
        if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
            break;
        }
        if (frame_count >= 1UL && (Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) == 0UL) {
            break;
        }
        usleep(1000U);
    }

    status = Xil_In32(VDMA_MM2S_SR);
    frame_count = vdma_frame_count();
    xil_printf("VDMA_ONE_FRAME SR=0x%08x COUNT=%u ERR=0x%08x\r\n",
               status, frame_count, status & VDMA_SR_ERROR_MASK);

    if (frame_count != 1UL || (status & VDMA_SR_ERROR_MASK) != 0UL) {
        xil_printf("VDMA_MM2S_FAIL REASON=ONE_FRAME\r\n");
        vdma_print_registers();
        return -1;
    }

    if (verify_colorbars() != 0) {
        xil_printf("VDMA_MM2S_FAIL REASON=SOURCE_AFTER_STREAM\r\n");
        return -1;
    }

    if ((status & VDMA_SR_HALTED) == 0UL &&
        (Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) != 0UL) {
        xil_printf("VDMA_MM2S_FAIL REASON=ONE_FRAME_NOT_HALTED\r\n");
        vdma_print_registers();
        return -1;
    }

    xil_printf("VDMA_ONE_FRAME_PASS\r\n");
    xil_printf("VDMA_STREAM_EVIDENCE SOURCE_BYTES=%u AXIS_WORDS=%u\r\n",
               FRAME_BYTES, FRAME_PIXELS);
    xil_printf("M_AXIS_MM2S_FRAME_DELIVERED SOURCE=PS_DDR FRAME_COUNT=1 ERR=0\r\n");

    vdma_reset_channel(VDMA_MM2S_CR);
    Xil_Out32(VDMA_MM2S_SR, VDMA_SR_ERROR_MASK | VDMA_SR_IRQ_MASK);
    Xil_Out32(VDMA_MM2S_ADDR_1, DDR_TEST_BASE);
    Xil_Out32(VDMA_MM2S_ADDR_2, DDR_TEST_BASE + FRAME_SPACING);
    Xil_Out32(VDMA_MM2S_ADDR_3, DDR_TEST_BASE + FRAME_SPACING * 2UL);
    Xil_Out32(VDMA_MM2S_STRIDE, FRAME_STRIDE);
    Xil_Out32(VDMA_MM2S_HSIZE, FRAME_STRIDE);
    Xil_Out32(VDMA_MM2S_CR, VDMA_CR_RUN | VDMA_CR_CIRCULAR);
    Xil_Out32(VDMA_MM2S_VSIZE, FRAME_HEIGHT);
    usleep(100000U);
    status = Xil_In32(VDMA_MM2S_SR);
    xil_printf("VDMA_CONTINUOUS SR=0x%08x CR=0x%08x\r\n",
               status, Xil_In32(VDMA_MM2S_CR));
    if ((Xil_In32(VDMA_MM2S_CR) & VDMA_CR_RUN) == 0UL ||
        (status & VDMA_SR_ERROR_MASK) != 0UL) {
        xil_printf("VDMA_MM2S_FAIL REASON=CONTINUOUS\r\n");
        vdma_print_registers();
        return -1;
    }

    xil_printf("VDMA_MM2S_PASS\r\n");
    xil_printf("HDMI_COLORBAR_RUNNING CHECK_640x480_RGB888\r\n");
    return 0;
}

int main(void)
{
    ddr_error_t error = {0};

    xil_printf("V1_PLATFORM_OK UART_STDOUT=0xE0001000\r\n");
    xil_printf("DDR_TEST_BEGIN BASE=0x%08x BYTES=%u\r\n",
               DDR_TEST_BASE, DDR_TEST_BYTES);
    if (run_ddr_write_read(&error) != 0) {
        print_ddr_error("WRITE_READ", &error);
        goto stopped;
    }
    if (run_ddr_hold_test(30U, &error) != 0) {
        goto stopped;
    }
    xil_printf("DDR_PASS\r\n");

    if (run_vdma_hdmi_test() != 0) {
        goto stopped;
    }

    while (1) {
        static uint32_t heartbeat = 0U;
        uint32_t status = Xil_In32(VDMA_MM2S_SR);

        if ((status & VDMA_SR_ERROR_MASK) != 0UL) {
            xil_printf("HDMI_COLORBAR_FAIL SR=0x%08x\r\n", status);
            break;
        }
        ++heartbeat;
        xil_printf("HDMI_HEARTBEAT=%u FRAMES=%u SR=0x%08x\r\n",
                   heartbeat, vdma_frame_count(), status);
        sleep(5);
    }

stopped:
    xil_printf("TEST_STOPPED\r\n");
    while (1) {
    }
    return 0;
}
