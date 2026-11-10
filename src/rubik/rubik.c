#include "rubik.h"
#include "rubik_tables.h"

/* Move m turns face m / 3 (R, B, D) a quarter turn (m % 3) + 1 times, in
 * the order of sysprog21/minirubik.
 */
static const char move_text[9][3] = {"R",  "R2", "R'", "B", "B2",
                                     "B'", "D",  "D2", "D'"};

/* Weights of the permutation rank (Lehmer code), as in minirubik. */
static const uint16_t fact[7] = {720, 120, 24, 6, 2, 1, 1};

typedef struct {
    uint32_t p, o;    /* state reached by the moves in path */
    uint8_t path[12]; /* at most 11 moves */
    int n;
} solver_t;

/* Distance of a state within 5 moves, or -1: binary search over the
 * sorted entries key << 3 | distance, with key = p << 10 | o.
 */
static int near_depth(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_NEAR_COUNT, want = key << 3;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t e = rubik_near[mid], k = e & ~7u;
        if (k < want)
            lo = mid + 1;
        else if (k > want)
            hi = mid;
        else
            return (int) (e & 7u);
    }
    return -1;
}

/* Whether a state lies at distance 11. */
static int is_far(uint32_t key)
{
    uint32_t lo = 0, hi = RUBIK_FAR_COUNT;
    while (lo < hi) {
        uint32_t mid = (lo + hi) >> 1;
        uint32_t e = rubik_far[mid];
        if (e < key)
            lo = mid + 1;
        else if (e > key)
            hi = mid;
        else
            return 1;
    }
    return 0;
}

/* Depth-limited search: try every sequence of depth moves from (p, o),
 * never turning the same face twice in a row, and stop at the first leaf
 * found in the near table. The moves are appended to path.
 */
static int search(solver_t *s, uint32_t p, uint32_t o, int depth, int last)
{
    if (depth == 0) {
        if (near_depth((p << 10) | o) < 0)
            return 0;
        s->p = p;
        s->o = o;
        return 1;
    }
    for (int f = 0; f < 3; f++) {
        if (f == last)
            continue;
        uint32_t np = p, no = o;
        for (int t = 0; t < 3; t++) {
            np = rubik_perm_move[f][np];
            no = rubik_orient_move[f][no];
            s->path[s->n++] = (uint8_t) (f * 3 + t);
            if (search(s, np, no, depth - 1, f))
                return 1;
            s->n--;
        }
    }
    return 0;
}

/* Walk down the near table: from a state at distance d, some move
 * reaches distance d - 1.
 */
static void descend(solver_t *s, int d)
{
    while (d > 0) {
        int found = 0;
        for (int f = 0; f < 3 && !found; f++) {
            uint32_t np = s->p, no = s->o;
            for (int t = 0; t < 3; t++) {
                np = rubik_perm_move[f][np];
                no = rubik_orient_move[f][no];
                if (near_depth((np << 10) | no) == d - 1) {
                    s->path[s->n++] = (uint8_t) (f * 3 + t);
                    s->p = np;
                    s->o = no;
                    found = 1;
                    break;
                }
            }
        }
        d--;
    }
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned seen = 0, sum = 0;
    uint32_t p = 0, o = 0;
    uint8_t perm[7];

    /* Parse and validate; stop at the first bad character, so a short
     * string is never read past its terminator.
     */
    for (int i = 0; i < 7; i++) {
        char c = state[i];
        if (c < '1' || c > '7')
            return -1;
        unsigned v = (unsigned) (c - '1');
        if (seen & (1u << v))
            return -1; /* repeated cubie */
        seen |= 1u << v;
        perm[i] = (uint8_t) v;
    }
    for (int i = 0; i < 7; i++) {
        char c = state[7 + i];
        if (c < '1' || c > '3')
            return -1;
        unsigned v = (unsigned) (c - '1');
        sum += v;
        if (i < 6)
            o = o * 3 + v;
    }
    if (state[14] != '\0')
        return -1;
    while (sum >= 3) /* sum % 3 without a divide */
        sum -= 3;
    if (sum)
        return -1;

    for (int i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (int j = i + 1; j < 7; j++)
            if (perm[j] < perm[i])
                smaller++;
        p += smaller * fact[i];
    }

    solver_t s = {.p = p, .o = o, .n = 0};
    uint32_t key = (p << 10) | o;
    int d = near_depth(key);
    if (d < 0) {
        if (is_far(key)) {
            /* Distance 11: a neighbor outside the far table is at
             * distance 10, which a 5-move search resolves.
             */
            int done = 0;
            for (int f = 0; f < 3 && !done; f++) {
                uint32_t np = p, no = o;
                for (int t = 0; t < 3; t++) {
                    np = rubik_perm_move[f][np];
                    no = rubik_orient_move[f][no];
                    if (!is_far((np << 10) | no)) {
                        s.path[s.n++] = (uint8_t) (f * 3 + t);
                        done = search(&s, np, no, 5, f);
                        if (!done)
                            s.n--;
                        break;
                    }
                }
            }
        } else {
            /* Distance 6 to 10: the first depth k whose leaves reach the
             * near table gives the distance k + 5.
             */
            for (int k = 1; k <= 5; k++)
                if (search(&s, p, o, k, -1))
                    break;
        }
        d = near_depth((s.p << 10) | s.o);
    }
    descend(&s, d);

    /* Names plus one separator between moves plus the NUL. */
    size_t need = 1;
    for (int i = 0; i < s.n; i++)
        need += move_text[s.path[i]][1] ? 3u : 2u;
    if (s.n)
        need--;
    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }

    char *w = out;
    for (int i = 0; i < s.n; i++) {
        const char *m = move_text[s.path[i]];
        if (i)
            *w++ = ' ';
        *w++ = m[0];
        if (m[1])
            *w++ = m[1];
    }
    *w = '\0';
    return s.n;
}
