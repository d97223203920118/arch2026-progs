#include "gcd.h"

/* Count trailing zeros by binary search; x must be nonzero. RV32I has no
 * ctz instruction, and __builtin_ctz would call the missing __ctzsi2.
 */
static inline unsigned ctz32(uint32_t x)
{
    unsigned n = 0;
    if (!(x & 0xFFFFu)) {
        n += 16;
        x >>= 16;
    }
    if (!(x & 0xFFu)) {
        n += 8;
        x >>= 8;
    }
    if (!(x & 0xFu)) {
        n += 4;
        x >>= 4;
    }
    if (!(x & 0x3u)) {
        n += 2;
        x >>= 2;
    }
    if (!(x & 0x1u))
        n += 1;
    return n;
}

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    /* Common factors of two: trailing zeros shared by a and b. */
    unsigned shift = ctz32(a | b);

    a >>= ctz32(a); /* a is odd from here on */
    do {
        b >>= ctz32(b); /* make b odd */
        if (a > b) {    /* keep a <= b */
            uint32_t t = a;
            a = b;
            b = t;
        }
        b -= a; /* odd - odd = even, so the next pass shifts again */
    } while (b != 0);

    return a << shift;
}
