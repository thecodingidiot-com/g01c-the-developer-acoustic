#!/bin/bash
# g01c — The Sound / test.sh
#
# Tests game logic (headless), music module process lifecycle, and tier
# transitions. No SDL2, no audio output required.
#
# Copy this file into your working directory alongside libtci.a,
# libtciutil.a, and all source files, then run:
#
#   bash test.sh

set -o pipefail

# ── colour ────────────────────────────────────────────────────────────────────

if [[ ! -t 1 ]]; then
    C_GREEN=""
    C_RED=""
    C_BOLD=""
    C_RESET=""
else
    C_GREEN="\033[0;32m"
    C_RED="\033[0;31m"
    C_BOLD="\033[1m"
    C_RESET="\033[0m"
fi

# ── state ─────────────────────────────────────────────────────────────────────

pass_count=0
fail_count=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures"
SILENCE_WAV=/tmp/g01c_silence.wav

# ── helpers ───────────────────────────────────────────────────────────────────

hr() { echo "────────────────────────────────────────────────────────────────"; }

banner() {
    hr
    echo "  g01c — The Sound / test.sh"
    hr
}

pass() {
    printf "  ${C_GREEN}PASS${C_RESET}  %s\n" "$1"
    pass_count=$((pass_count + 1))
}

fail() {
    local label="$1"
    local detail="$2"
    printf "  ${C_RED}FAIL${C_RESET}  %s\n" "$label"
    [[ -n "$detail" ]] && printf "    %s\n" "$detail"
    fail_count=$((fail_count + 1))
}

# ── pre-flight ────────────────────────────────────────────────────────────────

preflight() {
    local ok=1
    for tool in gcc aplay python3; do
        if ! command -v "$tool" &>/dev/null; then
            echo "error: $tool is not installed" >&2
            ok=0
        fi
    done
    if [[ ! -f libtci.a ]]; then
        echo "error: libtci.a not found — copy it from your c01 build" >&2
        ok=0
    fi
    if [[ ! -f libtciutil.a ]]; then
        echo "error: libtciutil.a not found — copy it from your c01 build" >&2
        ok=0
    fi
    if [[ ! -d "$FIXTURES" ]]; then
        echo "error: fixtures/ not found — keep the g01c clone alongside" >&2
        ok=0
    fi
    [[ $ok -eq 0 ]] && exit 1
}

# ── silence WAV fixture ───────────────────────────────────────────────────────

