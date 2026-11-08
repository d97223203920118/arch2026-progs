#include "fixed.h"

/* Bitwise adder: a ^ b is the sum without carries and (a & b) << 1 is
 * the carry word. The carry moves left at least one bit per pass, so the
 * loop ends within 32 passes.
 */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b) {
        uint32_t c = (a & b) << 1;
        a ^= b;
        b = c;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

/* floor((a + b) / 2) without overflow: the shared bits count fully, the
 * bits set in only one operand count half.
 */
uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

/* Q11.20 multiply. The signed 64-bit product is built from four 16-bit
 * partial products, since RV32I has no multiply and the runtime offers
 * __mulsi3 but not __muldi3. Only bits 20 to 51 of the rounded product
 * are kept, so no 64-bit arithmetic shift is needed.
 */
int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFFu, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFFu, bh = ub >> 16;

    uint32_t ll = al * bl;
    uint32_t lh = al * bh;
    uint32_t hl = ah * bl;
    uint32_t hh = ah * bh;

    /* Unsigned 64-bit product hi:lo. */
    uint32_t mid = (ll >> 16) + (lh & 0xFFFFu) + (hl & 0xFFFFu);
    uint32_t lo = (ll & 0xFFFFu) | (mid << 16);
    uint32_t hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16);

    /* Signed correction of the high word. */
    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    /* Add half a unit, 2^19, with carry into the high word. */
    uint32_t r = lo + (1u << (Q - 1));
    hi += (lo >= 0xFFF80000u); /* lo + 2^19 carries out */

    /* Bits 20..51 of the 64-bit sum. */
    return (int32_t) ((r >> Q) | (hi << (32 - Q)));
}
