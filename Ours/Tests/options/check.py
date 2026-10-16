"""Ours: runs our page of the game's Video options (Ours/Interface/OursVideoOptions.lua) without the game, together
with the game's own option code, and checks that it shows, sets, cancels and resets its settings as the game's own
pages do.

    python Ours/Tests/options/check.py [<the game's folder> [<the editor's wowtool.exe>]]

The game's OptionsPanelTemplates.lua and VideoOptionsPanels.lua are taken out of its archives with the editor's
wowtool. Lua 5.1 is OpenMW's lua51.dll (a LuaJIT), loaded into Python: no Lua is installed on this machine.
"""

import ctypes
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORK = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GAME = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\johan\Documents\WorldOfWarcraft\ChromieCraft_3.3.5a'
WOWTOOL = sys.argv[2] if len(sys.argv) > 2 else r'C:\WOW_MODS\Project_WOW_Editor\build\bin\wowtool.exe'
KNOWN = [r'C:\Program Files\OpenMW*\lua51.dll', r'C:\Program Files\*\lua51.dll']


def game_file(name, folder):
    path = os.path.join(folder, name)
    subprocess.run([WOWTOOL, GAME, 'extract', 'Interface\\FrameXML\\' + name, path], check=True, capture_output=True)
    return open(path, encoding='utf-8', errors='replace').read()


def main():
    libraries = [path for pattern in KNOWN for path in glob.glob(pattern)]
    if not libraries:
        print('No Lua 5.1 library on this machine: nothing was run.')
        return 2
    lua = ctypes.CDLL(libraries[0])
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.lua_tolstring.restype = ctypes.c_char_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.lua_close.argtypes = [ctypes.c_void_p]
    lua.luaL_loadbuffer.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lua.lua_setfield.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
    lua.lua_pushstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.lua_createtable.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    lua.lua_rawseti.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    lua.lua_pushcclosure.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
    GLOBALS = -10002                                         # (Lua 5.1's pseudo-index of the globals)

    with tempfile.TemporaryDirectory() as folder:
        files = [(name, game_file(name, folder)) for name in ('OptionsPanelTemplates.lua', 'VideoOptionsPanels.lua')]
    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    lines = []
    printer = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(
        lambda s: (lines.append(lua.lua_tolstring(s, 1, None).decode('utf-8', 'replace')), 0)[1])
    lua.lua_pushcclosure(state, ctypes.cast(printer, ctypes.c_void_p), 0)
    lua.lua_setfield(state, GLOBALS, b'print')
    lua.lua_createtable(state, len(files), 0)
    for i, (name, text) in enumerate(files):
        lua.lua_createtable(state, 0, 2)
        lua.lua_pushstring(state, name.encode())
        lua.lua_setfield(state, -2, b'name')
        lua.lua_pushstring(state, text.encode('utf-8'))
        lua.lua_setfield(state, -2, b'text')
        lua.lua_rawseti(state, -2, i + 1)
    lua.lua_setfield(state, GLOBALS, b'GAME_FILES')
    page = open(os.path.join(FORK, 'Ours', 'Interface', 'OursVideoOptions.lua'), encoding='utf-8').read()
    lua.lua_pushstring(state, page.encode('utf-8'))
    lua.lua_setfield(state, GLOBALS, b'OUR_PAGE')
    script = open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read().encode('utf-8')
    fault = None
    if lua.luaL_loadbuffer(state, script, len(script), b'mock.lua') or lua.lua_pcall(state, 0, 0, 0):
        fault = lua.lua_tolstring(state, -1, None).decode('utf-8', 'replace')
    lua.lua_close(state)
    print('\n'.join(lines))
    if fault:
        print('STOPPED: %s' % fault)
        return 1
    return 0 if lines and lines[-1] == 'ALL RIGHT' else 1


if __name__ == '__main__':
    sys.exit(main())
