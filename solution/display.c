#include "game.h"

const char  *PRIZES[LEVELS] = {
    "£100", "£200", "£300", "£500",
    "£1,000", "£2,000", "£4,000", "£8,000",
    "£16,000", "£32,000", "£64,000", "£125,000",
    "£250,000", "£500,000", "£1,000,000"
};

const int   SAFE[LEVELS] = {
    0, 0, 0, 0, 1,
    0, 0, 0, 0, 1,
    0, 0, 0, 0, 0
};

void    display_ladder(int level, int safe_level)
{
    int  i;

    tci_printf("\n");
    for (i = LEVELS - 1; i >= 0; i--) {
        if (i == level)
            tci_printf("\033[33m");
        if (SAFE[i])
            tci_printf("\033[32m  *\033[0m");
        else
            tci_printf("   ");
        if (i == safe_level && i != level)  /* yellow takes priority when both match */
            tci_printf("\033[32m");
        tci_printf(" %2d: %s", i + 1, PRIZES[i]);
        if (i == level || (i == safe_level && i != level))
            tci_printf("\033[0m");
        tci_printf("\n");
    }
    tci_printf("\n");
}

void    display_question(question_t *q, int hidden[4])
{
    int         i;
    const char  letters[] = "ABCD";

    tci_printf("%s\n\n", q->text);
    for (i = 0; i < 4; i++) {
        if (!hidden[i])
            tci_printf("  %c. %s\n", letters[i], q->opts[i]);
    }
    tci_printf("\n");
}

void    display_audience(question_t *q)
{
    int  pcts[4];
    int  total;
    int  scaled;
    int  i;
    int  j;

    for (i = 0; i < 4; i++)
        pcts[i] = 2 + rand() % 8;          /* 2–9 raw points for wrong answers */
    pcts[q->answer] = 58 + rand() % 16;    /* 58–73 raw points for the correct answer */
    total = 0;
    for (i = 0; i < 4; i++)
        total += pcts[i];
    tci_printf("\nAsk the Audience:\n\n");
    for (i = 0; i < 4; i++) {
        scaled = (pcts[i] * 100) / total;
        tci_printf("  %c: ", "ABCD"[i]);
        for (j = 0; j < scaled / 3; j++)
            tci_printf("#");
        tci_printf(" %d%%\n", scaled);
    }
    tci_printf("\n");
}

void    display_win(void)
{
    tci_printf("\n\033[32m");
    tci_printf("  Congratulations! You have won £1,000,000!\n");
    tci_printf("\033[0m\n");
}

void    display_loss(int safe_level)
{
    tci_printf("\nWrong answer.\n");
    if (safe_level >= 0)
        tci_printf("You leave with %s.\n\n", PRIZES[safe_level]);
    else
        tci_printf("You leave with £0.\n\n");
}

void    display_walkaway(int level)
{
    tci_printf("\nYou walk away with %s.\n\n",
               level > 0 ? PRIZES[level - 1] : "£0");
}
