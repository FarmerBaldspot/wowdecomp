"""Ours: runs the forge window (Ours/Interface/OursForge.lua) without the game, against a stand-in for its frames
(mock.lua), and checks it (test.lua): the recipe written and read back for every kind of effect, shape and cast, a
recipe file of the server module's read the same, and the window shown, edited, previewed, answered, a recipe
loaded, a spell forged and forgotten, an icon picked. Then every recipe the window wrote is handed to the server
module's own reader and compiler (the editor's build of mod-spellforge's forge_check), which has to take it.

    python Ours/Tests/forge/check.py [<forge_check.exe> [<dbc folder>]]

Lua 5.1 is OpenMW's lua51.dll (a LuaJIT), loaded into Python: no Lua is installed on this machine.
"""

import ctypes
import glob
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FORK = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
EDITOR = r'C:\WOW_MODS\Project_WOW_Editor'
FORGE_CHECK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(EDITOR, 'build', 'spellforge', 'forge_check.exe')
DBC = sys.argv[2] if len(sys.argv) > 2 else r'C:\Build\bin\RelWithDebInfo\data\dbc'
EMBER = os.path.join(EDITOR, 'server', 'mod-spellforge', 'tools', 'recipes', 'ember-curse.sf')
KNOWN = [r'C:\Program Files\OpenMW*\lua51.dll', r'C:\Program Files\*\lua51.dll']


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
    lua.lua_pushcclosure.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
    GLOBALS = -10002                                         # (Lua 5.1's pseudo-index of the globals)

    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    lines = []
    printer = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(
        lambda s: (lines.append(lua.lua_tolstring(s, 1, None).decode('utf-8', 'replace')), 0)[1])
    lua.lua_pushcclosure(state, ctypes.cast(printer, ctypes.c_void_p), 0)
    lua.lua_setfield(state, GLOBALS, b'print')
    if os.path.exists(EMBER):
        lua.lua_pushstring(state, open(EMBER, encoding='utf-8').read().encode('utf-8'))
        lua.lua_setfield(state, GLOBALS, b'EMBER_CURSE')

    def run(text, name):
        data = text.encode('utf-8')
        if lua.luaL_loadbuffer(state, data, len(data), name.encode()) or lua.lua_pcall(state, 0, 0, 0):
            print('%s fails: %s' % (name, lua.lua_tolstring(state, -1, None).decode('utf-8', 'replace')))
            return False
        return True

    checks = '''
CHECKS, FAILED = 0, 0
function CHECK (cond, what)
    CHECKS = CHECKS + 1
    if not cond then FAILED = FAILED + 1; print("FAILED: " .. tostring(what)) end
end
'''
    ok = run(checks, 'checks') and run(open(os.path.join(HERE, 'mock.lua'), encoding='utf-8').read(), 'mock.lua') \
        and run(open(os.path.join(FORK, 'Ours', 'Interface', 'OursForge.lua'), encoding='utf-8').read(), 'OursForge.lua') \
        and run(open(os.path.join(HERE, 'test.lua'), encoding='utf-8').read(), 'test.lua')
    run('print("COUNT " .. CHECKS .. " " .. FAILED); for i, t in ipairs(FORGE_TEXTS) do print("TEXT " .. t) end', 'results')
    lua.lua_close(state)

    texts = [l[5:] for l in lines if l.startswith('TEXT ')]
    counts = [l for l in lines if l.startswith('COUNT ')]
    for line in lines:
        if not line.startswith(('TEXT ', 'COUNT ')):
            print(line)
    if not ok or not counts:
        print('the window did not run through')
        return 1
    checks_run, failed = map(int, counts[0].split()[1:])

    # The server's reader and compiler on every recipe the window wrote
    taken = 0
    with tempfile.TemporaryDirectory() as folder:
        files = []
        for i, text in enumerate(texts):
            path = os.path.join(folder, 'window_%02d.sf' % i)
            open(path, 'w', encoding='utf-8').write(text + '\n')
            files.append(path)
        result = subprocess.run([FORGE_CHECK, DBC, 'check'] + files, capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if line.startswith('== '):
                taken += 1
            elif line.startswith(folder) or ': line' in line:
                print('the server does not take it: ' + line.replace(folder, ''))
                failed += 1
    print('%d checks of the window, %d failed; %d of %d recipe(s) it wrote taken by the server\'s reader' % (
        checks_run, failed, taken, len(texts)))
    return 1 if failed or taken != len(texts) else 0


if __name__ == '__main__':
    sys.exit(main())
