#include "bf16.h"

#define BF16_QNAN 0x7FC0u
#define BF16_INF 0x7F80u

/* Round to nearest, ties to even: adding 0x7FFF plus the lowest kept bit
 * carries into bit 16 exactly when the dropped half exceeds one half, or
 * equals one half and the kept value is odd. Inf and NaN pass unchanged.
 */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFFu) == 0xFFu)
        return (uint16_t) (f32bits >> 16);
    f32bits += 0x7FFFu + ((f32bits >> 16) & 1u);
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t exp_a = (a >> 7) & 0xFFu, exp_b = (b >> 7) & 0xFFu;
    uint32_t mant_a = a & 0x7Fu, mant_b = b & 0x7Fu;
    uint32_t sign = ((uint32_t) a ^ (uint32_t) b) & 0x8000u;

    /* a is examined first, so an infinite a swallows a NaN b. */
    if (exp_a == 0xFFu) {
        if (mant_a)
            return a;
        if (!exp_b && !mant_b)
            return BF16_QNAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if (exp_b == 0xFFu) {
        if (mant_b)
            return b;
        if (!exp_a && !mant_a)
            return BF16_QNAN;
        return (uint16_t) (sign | BF16_INF);
    }
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return (uint16_t) sign;

    /* Normalize denormals so that bit 7 holds the leading one. */
    int32_t exp_adjust = 0;
    if (!exp_a) {
        while (!(mant_a & 0x80u)) {
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1;
    } else {
        mant_a |= 0x80u;
    }
    if (!exp_b) {
        while (!(mant_b & 0x80u)) {
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1;
    } else {
        mant_b |= 0x80u;
    }

    /* 8-bit by 8-bit product in [2^14, 2^16); the fraction is truncated. */
    uint32_t prod = mant_a * mant_b;
    int32_t exp = (int32_t) exp_a + (int32_t) exp_b - 127 + exp_adjust;
    uint32_t frac;
    if (prod & 0x8000u) {
        frac = (prod >> 8) & 0x7Fu;
        exp++;
    } else {
        frac = (prod >> 7) & 0x7Fu;
    }

    if (exp >= 0xFF)
        return (uint16_t) (sign | BF16_INF);
    if (exp <= 0) {
        if (exp < -6)
            return (uint16_t) sign;
        frac >>= 1 - exp; /* the 7-bit fraction, as the contract states */
        exp = 0;
    }
    return (uint16_t) (sign | ((uint32_t) exp << 7) | frac);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exp = (a >> 7) & 0xFFu, mant = a & 0x7Fu;

    if (exp == 0xFFu) {
        if (mant)
            return a; /* NaN */
        if (a & 0x8000u)
            return BF16_QNAN; /* -Inf */
        return a;             /* +Inf */
    }
    if (!exp && !mant)
        return 0; /* +0 and -0 give +0 */
    if (a & 0x8000u)
        return BF16_QNAN; /* negative nonzero */
    if (!exp)
        return 0; /* denormals give +0 */

    /* With e = exp - 127, an odd e (even exp) doubles the significand,
     * and either way the new exponent field is (exp + 127) / 2 rounded
     * down, which avoids shifting a negative value.
     */
    uint32_t m = 0x80u | mant;
    uint32_t new_exp = (exp + 127) >> 1;
    if (!(exp & 1u))
        m <<= 1;

    /* Largest mid in [90, 256] with (mid * mid) / 128 <= m. */
    uint32_t low = 90, high = 256, result = 128;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if ((mid * mid) / 128 <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /* m lies in [128, 510], so result lies in [128, 255] and needs no
     * renormalization, and new_exp lies in [63, 190], far from both Inf
     * and zero.
     */
    return (uint16_t) ((new_exp << 7) | (result & 0x7Fu));
}
