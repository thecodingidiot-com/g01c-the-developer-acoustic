#!/bin/bash
# g01c — Who Wants to Be a Game Developer? Acoustic / test.sh
#
# Tests the music module (process lifecycle) and game tier-switching
# logic (headless, no SDL2, no audio output required).
#
# Copy this file into your working directory alongside libtci.a,
# libtciutil.a, game.h, and all source files, then run:
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
    echo "  g01c — Who Wants to Be a Game Developer? Acoustic / test.sh"
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
    for tool in gcc make aplay python3; do
        if ! command -v "$tool" &>/dev/null; then
            echo "error: $tool is not installed" >&2
            ok=0
        fi
    done
    if [[ ! -f Makefile ]]; then
        echo "error: Makefile not found — run from your working directory" >&2
        ok=0
    fi
    if [[ ! -f libtci.a ]]; then
        echo "error: libtci.a not found — copy it from your c01 build" >&2
        ok=0
    fi
    if [[ ! -f libtciutil.a ]]; then
        echo "error: libtciutil.a not found — copy it from your c01 build" >&2
        ok=0
    fi
    if [[ ! -d "$FIXTURES" ]]; then
        echo "error: fixtures/ not found — keep the g01c-the-developer-acoustic clone alongside" >&2
        ok=0
    fi
    [[ $ok -eq 0 ]] && exit 1
}

# ── build ─────────────────────────────────────────────────────────────────────

build() {
    echo ""
    echo "${C_BOLD}  Building${C_RESET}"
    echo ""
    local out
    out=$(make re 2>&1)
    local rc=$?
    printf '%s\n' "$out" | sed 's/^/  /'
    echo ""
    if [[ $rc -eq 0 ]]; then
        pass "make re"
    else
        fail "make re" ""
        echo "  Build failed — aborting tests."
        exit 1
    fi
}

# ── silence fixture ───────────────────────────────────────────────────────────

make_silence() {
    python3 - <<'PY'
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
}

prepare_silence() {
    make_silence > "$SILENCE_WAV"
    if [[ ! -s "$SILENCE_WAV" ]]; then
        echo "error: could not generate silence WAV fixture" >&2
        exit 1
    fi
}

# ── music module tests ────────────────────────────────────────────────────────

run_music_tests() {
    echo ""
    echo "${C_BOLD}  Music module — process lifecycle${C_RESET}"
    echo ""

    cat > /tmp/g01c_music_test.c <<'C'
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>
#include "music.h"

extern const char *WAV_PATH;
const char *WAV_PATH;

int main(int argc, char **argv)
{
    pid_t  pid;
    int    rc;

    if (argc < 2) {
        fprintf(stderr, "usage: music_test <wav_path>\n");
        return 1;
    }
    WAV_PATH = argv[1];

    /* Test 1: start_music returns a positive PID */
    pid = start_music(WAV_PATH);
    if (pid > 0)
        printf("PASS start_music returns valid PID\n");
    else {
        printf("FAIL start_music returned %d\n", (int)pid);
        return 1;
    }

    /* brief yield so aplay has time to exec */
    usleep(50000);

    /* Test 2: aplay process is alive */
    rc = kill(pid, 0);
    if (rc == 0)
        printf("PASS aplay process is alive after start\n");
    else
        printf("FAIL aplay process is not alive (errno %d)\n", errno);

    /* Test 3: stop_music kills it */
    stop_music(pid);
    rc = kill(pid, 0);
    if (rc == -1 && errno == ESRCH)
        printf("PASS stop_music killed the process\n");
    else
        printf("FAIL process still exists after stop_music\n");

    /* Test 4: no zombie — waitpid(WNOHANG) should return -1 (ECHILD) */
    rc = waitpid(pid, NULL, WNOHANG);
    if (rc == -1 && errno == ECHILD)
        printf("PASS no zombie process left\n");
    else
        printf("FAIL zombie detected (waitpid returned %d, errno %d)\n",
               rc, errno);

    return 0;
}
C

    gcc -Wall -Wextra -std=c99 -D_POSIX_C_SOURCE=200112L -I. \
        /tmp/g01c_music_test.c music.c \
        -o /tmp/g01c_music_test 2>/tmp/g01c_music_build.log

    if [[ $? -ne 0 ]]; then
        fail "music module compilation" "$(cat /tmp/g01c_music_build.log)"
        return
    fi

    local output
    output=$(/tmp/g01c_music_test "$SILENCE_WAV" 2>&1)
    while IFS= read -r line; do
        local label="${line#PASS }"
        local result="${line%% *}"
        if [[ "$result" == "PASS" ]]; then
            pass "$label"
        else
            fail "${line#FAIL }" ""
        fi
    done <<< "$output"
}

# ── tier logic tests (headless) ───────────────────────────────────────────────

