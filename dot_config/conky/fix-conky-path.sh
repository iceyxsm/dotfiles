#!/bin/bash
# Fix conky path for current user
USER_HOME="$HOME"
sed -i "s|/home/[^/]*/.config/conky|$USER_HOME/.config/conky|g" ~/.config/conky/.conkyrc
