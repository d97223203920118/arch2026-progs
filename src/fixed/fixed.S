# Arithmetic built from logic and Q11.20 fixed point for RV32I.
# All four functions are leaf functions that use only a and t
# registers, so none touches the stack.

# MUL16 rd, x, y, tmp: rd = x * y for x, y below 2^16, by shift and add,
# two multiplier bits per pass, stopping as soon as y runs out of bits.
# x and y are clobbered.
    .macro  MUL16 rd, x, y, tmp
    li      \rd, 0
    beqz    \y, 3f
1:  andi    \tmp, \y, 1
    beqz    \tmp, 2f
    add     \rd, \rd, \x
2:  andi    \tmp, \y, 2
    beqz    \tmp, 4f
    slli    \tmp, \x, 1
    add     \rd, \rd, \tmp
4:  slli    \x, \x, 2
    srli    \y, \y, 2
    bnez    \y, 1b
3:
    .endm

    .text

# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)
# Carry loop of a bitwise adder, unrolled twice: each pass sets
# c = (a & b) << 1, a = a ^ b, b = c, and *n receives the pass count.
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t1, 0                   # pass count
    beqz    a1, 3f                  # no carry: zero passes
1:  and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    beqz    a1, 2f                  # ended after an odd pass
    and     t0, a0, a1
    xor     a0, a0, a1
    slli    a1, t0, 1
    addi    t1, t1, 2
    bnez    a1, 1b
    j       3f
2:  addi    t1, t1, 1
3:  sw      t1, 0(a2)
    ret
    .size   op1_asm, . - op1_asm

# uint32_t op2_asm(uint32_t a, uint32_t b): a - b modulo 2^32
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, . - op2_asm

# uint32_t op3_asm(uint32_t a, uint32_t b): floor((a + b) / 2) without
# overflow, as (a & b) + ((a ^ b) >> 1).
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, . - op3_asm

# int32_t q_mul_asm(int32_t a, int32_t b)
# Unsigned 64-bit product from four inline 16x16 products, signed
# correction of the high word, plus 2^19, then bits 20..51.
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    slli    a2, a0, 16
    srli    a2, a2, 16              # al
    srli    a3, a0, 16              # ah
    slli    a4, a1, 16
    srli    a4, a4, 16              # bl
    srli    a5, a1, 16              # bh

    mv      a6, a2
    mv      a7, a4
    MUL16   t3, a6, a7, t0          # ll = al * bl
    mv      a6, a2
    mv      a7, a5
    MUL16   t4, a6, a7, t0          # lh = al * bh
    mv      a6, a3
    mv      a7, a4
    MUL16   t5, a6, a7, t0          # hl = ah * bl
    mv      a6, a3
    mv      a7, a5
    MUL16   t6, a6, a7, t0          # hh = ah * bh

    # mid = (ll >> 16) + (lh & 0xFFFF) + (hl & 0xFFFF)
    srli    t1, t3, 16
    slli    t2, t4, 16
    srli    t2, t2, 16
    add     t1, t1, t2
    slli    t2, t5, 16
    srli    t2, t2, 16
    add     t1, t1, t2
    # lo = (ll & 0xFFFF) | (mid << 16)
    slli    t2, t3, 16
    srli    t2, t2, 16
    slli    a6, t1, 16
    or      a6, a6, t2
    # hi = hh + (lh >> 16) + (hl >> 16) + (mid >> 16)
    srli    t2, t4, 16
    add     t6, t6, t2
    srli    t2, t5, 16
    add     t6, t6, t2
    srli    t2, t1, 16
    add     t6, t6, t2

    # signed correction: a < 0 subtracts b, b < 0 subtracts a
    bgez    a0, 5f
    sub     t6, t6, a1
5:  bgez    a1, 6f
    sub     t6, t6, a0
6:
    # add half a unit, 2^19, with carry into the high word
    li      t2, 0x80000
    add     a7, a6, t2
    sltu    t2, a7, a6              # carry out of the low word
    add     t6, t6, t2

    # bits 20..51 of the 64-bit sum
    srli    a0, a7, 20
    slli    t6, t6, 12
    or      a0, a0, t6
    ret
    .size   q_mul_asm, . - q_mul_asm
