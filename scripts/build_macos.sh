#!/usr/bin/env bash
set -euo pipefail
python3 -m pip install --upgrade pip
python3 -m pip install '.[macos,tray]'
python3 -m pip install py2app
python3 setup.py py2app