prepare_silence() {
    python3 - <<'PY' > "$SILENCE_WAV"
import struct, sys
sr, ch, bits, nsamp = 44100, 1, 16, 4410
data = bytes(nsamp * ch * (bits // 8))
hdr = struct.pack('<4sI4s4sIHHIIHH4sI',
    b'RIFF', 36 + len(data), b'WAVE',
    b'fmt ', 16, 1, ch, sr,
    sr * ch * (bits // 8), ch * (bits // 8), bits,
    b'data', len(data))
sys.stdout.buffer.write(hdr + data)
PY
    if [[ ! -s "$SILENCE_WAV" ]]; then
        echo "error: could not generate silence WAV fixture" >&2
        exit 1
    fi
}

# ── shared setup: headless game.h and music stub ──────────────────────────────

write_headless_game_h() {
    cat > /tmp/g01c_game_h.h <<'GAME_H'
#ifndef G01C_GAME_H_HEADLESS
# define G01C_GAME_H_HEADLESS

# include "libtci.h"
# include <sys/types.h>
# include <fcntl.h>
# include <unistd.h>
# include <stdlib.h>
# include <time.h>

# define LEVELS 15
# define WIN_W  800
# define WIN_H  600

typedef struct s_question {
    char    *text;
    char    *opts[4];
    int      answer;
    char    *hint;
} question_t;

typedef enum e_state {
    STATE_TITLE,
    STATE_QUESTION,
    STATE_CONFIRM,
    STATE_CORRECT,
    STATE_WRONG,
    STATE_WIN,
    STATE_GAMEOVER
} game_state_t;

typedef struct s_game {
    void        *win;
    void        *ren;
    void        *bg_studio;
    void        *bg_correct;
    void        *bg_wrong;
    void        *font;
    game_state_t state;
    question_t **questions;
    int          count;
    int          level;
    int          safe_level;
    int          lifelines;
    int          phone_active;
    int          hidden[4];
    int          audience[4];
    char         pending;
    pid_t        music_pid;
} game_t;

extern const char  *PRIZES[LEVELS];
extern const int    SAFE[LEVELS];

question_t  **load_questions(const char *path, int *count);
void          free_questions(question_t **questions, int count);
void          game_init(game_t *g, question_t **questions, int count);
void          game_free(game_t *g);
void          evaluate_answer(game_t *g);
void          handle_lifeline(game_t *g, int lifeline);
void          next_question(game_t *g);

pid_t  start_music(const char *path);
void   stop_music(pid_t pid);

#endif
GAME_H
}

write_music_stub() {
    cat > /tmp/g01c_music_stub.c <<'STUB_C'
#include <stdio.h>
#include <sys/types.h>

#define STUB_LOG "/tmp/g01c_tier_log.txt"

pid_t  start_music(const char *path)
{
    FILE *f = fopen(STUB_LOG, "a");
    if (f) { fprintf(f, "start:%s\n", path); fclose(f); }
    return (9999);
}

void  stop_music(pid_t pid)
{
    FILE *f = fopen(STUB_LOG, "a");
    if (f) { fprintf(f, "stop:%d\n", (int)pid); fclose(f); }
}
STUB_C
}

# ── logic tests (headless — no SDL2, no audio output) ─────────────────────────

run_logic_tests() {
    echo ""
    echo "${C_BOLD}  Game logic — headless (no SDL2, no audio)${C_RESET}"
    echo ""

    write_headless_game_h
    write_music_stub

    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' game.c > /tmp/g01c_game.c
    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' load.c > /tmp/g01c_load.c

    cat > /tmp/g01c_logic_test.c <<'TEST_C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "/tmp/g01c_game_h.h"

int main(void)
{
    question_t **qs;
    int          count;
    game_t       g;
    int          prev;

    /* ── Test 1: question loading ── */
    qs = load_questions("fixtures/questions.txt", &count);
    if (count >= 15)
        printf("PASS load_questions: %d questions loaded\n", count);
    else
        printf("FAIL load_questions: got %d, want >= 15\n", count);
    if (qs && qs[0] && qs[0]->text && qs[0]->text[0] != '\0')
        printf("PASS load_questions: first question text is non-empty\n");
    else
        printf("FAIL load_questions: first question text is empty\n");

    /* ── Test 2: game_init ── */
    game_init(&g, qs, count);
    if (g.state == STATE_TITLE && g.level == 0 && g.safe_level == -1 && g.lifelines == 7)
        printf("PASS game_init: state TITLE, level 0, safe_level -1, lifelines 7\n");
    else
        printf("FAIL game_init: unexpected initial state\n");

    /* ── Test 3: safe-level advancement ── */
    g.level = 3;
    next_question(&g);
    if (g.safe_level == 4)
        printf("PASS safe_level: set to 4 after reaching level 5\n");
    else
        printf("FAIL safe_level: got %d, want 4\n", g.safe_level);
    if (g.state == STATE_QUESTION)
        printf("PASS state: STATE_QUESTION at safe level\n");
    else
        printf("FAIL state: got %d, want STATE_QUESTION (%d)\n", g.state, (int)STATE_QUESTION);
    g.level = 8;
    next_question(&g);
    if (g.safe_level == 9)
        printf("PASS safe_level: set to 9 after reaching level 10\n");
    else
        printf("FAIL safe_level: got %d, want 9\n", g.safe_level);

    /* ── Test 4: lifeline bitfield ── */
    game_init(&g, qs, count);
    if ((g.lifelines & 1) && (g.lifelines & 2) && (g.lifelines & 4))
        printf("PASS lifelines: all three set at start\n");
    else
        printf("FAIL lifelines: not all set at start (got %d)\n", g.lifelines);
    handle_lifeline(&g, 1);
    if (!(g.lifelines & 1))
        printf("PASS 50:50 lifeline: bit 0 cleared\n");
    else
        printf("FAIL 50:50 lifeline: bit 0 not cleared\n");
    prev = g.lifelines;
    handle_lifeline(&g, 1);
    if (g.lifelines == prev)
        printf("PASS 50:50 lifeline: not re-usable\n");
    else
        printf("FAIL 50:50 lifeline: changed on second use\n");
    handle_lifeline(&g, 2);
    if (!(g.lifelines & 2))
        printf("PASS phone lifeline: bit 1 cleared\n");
    else
        printf("FAIL phone lifeline: bit 1 not cleared\n");
    handle_lifeline(&g, 3);
    if (!(g.lifelines & 4))
        printf("PASS audience lifeline: bit 2 cleared\n");
    else
        printf("FAIL audience lifeline: bit 2 not cleared\n");

    /* ── Test 5: state transitions ── */
    game_init(&g, qs, count);
    g.state = STATE_QUESTION;
    g.pending = (char)('A' + qs[0]->answer);
    evaluate_answer(&g);
    if (g.state == STATE_CORRECT)
        printf("PASS evaluate_answer: correct answer -> STATE_CORRECT\n");
    else
        printf("FAIL evaluate_answer: got %d, want STATE_CORRECT (%d)\n", g.state, (int)STATE_CORRECT);
    game_init(&g, qs, count);
    g.state = STATE_QUESTION;
    g.pending = (char)('A' + ((qs[0]->answer + 1) % 4));
    evaluate_answer(&g);
    if (g.state == STATE_WRONG)
        printf("PASS evaluate_answer: wrong answer -> STATE_WRONG\n");
    else
        printf("FAIL evaluate_answer: got %d, want STATE_WRONG (%d)\n", g.state, (int)STATE_WRONG);

    game_free(&g);
    free_questions(qs, count);
    return 0;
}
TEST_C

    gcc -Wall -Wextra -I. -I libtci \
        /tmp/g01c_logic_test.c \
        /tmp/g01c_game.c \
        /tmp/g01c_load.c \
        /tmp/g01c_music_stub.c \
        libtci.a libtciutil.a \
        -o /tmp/g01c_logic_tester 2>/tmp/g01c_logic_build.log

    if [[ $? -ne 0 ]]; then
        fail "logic test compilation" "$(cat /tmp/g01c_logic_build.log)"
        return
    fi

    ln -sf "$FIXTURES" fixtures 2>/dev/null || true

    local output
    output=$(/tmp/g01c_logic_tester 2>&1)
    while IFS= read -r line; do
        local result="${line%% *}"
        if [[ "$result" == "PASS" ]]; then
            pass "${line#PASS }"
        else
            fail "${line#FAIL }" ""
        fi
    done <<< "$output"
}

# ── music module tests (real process lifecycle) ────────────────────────────────

run_music_tests() {
    echo ""
    echo "${C_BOLD}  Music module — process lifecycle${C_RESET}"
    echo ""

    cat > /tmp/g01c_music_test.c <<'MUSIC_C'
#include <stdio.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "music.h"

int main(int argc, char **argv)
{
    pid_t           pid;
    int             rc;
    struct timespec ts;

    if (argc < 2) {
        fprintf(stderr, "usage: music_test <wav_path>\n");
        return 1;
    }

    pid = start_music(argv[1]);
    if (pid > 0)
        printf("PASS start_music returns valid PID\n");
    else {
        printf("FAIL start_music returned %d\n", (int)pid);
        return 1;
    }

    ts.tv_sec = 0;
    ts.tv_nsec = 50000000;
    nanosleep(&ts, NULL);

    rc = kill(pid, 0);
    if (rc == 0)
        printf("PASS aplay process is alive after start\n");
    else
        printf("FAIL aplay process is not alive (errno %d)\n", errno);

    stop_music(pid);
    rc = kill(pid, 0);
    if (rc == -1 && errno == ESRCH)
        printf("PASS stop_music killed the process\n");
    else
        printf("FAIL process still exists after stop_music\n");

    rc = waitpid(pid, NULL, WNOHANG);
    if (rc == -1 && errno == ECHILD)
        printf("PASS no zombie process left\n");
    else
        printf("FAIL zombie detected (waitpid returned %d, errno %d)\n", rc, errno);

    return 0;
}
MUSIC_C

    gcc -Wall -Wextra -D_POSIX_C_SOURCE=200112L -I. \
        /tmp/g01c_music_test.c music.c \
        -o /tmp/g01c_music_test_bin 2>/tmp/g01c_music_build.log

    if [[ $? -ne 0 ]]; then
        fail "music module compilation" "$(cat /tmp/g01c_music_build.log)"
        return
    fi

    local output
    output=$(/tmp/g01c_music_test_bin "$SILENCE_WAV" 2>&1)
    while IFS= read -r line; do
        local result="${line%% *}"
        if [[ "$result" == "PASS" ]]; then
            pass "${line#PASS }"
        else
            fail "${line#FAIL }" ""
        fi
    done <<< "$output"
}

# ── tier transition tests (headless — log inspection) ─────────────────────────

run_tier_tests() {
    echo ""
    echo "${C_BOLD}  Tier transitions — headless${C_RESET}"
    echo ""

    write_headless_game_h
    write_music_stub

    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' game.c > /tmp/g01c_game.c
    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' load.c > /tmp/g01c_load.c

    cat > /tmp/g01c_tier_test.c <<'TIER_C'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "/tmp/g01c_game_h.h"

#define STUB_LOG "/tmp/g01c_tier_log.txt"

static int log_contains(const char *substr)
{
    FILE *f;
    char  line[256];

    f = fopen(STUB_LOG, "r");
    if (!f) return 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, substr)) { fclose(f); return 1; }
    }
    fclose(f);
    return 0;
}

static void log_clear(void)
{
    FILE *f = fopen(STUB_LOG, "w");
    if (f) fclose(f);
}

int main(void)
{
    question_t **qs;
    int          count;
    game_t       g;
    int          i;

    qs = load_questions("fixtures/questions.txt", &count);
    if (!qs || count < 15) {
        printf("FAIL could not load questions (got %d)\n", count);
        return 1;
    }

    /* ── tier1 starts on game_init ── */
    log_clear();
    game_init(&g, qs, count);
    if (log_contains("start:music/tier1.wav"))
        printf("PASS tier1 music started at game_init\n");
    else
        printf("FAIL tier1 music not started at game_init\n");

    /* ── tier2 starts at level 5 ── */
    for (i = 0; i < 5; i++)
        next_question(&g);
    if (log_contains("start:music/tier2.wav"))
        printf("PASS tier2 music started when level reaches 5\n");
    else
        printf("FAIL tier2 music not started at level 5\n");

    /* ── tier3 starts at level 10 ── */
    for (i = 0; i < 5; i++)
        next_question(&g);
    if (log_contains("start:music/tier3.wav"))
        printf("PASS tier3 music started when level reaches 10\n");
    else
        printf("FAIL tier3 music not started at level 10\n");

    /* ── stop_music called on win (final 5 questions) ── */
    log_clear();
    for (i = 0; i < 5; i++)
        next_question(&g);
    if (g.state == STATE_WIN && log_contains("stop:9999"))
        printf("PASS stop_music called on win\n");
    else
        printf("FAIL stop_music not called on win (state %d)\n", g.state);

    game_free(&g);

    /* ── stop_music called on game_free (game over path) ── */
    log_clear();
    game_init(&g, qs, count);
    game_free(&g);
    if (log_contains("stop:9999"))
        printf("PASS stop_music called on game_free\n");
    else
        printf("FAIL stop_music not called on game_free\n");

    free_questions(qs, count);
    return 0;
}
TIER_C

    gcc -Wall -Wextra -I. -I libtci \
        /tmp/g01c_tier_test.c \
        /tmp/g01c_game.c \
        /tmp/g01c_load.c \
        /tmp/g01c_music_stub.c \
        libtci.a libtciutil.a \
        -o /tmp/g01c_tier_tester 2>/tmp/g01c_tier_build.log

    if [[ $? -ne 0 ]]; then
        fail "tier test compilation" "$(cat /tmp/g01c_tier_build.log)"
        return
    fi

    ln -sf "$FIXTURES" fixtures 2>/dev/null || true

    local output
    output=$(/tmp/g01c_tier_tester 2>&1)
    while IFS= read -r line; do
        local result="${line%% *}"
        if [[ "$result" == "PASS" ]]; then
            pass "${line#PASS }"
        else
            fail "${line#FAIL }" ""
        fi
    done <<< "$output"
}

# ── summary ───────────────────────────────────────────────────────────────────

summary() {
    local total=$((pass_count + fail_count))
    echo ""
    hr
    printf "  %d / %d tests passed\n" "$pass_count" "$total"
    hr
    echo ""
    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────

banner
preflight
prepare_silence
run_logic_tests
run_music_tests
run_tier_tests
summary
