#include "music.h"

pid_t  start_music(const char *path)
{
    pid_t  pid;

    pid = fork();
    if (pid == -1)
        return (-1);
    if (pid == 0)
    {
        execlp("aplay", "aplay", "-q", path, NULL);
        _exit(1);
    }
    return (pid);
}

void  stop_music(pid_t pid)
{
    if (pid <= 0)
        return ;
    kill(pid, SIGTERM);
    waitpid(pid, NULL, 0);
}
