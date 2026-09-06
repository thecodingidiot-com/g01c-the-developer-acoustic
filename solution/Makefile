CC      = gcc
CFLAGS  = -Wall -Wextra -Werror -D_REENTRANT -D_POSIX_C_SOURCE=200112L -I libtci
BUILD   = -g -O0
RELEASE = -O2
LDFLAGS = $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf
SRCS    = main.c load.c game.c render.c font.c music.c
OBJS    = $(SRCS:.c=.o)
LIBS    = libtci/libtci.a
NAME    = game

.PHONY: all release clean fclean re

all: $(NAME)

$(NAME): $(OBJS) $(LIBS)
	$(CC) $(BUILD) $(OBJS) $(LIBS) $(LDFLAGS) -o $(NAME)

$(LIBS):
	$(MAKE) -C libtci

%.o: %.c game.h
	$(CC) $(CFLAGS) $(BUILD) -c $< -o $@

release:
	@$(MAKE) --no-print-directory fclean
	@$(MAKE) --no-print-directory BUILD="$(RELEASE)"
	strip $(NAME)

clean:
	$(MAKE) -C libtci clean
	rm -f $(OBJS)

fclean: clean
	$(MAKE) -C libtci fclean
	rm -f $(NAME)

re: fclean all
