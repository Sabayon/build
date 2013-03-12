# Do this or ssh localhost:123 screen -Rx won't source bashrc
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi
