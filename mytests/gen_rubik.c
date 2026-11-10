/* Host-side generator for the rubik tables. It rebuilds the move tables of
 * the sysprog21/minirubik model, runs a breadth-first search over all
 * 3,674,160 states, and writes the states within 5 moves and the states at
 * distance 11 as sorted keys (p << 10 | o).
 *
 * Usage: gcc -O2 -Wall -o mytests/gen_rubik mytests/gen_rubik.c
 *        mytests/gen_rubik src/rubik
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CUBIES = 7, PERMS = 5040, ORIENTS = 729, STATES = PERMS * ORIENTS };

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

/* Same model as sysprog21/minirubik solver.c: faces R, B, D. */
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

static state_t quarter_turn(state_t s, int face)
{
    state_t r;
    for (int i = 0; i < CUBIES; i++) {
        int from = source[face][i];
        r.p[i] = s.p[from];
        r.o[i] = (uint8_t) ((s.o[from] + twist[face][i]) % 3);
    }
    return r;
}

static uint32_t perm_rank(const state_t *s)
{
    uint32_t p = 0;
    for (int i = 0; i < CUBIES; i++) {
        uint32_t smaller = 0;
        for (int j = i + 1; j < CUBIES; j++)
            if (s->p[j] < s->p[i])
                smaller++;
        p = p * (uint32_t) (CUBIES - i) + smaller;
    }
    return p;
}

static uint32_t orient_rank(const state_t *s)
{
    uint32_t o = 0;
    for (int i = 0; i < 6; i++)
        o = o * 3 + s->o[i];
    return o;
}

static void unrank(uint32_t p, uint32_t o, state_t *s)
{
    uint8_t avail[CUBIES] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t f = 720, sum = 0;
    for (int i = 0; i < CUBIES; i++) {
        uint32_t q = p / f;
        p %= f;
        s->p[i] = avail[q];
        for (int j = (int) q; j + 1 < CUBIES - i; j++)
            avail[j] = avail[j + 1];
        if (i < 5)
            f /= (uint32_t) (6 - i);
    }
    for (int i = 6; i-- > 0;) {
        s->o[i] = (uint8_t) (o % 3);
        sum += s->o[i];
        o /= 3;
    }
    s->o[6] = (uint8_t) ((3 - sum % 3) % 3);
}

static uint16_t pm[3][PERMS], om[3][ORIENTS];

static FILE *open_out(const char *dir, const char *name)
{
    char path[512];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *f = fopen(path, "w");
    if (!f) {
        perror(path);
        exit(1);
    }
    return f;
}

static void c_row(FILE *f, unsigned v, int i, int n)
{
    if (i % 12 == 0)
        fputs("    ", f);
    fprintf(f, "%u,", v);
    fputc((i % 12 == 11 || i == n - 1) ? '\n' : ' ', f);
}

static void s_row(FILE *f, const char *dir, unsigned v, int i, int n)
{
    if (i % 12 == 0)
        fprintf(f, "    %s ", dir);
    fprintf(f, "%u", v);
    fputs((i % 12 == 11 || i == n - 1) ? "\n" : ", ", f);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s OUTPUT_DIR\n", argv[0]);
        return 1;
    }

    state_t s;
    for (uint32_t p = 0; p < PERMS; p++) {
        unrank(p, 0, &s);
        for (int face = 0; face < 3; face++) {
            state_t n = quarter_turn(s, face);
            pm[face][p] = (uint16_t) perm_rank(&n);
        }
    }
    for (uint32_t o = 0; o < ORIENTS; o++) {
        unrank(0, o, &s);
        for (int face = 0; face < 3; face++) {
            state_t n = quarter_turn(s, face);
            om[face][o] = (uint16_t) orient_rank(&n);
        }
    }

    uint8_t *dist = malloc(STATES);
    uint32_t *queue = malloc((size_t) STATES * sizeof *queue);
    if (!dist || !queue)
        return 1;
    memset(dist, 0xFF, STATES);
    uint32_t head = 0, tail = 1;
    queue[0] = 0;
    dist[0] = 0;
    while (head < tail) {
        uint32_t here = queue[head++];
        uint32_t p = here / ORIENTS, o = here % ORIENTS;
        for (int face = 0; face < 3; face++) {
            uint32_t np = p, no = o;
            for (int t = 0; t < 3; t++) {
                np = pm[face][np];
                no = om[face][no];
                uint32_t idx = np * ORIENTS + no;
                if (dist[idx] == 0xFF) {
                    dist[idx] = (uint8_t) (dist[here] + 1);
                    queue[tail++] = idx;
                }
            }
        }
    }
    if (tail != STATES) {
        fprintf(stderr, "BFS reached %u states only\n", (unsigned) tail);
        return 1;
    }

    /* Keys grow with (p, o), so these loops emit sorted tables. */
    static uint32_t near[STATES], far[STATES];
    int n = 0, m = 0, diameter = 0;
    uint32_t count[16] = {0};
    for (uint32_t p = 0; p < PERMS; p++) {
        for (uint32_t o = 0; o < ORIENTS; o++) {
            int d = dist[p * ORIENTS + o];
            uint32_t key = (p << 10) | o;
            count[d]++;
            if (d > diameter)
                diameter = d;
            if (d <= 5)
                near[n++] = (key << 3) | (uint32_t) d;
            if (d == 11)
                far[m++] = key;
        }
    }
    free(dist);
    free(queue);

    printf("diameter %d, near %d, far %d\n", diameter, n, m);
    for (int d = 0; d <= diameter; d++)
        printf("  distance %2d: %u\n", d, (unsigned) count[d]);

    FILE *h = open_out(argv[1], "rubik_tables.h");
    fprintf(h,
            "/* Generated by mytests/gen_rubik.c; do not edit. */\n"
            "#pragma once\n\n#include <stdint.h>\n\n"
            "#define RUBIK_NEAR_COUNT %d\n#define RUBIK_FAR_COUNT %d\n\n"
            "extern const uint16_t rubik_perm_move[3][5040];\n"
            "extern const uint16_t rubik_orient_move[3][729];\n"
            "extern const uint32_t rubik_near[RUBIK_NEAR_COUNT];\n"
            "extern const uint32_t rubik_far[RUBIK_FAR_COUNT];\n",
            n, m);
    fclose(h);

    FILE *c = open_out(argv[1], "rubik_tables.c");
    fputs(
        "/* Generated by mytests/gen_rubik.c; do not edit. */\n"
        "#include \"rubik_tables.h\"\n\n"
        "const uint16_t rubik_perm_move[3][5040] = {\n",
        c);
    for (int face = 0; face < 3; face++) {
        fputs("    {\n", c);
        for (int i = 0; i < PERMS; i++)
            c_row(c, pm[face][i], i, PERMS);
        fputs("    },\n", c);
    }
    fputs("};\n\nconst uint16_t rubik_orient_move[3][729] = {\n", c);
    for (int face = 0; face < 3; face++) {
        fputs("    {\n", c);
        for (int i = 0; i < ORIENTS; i++)
            c_row(c, om[face][i], i, ORIENTS);
        fputs("    },\n", c);
    }
    fputs("};\n\nconst uint32_t rubik_near[RUBIK_NEAR_COUNT] = {\n", c);
    for (int i = 0; i < n; i++)
        c_row(c, near[i], i, n);
    fputs("};\n\nconst uint32_t rubik_far[RUBIK_FAR_COUNT] = {\n", c);
    for (int i = 0; i < m; i++)
        c_row(c, far[i], i, m);
    fputs("};\n", c);
    fclose(c);

    FILE *a = open_out(argv[1], "rubik_tables.S");
    fputs(
        "# Generated by mytests/gen_rubik.c; do not edit.\n"
        "# Tables of the assembly solver, a copy of rubik_tables.c,\n"
        "# because the C and assembly objects are linked separately.\n"
        "    .section .rodata\n    .balign 4\n"
        "    .globl rubik_asm_perm_move\nrubik_asm_perm_move:\n",
        a);
    for (int face = 0; face < 3; face++)
        for (int i = 0; i < PERMS; i++)
            s_row(a, ".half", pm[face][i], i, PERMS);
    fputs("    .globl rubik_asm_orient_move\nrubik_asm_orient_move:\n", a);
    for (int face = 0; face < 3; face++)
        for (int i = 0; i < ORIENTS; i++)
            s_row(a, ".half", om[face][i], i, ORIENTS);
    fputs("    .balign 4\n    .globl rubik_asm_near\nrubik_asm_near:\n", a);
    for (int i = 0; i < n; i++)
        s_row(a, ".word", near[i], i, n);
    fputs("    .globl rubik_asm_far\nrubik_asm_far:\n", a);
    for (int i = 0; i < m; i++)
        s_row(a, ".word", far[i], i, m);
    fclose(a);
    return 0;
}
