# Binary GCD for RV32I, no multiply or divide.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)
#   a0 = a, a1 = b, result in a0. Leaf function: uses only a0-a1 and
#   t0-t5, no stack.
#
# 1. gcd(0, b) = b and gcd(a, 0) = a.
# 2. k = ctz(a | b) counts the factors of two shared by a and b; it is
#    found once by binary search and both operands are shifted right by k.
# 3. The remaining zeros are stripped one bit at a time: on average the
#    difference has only one or two of them, so a 3-instruction loop beats
#    a full binary search on every pass.
# 4. With a and b odd, a branchless step sets a = min(a, b) and
#    b = |b - a|, which is even, then the loop strips it again.
# 5. The result is a << k.

    .text
    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz    a0, .Lret_b             # gcd(0, b) = b
    beqz    a1, .Ldone              # gcd(a, 0) = a, already in a0

    # k = ctz(a | b) by binary search; x = t0, k = t5, scratch = t2
    or      t0, a0, a1
    li      t5, 0
    slli    t2, t0, 16              # low 16 bits all zero?
    bnez    t2, 1f
    srli    t0, t0, 16
    addi    t5, t5, 16
1:  slli    t2, t0, 24              # low 8 bits
    bnez    t2, 2f
    srli    t0, t0, 8
    addi    t5, t5, 8
2:  slli    t2, t0, 28              # low 4 bits
    bnez    t2, 3f
    srli    t0, t0, 4
    addi    t5, t5, 4
3:  slli    t2, t0, 30              # low 2 bits
    bnez    t2, 4f
    srli    t0, t0, 2
    addi    t5, t5, 2
4:  andi    t2, t0, 1               # low bit
    bnez    t2, 5f
    addi    t5, t5, 1
5:
    srl     a0, a0, t5              # drop the shared factors of two
    srl     a1, a1, t5

    # make a odd
    andi    t2, a0, 1
    bnez    t2, .La_odd
6:  srli    a0, a0, 1
    andi    t2, a0, 1
    beqz    t2, 6b
.La_odd:
    andi    t2, a1, 1               # b already odd: go straight to step
    bnez    t2, .Lstep

.Lstrip:                            # b is even and nonzero
    srli    a1, a1, 1
    andi    t2, a1, 1
    beqz    t2, .Lstrip

.Lstep:                             # a and b odd
    sub     t0, a1, a0              # d = b - a (wraps if b < a)
    sltu    t1, a1, a0              # t1 = (b < a)
    neg     t1, t1                  # mask = all ones if b < a
    and     t2, t0, t1
    add     a0, a0, t2              # a = min(a, b)
    xor     t0, t0, t1
    sub     a1, t0, t1              # b = |b - a|, even
    bnez    a1, .Lstrip

    sll     a0, a0, t5              # restore the shared factors of two
.Ldone:
    ret
.Lret_b:
    mv      a0, a1
    ret

    .size   gcd_u32_asm, . - gcd_u32_asm
