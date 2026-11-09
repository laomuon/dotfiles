#!/bin/bash

source /home/dmmuon/qtile-venv/bin/activate
# Qtile is installed with `uv tool` in ~/.local/bin. Everything else (pylsp, ruff, python) stays in qtile-venv.
# To roll back to 0.33, delete the next line.
export PATH="/home/dmmuon/.local/bin:$PATH"
qtile start
