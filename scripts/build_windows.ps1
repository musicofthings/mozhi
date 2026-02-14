python -m pip install --upgrade pip
python -m pip install .[windows,tray]
python -m pip install pyinstaller
pyinstaller --name MozhiAgent --noconsole --onefile desktop_agent/mozhi_agent/main.py
