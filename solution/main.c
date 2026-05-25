#include "game.h"

static void shuffle(question_t **arr, int n)
{
    int          i;
    int          j;
    question_t  *tmp;

    for (i = n - 1; i > 0; i--) {
        j      = rand() % (i + 1);
        tmp    = arr[j];
        arr[j] = arr[i];
        arr[i] = tmp;
    }
}

int main(int argc, char **argv)
{
    question_t  **questions;
    int          count;

    if (argc < 2) {
        tci_printf("usage: %s <questions.txt>\n", argv[0]);
        return (1);
    }
    srand((unsigned int)time(NULL));
    questions = load_questions(argv[1], &count);
    if (!questions)
        return (1);
    if (count < LEVELS) {
        tci_printf("error: need at least %d questions\n", LEVELS);
        free_questions(questions, count);
        return (1);
    }
    shuffle(questions, count);
    game_loop(questions, count);
    return (0);
}
