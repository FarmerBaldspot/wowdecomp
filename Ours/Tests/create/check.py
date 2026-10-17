"""Ours: runs the Spellforge realm's creation screen (Ours/Interface/OursCreate.lua) without the game, against the
forge's frame stand-in (../forge/mock.lua) and a stand-in for the game's GlueXML (glue.lua), and checks it
(test.lua): the distributions on the class buttons, the death knight's hidden, the class panel, the class's name
and resource, what a name may be, and Accept.

    python Ours/Tests/create/check.py

Lua 5.1 is OpenMW's lua51.dll (a LuaJIT), loaded into Python: no Lua is installed on this machine.
"""
import ctypes
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FORK = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
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
    lua.lua_pushcclosure.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
    GLOBALS = -10002

    state = lua.luaL_newstate()
    lua.luaL_openlibs(state)
    lines = []
    printer = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)(
        lambda s: (lines.append(lua.lua_tolstring(s, 1, None).decode('utf-8', 'replace')), 0)[1])
    lua.lua_pushcclosure(state, ctypes.cast(printer, ctypes.c_void_p), 0)
    lua.lua_setfield(state, GLOBALS, b'print')

    def run(path, name):
        data = open(path, encoding='utf-8').read().encode('utf-8') if path else name.encode('utf-8')
        label = os.path.basename(path) if path else 'inline'
        if lua.luaL_loadbuffer(state, data, len(data), label.encode()) or lua.lua_pcall(state, 0, 0, 0):
            print('%s fails: %s' % (label, lua.lua_tolstring(state, -1, None).decode('utf-8', 'replace')))
            return False
        return True

    checks = '''
CHECKS, FAILED = 0, 0
function CHECK (cond, what)
    CHECKS = CHECKS + 1
    if not cond then FAILED = FAILED + 1; print("FAILED: " .. tostring(what)) end
end
'''
    ok = run(None, checks) and run(os.path.join(FORK, 'Ours', 'Tests', 'forge', 'mock.lua'), '') \
        and run(os.path.join(HERE, 'glue.lua'), '') and run(os.path.join(FORK, 'Ours', 'Interface', 'OursCreate.lua'), '') \
        and run(os.path.join(HERE, 'test.lua'), '')
    run(None, 'print("COUNT " .. CHECKS .. " " .. FAILED)')
    lua.lua_close(state)
    counts = [l for l in lines if l.startswith('COUNT ')]
    for line in lines:
        if not line.startswith('COUNT '):
            print(line)
    if not ok or not counts:
        print('the creation screen did not run through')
        return 1
    checks_run, failed = map(int, counts[0].split()[1:])
    print('%d checks of the creation screen, %d failed' % (checks_run, failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
