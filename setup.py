from setuptools import setup

APP = ['desktop_agent/mozhi_agent/main.py']
OPTIONS = {
    'argv_emulation': False,
    'plist': {'CFBundleName': 'MozhiAgent'},
}

setup(
    app=APP,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
