"""Run Lua against the installed PZ Kahlua VM, without launching the game.

The game bundles a JRE but no javac. Emit a tiny Java entry point (class version
49, straight-line bytecode) using only Python stdlib. Equivalent Java:

  J2SEPlatform platform = new J2SEPlatform();
  KahluaTable env = platform.newEnvironment();
  KahluaThread thread = new KahluaThread(platform, env);
  thread.debugOwnerThread = Thread.currentThread();
  LuaClosure fn = LuaCompiler.loadis(new InputStreamReader(
      new FileInputStream(args[0]), "ISO-8859-1"), args[0], env);
  System.out.println(thread.call(fn, null, null, null));

Kahlua's lexer decodes UTF-8 literal bytes itself. The Reader must preserve bytes,
including non-ASCII fixture text, rather than decoding them a second time.
No Java game objects are exposed. This verifies compiler/string/library behavior,
not Java rendering or live combat. All generated files and user.home are isolated
in a temporary directory; the supplied game installation is read-only.
"""
from pathlib import Path
import argparse
import struct
import subprocess
import tempfile


def entrypoint():
    pool = []
    def u2(n): return struct.pack('>H', n)
    def u4(n): return struct.pack('>I', n)
    def add(tag, body):
        pool.append(bytes([tag]) + body)
        return len(pool)
    def utf(s):
        data = s.encode('utf-8')
        return add(1, u2(len(data)) + data)
    def cls(s): return add(7, u2(utf(s)))
    def member(tag, owner, name, signature):
        c = cls(owner)
        nt = add(12, u2(utf(name)) + u2(utf(signature)))
        return add(tag, u2(c) + u2(nt))
    def method(owner, name, signature): return member(10, owner, name, signature)
    def op(code, index): return bytes([code]) + u2(index)
    p = 'se/krka/kahlua/j2se/J2SEPlatform'
    t = 'se/krka/kahlua/vm/KahluaThread'
    table = 'Lse/krka/kahlua/vm/KahluaTable;'
    closure = 'Lse/krka/kahlua/vm/LuaClosure;'
    obj = 'Ljava/lang/Object;'
    this, parent = cls('GodSystemKahluaProbe'), cls('java/lang/Object')
    code = op(0xbb, cls(p)) + b'\x59' + op(0xb7, method(p, '<init>', '()V')) + b'\x4c'
    code += b'\x2b' + op(0xb6, method(p, 'newEnvironment', '()' + table)) + b'\x4d'
    code += op(0xbb, cls(t)) + b'\x59\x2b\x2c' + op(0xb7, method(t, '<init>', '(Lse/krka/kahlua/vm/Platform;' + table + ')V')) + b'\x4e'
    code += b'\x2d' + op(0xb8, method('java/lang/Thread', 'currentThread', '()Ljava/lang/Thread;'))
    code += op(0xb5, member(9, t, 'debugOwnerThread', 'Ljava/lang/Thread;'))
    code += op(0xb2, member(9, 'java/lang/System', 'out', 'Ljava/io/PrintStream;')) + b'\x2d'
    code += op(0xbb, cls('java/io/InputStreamReader')) + b'\x59'
    code += op(0xbb, cls('java/io/FileInputStream')) + b'\x59\x2a\x03\x32'
    code += op(0xb7, method('java/io/FileInputStream', '<init>', '(Ljava/lang/String;)V'))
    code += op(0x13, add(8, u2(utf('ISO-8859-1')))) + op(0xb7, method('java/io/InputStreamReader', '<init>', '(Ljava/io/InputStream;Ljava/lang/String;)V'))
    code += b'\x2a\x03\x32\x2c' + op(0xb8, method('se/krka/kahlua/luaj/compiler/LuaCompiler', 'loadis', '(Ljava/io/Reader;Ljava/lang/String;' + table + ')' + closure))
    code += b'\x01\x01\x01' + op(0xb6, method(t, 'call', '(' + obj * 4 + ')' + obj))
    code += op(0xb6, method('java/io/PrintStream', 'println', '(' + obj + ')V')) + b'\xb1'
    main_name, main_type, code_name = utf('main'), utf('([Ljava/lang/String;)V'), utf('Code')
    body = u2(10) + u2(4) + u4(len(code)) + code + u2(0) + u2(0)
    main = u2(0x0009) + u2(main_name) + u2(main_type) + u2(1) + u2(code_name) + u4(len(body)) + body
    return b'\xca\xfe\xba\xbe' + u2(0) + u2(49) + u2(len(pool)+1) + b''.join(pool) + u2(0x0021) + u2(this) + u2(parent) + u2(0) + u2(0) + u2(1) + main + u2(0)


def run(source, game):
    game = Path(game).resolve()
    java = game / 'jre64/bin/java.exe'
    jar = game / 'projectzomboid.jar'
    if not java.is_file() or not jar.is_file():
        raise SystemExit('Expected a B42 installation with jre64 and projectzomboid.jar')
    with tempfile.TemporaryDirectory(prefix='godsystem-kahlua-') as folder:
        folder = Path(folder)
        (folder / 'GodSystemKahluaProbe.class').write_bytes(entrypoint())
        (folder / 'stdlib.lua').write_bytes((game / 'stdlib.lua').read_bytes())
        script = folder / 'probe.lua'
        script.write_text(source, encoding='utf-8')
        import os
        cp = os.pathsep.join([str(folder), str(jar), str(game / '*')])
        result = subprocess.run([str(java), '-Djava.awt.headless=true', '-Dstdout.encoding=UTF-8', '-Dstderr.encoding=UTF-8', '-Duser.home='+str(folder),
                                 '-cp', cp, 'GodSystemKahluaProbe', str(script)],
                                cwd=folder, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        return result.stdout.strip()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--game', required=True)
    parser.add_argument('script', type=Path)
    args = parser.parse_args()
    print(run(args.script.read_text(encoding='utf-8-sig'), args.game))