run_tier_tests() {
    echo ""
    echo "${C_BOLD}  Tier logic — headless (no audio output)${C_RESET}"
    echo ""

    # Stub music functions: start_music records the path and returns a
    # fake PID; stop_music records the call. Both write to a shared log
    # so the test binary can inspect them.

    cat > /tmp/g01c_music_stub.c <<'C'
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

#define LOG "/tmp/g01c_tier_log.txt"

static FILE *log_fp(void) { return fopen(LOG, "a"); }

pid_t  start_music(const char *path)
{
    FILE *f = log_fp();
    if (f) { fprintf(f, "start:%s\n", path); fclose(f); }
    return 9999;
}

void  stop_music(pid_t pid)
{
    FILE *f = log_fp();
    if (f) { fprintf(f, "stop:%d\n", (int)pid); fclose(f); }
    (void)pid;
}
C

    # Headless game.h — replaces music.h includes with stub
    cat > /tmp/g01c_game_h.h <<'C'
#ifndef G01C_GAME_H
# define G01C_GAME_H

# include "libtci.h"
# include "libtciutil.h"
# include <sys/types.h>
# include <fcntl.h>
# include <unistd.h>
# include <stdlib.h>
# include <time.h>

# define LEVELS 15

typedef struct {
    char    *text;
    char    *opts[4];
    int      answer;
    char    *hint;
} question_t;

question_t  **load_questions(const char *path, int *count);
void          free_questions(question_t **questions, int count);
void          display_ladder(int level, int safe_level);
void          display_question(question_t *q, int hidden[4]);
void          display_audience(question_t *q);
void          display_win(void);
void          display_loss(int safe_level);
void          display_walkaway(int level);

extern const char  *PRIZES[];
extern const int    SAFE[];

pid_t  start_music(const char *path);
void   stop_music(pid_t pid);

void   game_loop(question_t **questions, int count);

#endif
C

    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' game.c  > /tmp/g01c_game.c
    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' load.c  > /tmp/g01c_load.c
    sed 's|#include "game.h"|#include "/tmp/g01c_game_h.h"|g' display.c > /tmp/g01c_display.c

    cat > /tmp/g01c_tier_test.c <<'C'
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "/tmp/g01c_game_h.h"

#define LOG "/tmp/g01c_tier_log.txt"

static int log_contains(const char *substr)
{
    FILE *f = fopen(LOG, "r");
    char  line[256];
    if (!f) return 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, substr)) { fclose(f); return 1; }
    }
    fclose(f);
    return 0;
}

static void log_clear(void) { fopen(LOG, "w"); }

int main(void)
{
    question_t **qs;
    int          count;

    qs = load_questions("fixtures/questions.txt", &count);
    if (!qs || count < 15) {
        printf("FAIL could not load questions\n");
        return 1;
    }

    /* Drive a full 15-question win with all-A answers (answer index 0) */
    log_clear();

    /* Redirect stdout to /dev/null for game output */
    int devnull = open("/dev/null", 1);
    int saved   = dup(1);
    dup2(devnull, 1);

    /* Feed: 15 'A\n' answers via a pipe */
    int pfd[2];
    pipe(pfd);
    for (int i = 0; i < 15; i++) write(pfd[1], "A\n", 2);
    close(pfd[1]);
    int saved_stdin = dup(0);
    dup2(pfd[0], 0);
    close(pfd[0]);

    game_loop(qs, count);

    dup2(saved, 1);
    close(saved);
    dup2(saved_stdin, 0);
    close(saved_stdin);
    close(devnull);

    /* Inspect log */
    int ok = 1;

    if (log_contains("start:music/tier1.wav"))
        printf("PASS tier1 music started at game start\n");
    else { printf("FAIL tier1 not started\n"); ok = 0; }

    if (log_contains("start:music/tier2.wav"))
        printf("PASS tier2 music started after Q5\n");
    else { printf("FAIL tier2 not started\n"); ok = 0; }

    if (log_contains("start:music/tier3.wav"))
        printf("PASS tier3 music started after Q10\n");
    else { printf("FAIL tier3 not started\n"); ok = 0; }

    if (log_contains("stop:9999"))
        printf("PASS stop_music called on game end\n");
    else { printf("FAIL stop_music not called on game end\n"); ok = 0; }

    free_questions(qs, count);
    return (ok ? 0 : 1);
}
C

    gcc -Wall -Wextra -std=c99 -D_POSIX_C_SOURCE=200112L -I. \
        /tmp/g01c_tier_test.c \
        /tmp/g01c_game.c \
        /tmp/g01c_load.c \
        /tmp/g01c_display.c \
        /tmp/g01c_music_stub.c \
        libtci.a libtciutil.a \
        -o /tmp/g01c_tier_test 2>/tmp/g01c_tier_build.log

    if [[ $? -ne 0 ]]; then
        fail "tier test compilation" "$(cat /tmp/g01c_tier_build.log)"
        return
    fi

    # Supply the fixtures path via argv through working directory symlink
    ln -sf "$FIXTURES" fixtures 2>/dev/null || true

    local output
    output=$(/tmp/g01c_tier_test 2>&1)
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
    [[ $fail_count -gt 0 ]] && exit 1
}

# ── main ──────────────────────────────────────────────────────────────────────

banner
preflight
prepare_silence
build
run_music_tests
run_tier_tests
summary
