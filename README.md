# g01c-the-developer-acoustic

Companion repository for **g01c — Who Wants to Be a Game Developer? Acoustic** at
[thecodingidiot.com](https://thecodingidiot.com).

---

## Follow my journey

Working through g01c alongside the implementation pages? Add the music
module to your g01a terminal game step by step, then run the tester.

Clone this repository and copy `test.sh` into your working directory:

```bash
git clone https://github.com/thecodingidiot-com/g01c-the-developer-acoustic.git
cp g01c-the-developer-acoustic/test.sh ~/g01c-practice/
cd ~/g01c-practice
make re
bash test.sh
```

All tests must pass before the chapter is complete.

---

## Follow your journey

Building the acoustic game independently? Here is the full project brief.

Start from the complete g01a terminal game (five source files: `main.c`,
`load.c`, `display.c`, `game.c`, `game.h`, plus `Makefile` and
`questions.txt`). Add two new files:

**music.h** — declares two functions:

```c
pid_t  start_music(const char *path);
void   stop_music(pid_t pid);
```

**music.c** — implements them:

- `start_music`: calls `fork()`. In the child, calls
  `execlp("aplay", "aplay", "-q", path, NULL)`. In the parent, returns
  the child's PID.
- `stop_music`: sends `SIGTERM` to the PID, then calls
  `waitpid(pid, NULL, 0)`.

**game.h** — add `#include "music.h"` after the existing system
includes.

**game.c** — add a `pid_t music_pid` local variable in `game_loop`.
Call `start_music("music/tier1.wav")` at game start. Switch to
`music/tier2.wav` when `level` reaches 5, and `music/tier3.wav` when
`level` reaches 10. Call `stop_music` on all exit paths (win, loss,
walk-away) before returning.

**Makefile** — add `music.c` to `SRCS`.

**music/** — create a directory with three royalty-free WAV files:

| File | Tier | Questions |
| --- | --- | --- |
| `music/tier1.wav` | 1 | 1–5 |
| `music/tier2.wav` | 2 | 6–10 |
| `music/tier3.wav` | 3 | 11–15 |

Source royalty-free tracks from [Freesound.org](https://freesound.org).
The tester does not verify audio content — only process lifecycle and
tier-switching logic.

---

## Building the solution

The `solution/` Makefile expects `libtci.a`, `libtciutil.a`, `libtci.h`,
and `libtciutil.h` in the `solution/libtci/` directory. Copy them from
your c01 build:

```bash
mkdir solution/libtci
cp libtci.a libtciutil.a libtci.h libtciutil.h solution/libtci/
mkdir solution/music
# copy your three WAV files here
cp tier1.wav tier2.wav tier3.wav solution/music/
cd solution
make
```

---

## What the tester checks

**Process lifecycle** — `start_music` returns a valid PID. The `aplay`
process is alive immediately after `start_music`. `stop_music` kills the
process. No zombie is left behind.

**Tier logic** — a headless build (no SDL2, no audio output) drives
`game_loop` with scripted answers and verifies that `start_music` is
called with `music/tier1.wav`, `music/tier2.wav`, and `music/tier3.wav`
at the correct level boundaries, and that `stop_music` is called on game
end.

---

## License

GPLv2. See [LICENSE](LICENSE).
