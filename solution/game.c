#include "game.h"

static char read_input(void)
{
    char  c;
    char  flush;

    if (read(0, &c, 1) <= 0)
        return ('\0');
    read(0, &flush, 1);
    return (tci_toupper(c));
}

static void handle_lifeline(question_t *q, int *flags, int hidden[4],
                             char choice)
{
    int  i;
    int  removed;

    if (choice == '1' && *flags & 1) {
        removed = 0;
        for (i = 0; i < 4 && removed < 2; i++) {
            if (i != q->answer) {
                hidden[i] = 1;
                removed++;
            }
        }
        *flags &= ~1;
        tci_printf("\n50:50 — two wrong answers removed.\n\n");
    } else if (choice == '2' && *flags & 2) {
        if (q->hint)
            tci_printf("\nFriend says: %s\n\n", q->hint);
        else
            tci_printf("\nFriend says: The answer is %c.\n\n",
                       "ABCD"[q->answer]);
        *flags &= ~2;
    } else if (choice == '3' && *flags & 4) {
        display_audience(q);
        *flags &= ~4;
    } else {
        tci_printf("Lifeline not available.\n");
    }
}

void    game_loop(question_t **questions, int count)
{
    int          level;
    int          safe_level;
    int          lifelines;
    int          hidden[4];
    int          i;
    char         c;
    question_t  *q;
    pid_t        music_pid;

    level      = 0;
    safe_level = -1;
    lifelines  = 7;
    music_pid  = start_music("music/tier1.wav");
    while (level < LEVELS && level < count) {
        q = questions[level];
        for (i = 0; i < 4; i++)
            hidden[i] = 0;
        display_ladder(level, safe_level);
        if (SAFE[level])
            safe_level = level;
        tci_printf("Level %d — %s\n\n", level + 1, PRIZES[level]);
        display_question(q, hidden);
        tci_printf("[1] 50:50  [2] Phone  [3] Audience  "
                   "[W] Walk away\n");
        tci_printf("Your answer (A-D): ");
        while (1) {
            c = read_input();
            if (c == 'A' || c == 'B' || c == 'C' || c == 'D')
                break;
            if (c == '1' || c == '2' || c == '3' || c == 'W') {
                if (c == 'W') {
                    stop_music(music_pid);
                    display_walkaway(level);
                    free_questions(questions, count);
                    return ;
                }
                handle_lifeline(q, &lifelines, hidden, c);
                display_question(q, hidden);
                tci_printf("Your answer (A-D): ");
            }
        }
        if (c - 'A' == q->answer) {
            tci_printf("\nCorrect!\n");
            level++;
            if (level == 5) {
                stop_music(music_pid);
                music_pid = start_music("music/tier2.wav");
            } else if (level == 10) {
                stop_music(music_pid);
                music_pid = start_music("music/tier3.wav");
            }
            if (level == LEVELS) {
                stop_music(music_pid);
                display_win();
                break;
            }
        } else {
            stop_music(music_pid);
            display_loss(safe_level);
            break;
        }
    }
    free_questions(questions, count);
}
