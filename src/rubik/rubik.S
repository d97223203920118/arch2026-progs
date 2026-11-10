# Optimal 2x2x2 solver for RV32I, the hand-written counterpart of rubik.c.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#
# Same algorithm as the C version: a state is the key (p << 10) | o, a face
# turn is two halfword table loads, an iterative deepening search of at most
# five moves ends in the near table (states within 5 moves), and the far
# table (distance 11) lets such a state step to distance 10 first.
#
# Speed comes from the leaf: the binary search over the 12,224 near entries
# is fully unrolled, since every step size is a constant, and the last
# search level expands its six children in registers without recursion.
#
# Globals kept in saved registers during the solve:
#   s0 frame base   s1 out   s2 cap   s3 near table   s4 far table
#   s5..s8 the four step sizes too large for an immediate   s9 move count

    .equ    FRAME, 128
    .equ    RES_P, 32           # state reached by the moves in PATH
    .equ    RES_O, 36
    .equ    PATH, 40            # move indices, at most 11 bytes
    .equ    PERM, 52            # parsed permutation digits
    .equ    SAVE, 64            # ra and s0..s11
    .equ    FAR_COUNT, 2644

# One quarter turn of the face whose tables are t6 (permutation) and a7
# (orientation): t4 = p, t5 = o.
    .macro  APPLY
    slli    t0, t4, 1
    add     t0, t6, t0
    lhu     t4, 0(t0)
    slli    t0, t5, 1
    add     t0, a7, t0
    lhu     t5, 0(t0)
    .endm

# Table bases of face f3 (0, 3 or 6) from the frame: t6 and a7.
    .macro  FACE_BASE
    slli    t0, a4, 2
    add     t0, s0, t0
    lw      t6, 0(t0)
    lw      a7, 4(t0)
    .endm

# Binary search steps: t0 = base, t1 = (key << 3) | 7.
    .macro  NBIG reg
    add     a1, t0, \reg
    lw      t2, 0(a1)
    bltu    t1, t2, 1f
    mv      t0, a1
1:
    .endm

    .macro  NSTEP off
    lw      t2, \off(t0)
    bltu    t1, t2, 1f
    addi    t0, t0, \off
1:
    .endm

# One child of a leaf: turn once more, look it up, record a hit.
    .macro  LEAF_TURN k
    APPLY
    slli    a0, t4, 10
    or      a0, a0, t5
    jal     t3, .Lnear
    sltiu   t0, a1, 8
    beqz    t0, 9f
    addi    t1, a4, \k
    j       .Lleaf_hit
9:
    .endm

    .text
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -FRAME
    sw      ra, SAVE+0(sp)
    sw      s0, SAVE+4(sp)
    sw      s1, SAVE+8(sp)
    sw      s2, SAVE+12(sp)
    sw      s3, SAVE+16(sp)
    sw      s4, SAVE+20(sp)
    sw      s5, SAVE+24(sp)
    sw      s6, SAVE+28(sp)
    sw      s7, SAVE+32(sp)
    sw      s8, SAVE+36(sp)
    sw      s9, SAVE+40(sp)
    sw      s10, SAVE+44(sp)
    sw      s11, SAVE+48(sp)
    mv      s0, sp
    mv      s1, a1
    mv      s2, a2

    # Permutation digits '1'..'7', each once. Characters are read one at
    # a time, so a short string stops at its terminator.
    li      t0, 0                   # bit set of cubies seen
    mv      t2, a0
    addi    t6, a0, 7
    addi    a6, s0, PERM
1:  lbu     t1, 0(t2)
    addi    t1, t1, -49             # '1' -> 0; anything else lands >= 7
    li      t4, 7
    bgeu    t1, t4, .Linvalid
    li      t4, 1
    sll     t4, t4, t1
    and     t5, t0, t4
    bnez    t5, .Linvalid           # repeated cubie
    or      t0, t0, t4
    sb      t1, 0(a6)
    addi    a6, a6, 1
    addi    t2, t2, 1
    bne     t2, t6, 1b

    # Orientation digits '1'..'3'; the first six form o in base 3.
    li      a3, 0                   # o
    li      a5, 0                   # digit sum
    addi    t6, a0, 14
2:  lbu     t1, 0(t2)
    addi    t1, t1, -49
    li      t4, 3
    bgeu    t1, t4, .Linvalid
    add     a5, a5, t1
    addi    t2, t2, 1
    beq     t2, t6, 3f              # the seventh digit is not folded in
    slli    t4, a3, 1
    add     a3, a3, t4
    add     a3, a3, t1              # o = 3 * o + digit
    j       2b
3:  lbu     t1, 0(t2)
    bnez    t1, .Linvalid           # longer than 14 characters
    li      t4, 3
4:  blt     a5, t4, 5f              # sum mod 3 by subtraction
    addi    a5, a5, -3
    j       4b
5:  bnez    a5, .Linvalid

    # Permutation rank: p = p * (7 - i) + (smaller digits to the right),
    # the multiply done by repeated addition (at most 7 per digit, once).
    li      a2, 0                   # p
    li      t1, 0                   # i
6:  add     t2, s0, t1
    lbu     t3, PERM(t2)
    li      t4, 0                   # smaller
    addi    t5, t1, 1               # j
7:  li      t0, 7
    bge     t5, t0, 8f
    add     t2, s0, t5
    lbu     t2, PERM(t2)
    bgeu    t2, t3, 9f
    addi    t4, t4, 1
9:  addi    t5, t5, 1
    j       7b
8:  li      t0, 7
    sub     t0, t0, t1
    li      t5, 0
10: add     t5, t5, a2
    addi    t0, t0, -1
    bnez    t0, 10b
    add     a2, t5, t4
    addi    t1, t1, 1
    li      t0, 7
    blt     t1, t0, 6b
    sw      a2, RES_P(s0)
    sw      a3, RES_O(s0)

    # Globals and the per-face table bases, indexed by f3 * 4.
    la      s3, rubik_asm_near
    la      s4, rubik_asm_far
    li      s5, 24448
    li      s6, 12224
    li      s7, 6112
    li      s8, 3056
    la      s10, rubik_asm_perm_move
    la      s11, rubik_asm_orient_move
    li      t0, 10080               # 5040 halfwords per face
    sw      s10, 0(s0)
    add     t1, s10, t0
    sw      t1, 12(s0)
    add     t1, t1, t0
    sw      t1, 24(s0)
    sw      s11, 4(s0)
    addi    t1, s11, 1458           # 729 halfwords per face
    sw      t1, 16(s0)
    addi    t1, t1, 1458
    sw      t1, 28(s0)

    li      s9, 0
    slli    a0, a2, 10
    or      a0, a0, a3              # key
    jal     t3, .Lnear
    sltiu   t0, a1, 8
    bnez    t0, .Ldescend           # within 5 moves: a1 is the distance
    jal     t3, .Lfar
    bnez    a1, .Lfar_case

    # Distance 6 to 10: the first depth whose leaves reach the near table.
    li      s9, 1
.Lk_loop:
    lw      a2, RES_P(s0)
    lw      a3, RES_O(s0)
    mv      a4, s9
    li      a5, -3                  # no previous face
    li      a6, 0
    jal     ra, .Lsearch
    bnez    a0, .Lhave_res
    addi    s9, s9, 1
    j       .Lk_loop

    # Distance 11: a neighbor outside the far table is at distance 10.
.Lfar_case:
    li      a4, 0
1:  FACE_BASE
    lw      t4, RES_P(s0)
    lw      t5, RES_O(s0)
    li      s9, 0                   # turn
2:  APPLY
    slli    a0, t4, 10
    or      a0, a0, t5
    jal     t3, .Lfar
    beqz    a1, 3f
    addi    s9, s9, 1
    li      t0, 3
    blt     s9, t0, 2b
    addi    a4, a4, 3
    j       1b
3:  add     t1, a4, s9
    sb      t1, PATH(s0)
    mv      a2, t4
    mv      a3, t5
    mv      a5, a4
    li      a4, 5
    li      a6, 1
    jal     ra, .Lsearch
    li      s9, 6

.Lhave_res:
    lw      t4, RES_P(s0)
    lw      t5, RES_O(s0)
    slli    a0, t4, 10
    or      a0, a0, t5
    jal     t3, .Lnear

    # Walk down the near table: a5 = distance, a6 = distance - 1.
.Ldescend:
    mv      a5, a1
.Ld_loop:
    beqz    a5, .Loutput
    addi    a6, a5, -1
    li      a4, 0
.Ld_face:
    FACE_BASE
    lw      t4, RES_P(s0)
    lw      t5, RES_O(s0)
    li      a3, 0
.Ld_turn:
    APPLY
    slli    a0, t4, 10
    or      a0, a0, t5
    jal     t3, .Lnear
    beq     a1, a6, .Ld_hit
    addi    a3, a3, 1
    li      t0, 3
    blt     a3, t0, .Ld_turn
    addi    a4, a4, 3
    j       .Ld_face
.Ld_hit:
    add     t1, a4, a3
    add     t0, s0, s9
    sb      t1, PATH(t0)
    addi    s9, s9, 1
    sw      t4, RES_P(s0)
    sw      t5, RES_O(s0)
    mv      a5, a6
    j       .Ld_loop

    # Output: names, one space between moves, a NUL.
.Loutput:
    la      a7, .Lnames
    li      t0, 1                   # bytes needed
    li      t1, 0
1:  bge     t1, s9, 2f
    add     t2, s0, t1
    lbu     t2, PATH(t2)
    slli    t2, t2, 1
    add     t2, a7, t2
    lbu     t2, 1(t2)
    snez    t2, t2
    addi    t0, t0, 2
    add     t0, t0, t2              # name length plus a separator
    addi    t1, t1, 1
    j       1b
2:  beqz    s9, 3f
    addi    t0, t0, -1              # no separator before the first move
3:  bgeu    s2, t0, 4f
    beqz    s2, 5f
    sb      zero, 0(s1)
5:  li      a0, -2
    j       .Lret
4:  mv      a2, s1
    li      t1, 0
6:  bge     t1, s9, 7f
    beqz    t1, 8f
    li      t0, 32                  # space
    sb      t0, 0(a2)
    addi    a2, a2, 1
8:  add     t2, s0, t1
    lbu     t2, PATH(t2)
    slli    t2, t2, 1
    add     t2, a7, t2
    lbu     t0, 0(t2)
    sb      t0, 0(a2)
    addi    a2, a2, 1
    lbu     t0, 1(t2)
    beqz    t0, 9f
    sb      t0, 0(a2)
    addi    a2, a2, 1
9:  addi    t1, t1, 1
    j       6b
7:  sb      zero, 0(a2)
    mv      a0, s9
    j       .Lret

.Linvalid:
    li      a0, -1
.Lret:
    lw      ra, SAVE+0(sp)
    lw      s0, SAVE+4(sp)
    lw      s1, SAVE+8(sp)
    lw      s2, SAVE+12(sp)
    lw      s3, SAVE+16(sp)
    lw      s4, SAVE+20(sp)
    lw      s5, SAVE+24(sp)
    lw      s6, SAVE+28(sp)
    lw      s7, SAVE+32(sp)
    lw      s8, SAVE+36(sp)
    lw      s9, SAVE+40(sp)
    lw      s10, SAVE+44(sp)
    lw      s11, SAVE+48(sp)
    addi    sp, sp, FRAME
    ret

# Depth-limited search. In: a2 = p, a3 = o, a4 = depth >= 1, a5 = previous
# face times 3 (or -3), a6 = path index. Out: a0 = 1 when a leaf reaches
# the near table (its state goes to RES_P/RES_O), else 0. Keeps s0..s11.
.Lsearch:
    li      t0, 1
    beq     a4, t0, .Lleaf
    addi    sp, sp, -48
    sw      ra, 0(sp)
    sw      a2, 4(sp)               # p
    sw      a3, 8(sp)               # o
    sw      a4, 12(sp)              # depth
    sw      a5, 16(sp)              # previous face
    sw      a6, 20(sp)              # path index
    li      a4, 0
