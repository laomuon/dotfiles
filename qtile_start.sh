#!/bin/bash

# Qtile and the editor tools (pylsp, ruff, mypy) are `uv tool` installs in ~/.local/bin.
export PATH="/home/dmmuon/.local/bin:$PATH"
qtile start
