#ifndef MUSIC_H
# define MUSIC_H

# include <sys/types.h>
# include <sys/wait.h>
# include <signal.h>
# include <unistd.h>

pid_t  start_music(const char *path);
void   stop_music(pid_t pid);

#endif