.Ls_face:
    lw      t0, 16(sp)
    beq     a4, t0, .Ls_next        # never the same face twice in a row
    sw      a4, 24(sp)
    FACE_BASE
    lw      t4, 4(sp)
    lw      t5, 8(sp)
    li      a0, 0
.Ls_turn:
    sw      a0, 28(sp)
    APPLY
    sw      t4, 32(sp)
    sw      t5, 36(sp)
    lw      a6, 20(sp)
    add     t0, s0, a6
    add     t1, a4, a0
    sb      t1, PATH(t0)
    mv      a2, t4
    mv      a3, t5
    mv      a5, a4
    lw      t0, 12(sp)
    addi    a4, t0, -1
    addi    a6, a6, 1
    jal     ra, .Lsearch
    bnez    a0, .Ls_found
    lw      a4, 24(sp)
    lw      a0, 28(sp)
    addi    a0, a0, 1
    li      t0, 3
    beq     a0, t0, .Ls_next
    FACE_BASE
    lw      t4, 32(sp)
    lw      t5, 36(sp)
    j       .Ls_turn
.Ls_next:
    addi    a4, a4, 3
    li      t0, 9
    blt     a4, t0, .Ls_face
    li      a0, 0
    j       .Ls_ret
.Ls_found:
    li      a0, 1
.Ls_ret:
    lw      ra, 0(sp)
    addi    sp, sp, 48
    ret

# Last level: the six children expanded in registers, no stack.
.Lleaf:
    li      a4, 0
.Ll_face:
    beq     a4, a5, .Ll_next
    FACE_BASE
    mv      t4, a2
    mv      t5, a3
    LEAF_TURN 0
    LEAF_TURN 1
    LEAF_TURN 2
.Ll_next:
    addi    a4, a4, 3
    li      t0, 9
    blt     a4, t0, .Ll_face
    li      a0, 0
    ret
.Lleaf_hit:
    add     t0, s0, a6
    sb      t1, PATH(t0)
    sw      t4, RES_P(s0)
    sw      t5, RES_O(s0)
    li      a0, 1
    ret

# Near lookup. In: a0 = key. Out: a1 = entry - (key << 3), which is the
# distance (0..5) when below 8 and means "absent" otherwise.
# Clobbers t0..t2. Called with jal t3. The 14 steps follow the halving
# of the fixed table length 12,224, so every offset is a constant.
.Lnear:
    slli    t1, a0, 3
    ori     t1, t1, 7               # largest entry with this key
    mv      t0, s3
    NBIG    s5
    NBIG    s6
    NBIG    s7
    NBIG    s8
    NSTEP   1528
    NSTEP   764
    NSTEP   380
    NSTEP   192
    NSTEP   96
    NSTEP   48
    NSTEP   24
    NSTEP   12
    NSTEP   4
    NSTEP   4
    lw      t2, 0(t0)
    addi    t1, t1, -7
    sub     a1, t2, t1
    jr      t3

# Far lookup. In: a0 = key. Out: a1 = 1 when present. Clobbers t0..t2.
# Called with jal t3; rarely used, so a plain loop.
.Lfar:
    mv      t0, s4
    li      t2, FAR_COUNT
1:  srli    t1, t2, 1
    sub     t2, t2, t1
    slli    t1, t1, 2
    add     a1, t0, t1
    lw      t1, 0(a1)
    bltu    a0, t1, 2f
    mv      t0, a1
2:  li      a1, 1
    blt     a1, t2, 1b
    lw      t1, 0(t0)
    sub     a1, t1, a0
    seqz    a1, a1
    jr      t3
    .size   rubik_solve_asm, . - rubik_solve_asm

    .section .rodata
.Lnames:                            # two bytes per move, NUL padded
    .byte   'R', 0, 'R', '2', 'R', 0x27
    .byte   'B', 0, 'B', '2', 'B', 0x27
    .byte   'D', 0, 'D', '2', 'D', 0x27
