NAME    = game
CC      = gcc
CFLAGS  = -Wall -Wextra -g -std=c99 -D_POSIX_C_SOURCE=200112L -I libtci
SRCS    = main.c load.c display.c game.c music.c
OBJS    = $(SRCS:.c=.o)
LIBS    = libtci/libtci.a libtci/libtciutil.a

.PHONY: all clean fclean re

all: $(NAME)

$(NAME): $(OBJS) $(LIBS)
	$(CC) $(CFLAGS) $(OBJS) $(LIBS) -o $(NAME)

$(LIBS):
	$(MAKE) -C libtci

%.o: %.c game.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	$(MAKE) -C libtci clean
	rm -f $(OBJS)

fclean: clean
	$(MAKE) -C libtci fclean
	rm -f $(NAME)

re: fclean all
