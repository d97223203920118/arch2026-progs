# BFloat16 narrowing, multiply and square root for RV32I.
# Leaf functions using only a and t registers; no multiply instruction,
# no runtime helper, no stack.

    .text

# uint16_t bf16_from_f32_asm(uint32_t f32bits)
# Exponent 0xFF passes the top half unchanged; otherwise add 0x7FFF plus
# bit 16 (round to nearest, ties to even) and keep the top half.
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    slli    t0, a0, 1               # drop the sign: exponent in bits 31..24
    lui     t1, 0xFF000             # 0xFF000000
    bgeu    t0, t1, 1f              # exponent 0xFF: Inf or NaN
    srli    t2, a0, 16
    andi    t2, t2, 1               # lowest kept bit
    add     a0, a0, t2
    lui     t1, 8
    addi    t1, t1, -1              # 0x7FFF
    add     a0, a0, t1
1:  srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, . - bf16_from_f32_asm

# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)
# t0/t1 exponents, t2/t3 significands, t6 sign, a2 product, a3 exponent.
    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t6, a0, a1
    srli    t6, t6, 15
    slli    t6, t6, 15              # product sign
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exponent of a
    andi    t2, a0, 0x7F            # fraction of a
    srli    t1, a1, 7
    andi    t1, t1, 0xFF            # exponent of b
    andi    t3, a1, 0x7F            # fraction of b
    li      t4, 0xFF
    beq     t0, t4, .Lmul_a_special # a first, as the contract orders
    beq     t1, t4, .Lmul_b_special
    or      t5, t0, t2
    beqz    t5, .Lmul_ret_sign      # a is zero
    or      t5, t1, t3
    beqz    t5, .Lmul_ret_sign      # b is zero

    # normalize a: a denormal shifts up until bit 7 is set, and its
    # exponent counts down from 1
    bnez    t0, 2f
    li      t0, 1
1:  slli    t2, t2, 1
    addi    t0, t0, -1
    andi    t5, t2, 0x80
    beqz    t5, 1b
    j       3f
2:  ori     t2, t2, 0x80            # implicit one
3:
    # normalize b the same way
    bnez    t1, 5f
    li      t1, 1
4:  slli    t3, t3, 1
    addi    t1, t1, -1
    andi    t5, t3, 0x80
    beqz    t5, 4b
    j       6f
5:  ori     t3, t3, 0x80
6:
    # 8-bit by 8-bit product, fully unrolled shift and add. Bit 7 of b
    # is always set, so start from a << 7 and add the lower bits.
    slli    a2, t2, 7
    andi    t5, t3, 1
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 2
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 4
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 8
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 16
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 32
    beqz    t5, 7f
    add     a2, a2, t2
7:  slli    t2, t2, 1
    andi    t5, t3, 64
    beqz    t5, 7f
    add     a2, a2, t2
7:
    # exponent = ea + eb - 127; a product reaching bit 15 shifts one
    # more and bumps the exponent (k = prod >> 15 is 0 or 1)
    add     a3, t0, t1
    addi    a3, a3, -127
    srli    t5, a2, 15
    add     a3, a3, t5
    addi    t5, t5, 7
    srl     a2, a2, t5
    andi    a2, a2, 0x7F            # truncated fraction

    bge     a3, t4, .Lmul_ret_inf   # exponent >= 0xFF
    blez    a3, .Lmul_small
    slli    a3, a3, 7
    or      a0, t6, a3
    or      a0, a0, a2
    ret
.Lmul_small:                        # exponent <= 0
    li      t5, -6
    blt     a3, t5, .Lmul_ret_sign  # below -6: signed zero
    li      t5, 1
    sub     t5, t5, a3
    srl     a2, a2, t5              # shift the 7-bit fraction 1 - e bits
    or      a0, t6, a2
    ret
.Lmul_ret_sign:
    mv      a0, t6
    ret
.Lmul_ret_inf:
    li      t5, 0x7F80
    or      a0, t6, t5
    ret
.Lmul_a_special:                    # exponent of a is 0xFF
    bnez    t2, .Lmul_ret_self      # NaN a returned unchanged
    or      t5, t1, t3
    beqz    t5, .Lmul_ret_nan       # Inf times zero
    j       .Lmul_ret_inf           # Inf, whatever b is
.Lmul_b_special:                    # exponent of b is 0xFF
    bnez    t3, .Lmul_ret_b         # NaN b returned unchanged
    or      t5, t0, t2
    beqz    t5, .Lmul_ret_nan
    j       .Lmul_ret_inf
.Lmul_ret_b:
    mv      a0, a1
.Lmul_ret_self:
    ret
.Lmul_ret_nan:
    li      a0, 0x7FC0
    ret
    .size   bf16_mul_asm, . - bf16_mul_asm

# uint16_t bf16_sqrt_asm(uint16_t a)
# The largest r with (r * r) / 128 <= m is the integer square root of
# 128 * m + 127, found digit by digit with no multiply.
    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF            # exponent field
    andi    t1, a0, 0x7F            # fraction
    li      t2, 0xFF
    beq     t0, t2, .Lsq_special
    or      t3, t0, t1
    beqz    t3, .Lsq_ret_zero       # +0 and -0 give +0
    srli    t3, a0, 15
    bnez    t3, .Lsq_ret_nan        # negative nonzero
    beqz    t0, .Lsq_ret_zero       # denormals give +0

    ori     t1, t1, 0x80            # m = significand
    addi    t2, t0, 127
    srli    t2, t2, 1               # new exponent field = (exp + 127) / 2
    andi    t3, t0, 1
    bnez    t3, 1f
    slli    t1, t1, 1               # even field = odd exponent: double m
1:
    slli    t1, t1, 7
    addi    t1, t1, 127             # N = 128 * m + 127, below 2^16

    # digit-by-digit integer square root of N: t1 = N, t4 = root,
    # t3 = current bit, starting at 4^7
    li      t4, 0
    lui     t3, 4                   # 1 << 14
2:  add     t5, t4, t3
    bltu    t1, t5, 3f
    sub     t1, t1, t5
    srli    t4, t4, 1
    add     t4, t4, t3
    j       4f
3:  srli    t4, t4, 1
4:  srli    t3, t3, 2
    bnez    t3, 2b

    # the root lies in [128, 255], so only the fraction bits are kept
    andi    t4, t4, 0x7F
    slli    t2, t2, 7
    or      a0, t2, t4
    ret
.Lsq_special:                       # exponent 0xFF
    bnez    t1, .Lsq_ret_self       # NaN unchanged
    srli    t3, a0, 15
    bnez    t3, .Lsq_ret_nan        # -Inf
.Lsq_ret_self:
    ret                             # +Inf unchanged
.Lsq_ret_zero:
    li      a0, 0
    ret
.Lsq_ret_nan:
    li      a0, 0x7FC0
    ret
    .size   bf16_sqrt_asm, . - bf16_sqrt_asm
