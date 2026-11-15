#!/usr/bin/env python3
"""
Quick check after a CS2 update: does the plugin still find what it needs?
You don't have to start the server for this.

It looks at three things:
  * every Linux signature in src/ still matches, and only once
    (two matches would mean we might hook the wrong function)
  * every vtable we look up by class name is still there
  * with --plugin: game_fixes.so doesn't need anything the game libs don't have

Usage:
    tools/check_signatures.py <path to the cs2 "game" folder> [--plugin game_fixes.so]

Exit code 0 means all good. Needs python3, plus "nm" if you use --plugin.
"""
import os
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBS = {
    "server": "csgo/bin/linuxsteamrt64/libserver.so",
    "engine": "bin/linuxsteamrt64/libengine2.so",
}


class Elf:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            self.data = f.read()
        d = self.data
        if d[:4] != b"\x7fELF" or d[4] != 2:
            raise SystemExit(f"{path}: not a 64-bit ELF file")
        shoff, = struct.unpack_from("<Q", d, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from("<HHH", d, 0x3A)
        raw = []
        for i in range(shnum):
            name, typ, _flags, addr, off, size = struct.unpack_from("<IIQQQQ", d, shoff + i * shentsize)
            raw.append((name, typ, addr, off, size))
        stroff = raw[shstrndx][3]
        self.sections = {}
        for name, typ, addr, off, size in raw:
            end = d.index(b"\0", stroff + name)
            self.sections[d[stroff + name:end].decode()] = (typ, addr, off, size)
        # pointers are filled in by the loader, so read them from the relocation table
        self.relative = {}
        for sec in (".rela.dyn",):
            if sec not in self.sections:
                continue
            _t, _a, off, size = self.sections[sec]
            for o in range(off, off + size, 24):
                r_offset, r_info, r_addend = struct.unpack_from("<QQq", d, o)
                if (r_info & 0xFFFFFFFF) == 8:
                    self.relative[r_offset] = r_addend

    def section_bytes(self, name):
        _t, addr, off, size = self.sections[name]
        return addr, self.data[off:off + size]

    def in_section(self, name, addr):
        if name not in self.sections:
            return False
        _t, a, _o, size = self.sections[name]
        return a <= addr < a + size

    def find_pattern(self, pattern):
        """All addresses in .text matching an IDA-style pattern ("48 8B ? ?")."""
        rx = b"".join(b"." if tok in ("?", "??") else re.escape(bytes([int(tok, 16)])) for tok in pattern.split())
        addr, text = self.section_bytes(".text")
        # lookahead so overlapping matches get counted too
        return [addr + m.start() for m in re.finditer(b"(?=" + rx + b")", text, re.DOTALL)]

    def vtable(self, class_name, decorated=False):
        """Find a class's main vtable the same way DynLibUtils does at runtime."""
        ro_addr, rodata = self.section_bytes(".rodata")
        needle = (class_name if decorated else f"{len(class_name)}{class_name}").encode() + b"\0"
        pos = rodata.find(needle)
        if pos < 0:
            return None
        name_addr = ro_addr + pos
        by_value = {}
        for slot, value in self.relative.items():
            by_value.setdefault(value, []).append(slot)
        for ref in sorted(by_value.get(name_addr, [])):
            if not self.in_section(".data.rel.ro", ref):
                continue
            typeinfo = ref - 8
            for vref in sorted(by_value.get(typeinfo, [])):
                if not (self.in_section(".data.rel.ro", vref) or self.in_section(".data.rel.ro.local", vref)):
                    continue
                if vref - 8 in self.relative:
                    continue  # the slot before a vtable is a plain number, not a pointer
                sec = ".data.rel.ro" if self.in_section(".data.rel.ro", vref) else ".data.rel.ro.local"
                a, b = self.section_bytes(sec)
                if struct.unpack_from("<q", b, vref - 8 - a)[0] == 0:
                    return vref + 8
        return None

    def vtable_slots(self, vtable, limit=400):
        slots = []
        addr = vtable
        while addr in self.relative and self.in_section(".text", self.relative[addr]) and len(slots) < limit:
            slots.append(self.relative[addr])
            addr += 8
        return slots


def collect_from_source():
    """Pull every signature and vtable name straight out of the source files."""
    patterns, vtables = [], []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "src")):
        for name in sorted(files):
            if not name.endswith((".cpp", ".h", ".hpp")):
                continue
            path = os.path.join(dirpath, name)
            src = open(path, encoding="utf-8", errors="replace").read()
            rel = os.path.relpath(path, ROOT)
            for m in re.finditer(r"(\w+)\s*=\s*(?:modules\.)?(\w+)\.FindPattern\(ParseStringPattern\(WIN_LINUX\(\s*\"[^\"]*\"\s*,\s*\"([^\"]*)\"", src):
                var, module, pat = m.groups()
                patterns.append((rel, var, module, pat))
            for m in re.finditer(r"(?:modules\.)?(\w+)\.GetVirtualTableByName\(\"(\w+)\"\)", src):
                vtables.append((rel, m.group(1), m.group(2)))
    return patterns, vtables


def check_plugin_imports(plugin, game):
    def syms(path, flag):
        out = subprocess.run(["nm", "-D", flag, path], capture_output=True, text=True, check=True).stdout
        return {line.split()[-1].split("@")[0] for line in out.splitlines() if line.strip()}

    libdir = os.path.join(game, "bin/linuxsteamrt64")
    provided = set()
    for lib in ("libtier0.so", "libsteam_api.so"):
        provided |= syms(os.path.join(libdir, lib), "--defined-only")
    wanted = syms(plugin, "--undefined-only")
    # stuff every Linux box has (libc and friends)
    system = set()
    for lib in ("libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "ld-linux-x86-64.so.2", "libgcc_s.so.1"):
        for d in ("/lib/x86_64-linux-gnu", "/lib64", "/usr/lib64", "/usr/lib/x86_64-linux-gnu"):
            p = os.path.join(d, lib)
            if os.path.exists(p):
                system |= syms(p, "--defined-only")
                break
    weak = {line.split()[-1].split("@")[0]
            for line in subprocess.run(["nm", "-D", "--undefined-only", plugin], capture_output=True, text=True).stdout.splitlines()
            if len(line.split()) >= 2 and line.split()[-2] in ("w", "v")}
    return sorted(wanted - provided - system - weak), len(wanted & provided)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plugin = None
    if "--plugin" in sys.argv:
        plugin = sys.argv[sys.argv.index("--plugin") + 1]
        args = [a for a in args if a != plugin]
    if len(args) != 1:
        raise SystemExit(__doc__)
    game = args[0]

    inf = os.path.join(game, "csgo/steam.inf")
    if os.path.exists(inf):
        info = dict(line.strip().split("=", 1) for line in open(inf) if "=" in line)
        print(f"Game: CS2 {info.get('PatchVersion', '?')} ({info.get('VersionDate', '?')}), {game}\n")

    elfs = {key: Elf(os.path.join(game, rel)) for key, rel in LIBS.items()}
    alias = {"server": "server", "libserver": "server", "engine": "engine", "libengine": "engine"}
    patterns, vtables = collect_from_source()
    bad = 0

    print("Signatures")
    for rel, var, module, pat in patterns:
        elf = elfs[alias[module]]
        hits = elf.find_pattern(pat)
        if len(hits) == 1:
            status = f"ok    {hits[0]:#x}"
        elif not hits:
            status, bad = "MISSING", bad + 1
        else:
            status, bad = f"AMBIGUOUS ({len(hits)} matches, first {hits[0]:#x})", bad + 1
        print(f"  {status:<22} {os.path.basename(rel):<28} {var}")

    print("\nVtables by class name")
    seen = set()
    for rel, module, cls in vtables:
        if (module, cls) in seen:
            continue
        seen.add((module, cls))
        elf = elfs[alias[module]]
        vt = elf.vtable(cls)
        if vt is None:
            print(f"  MISSING                {cls} ({module})")
            bad += 1
        else:
            print(f"  ok    {vt:#x}  {cls} ({module}), {len(elf.vtable_slots(vt))} virtuals")

    if plugin:
        print("\nPlugin imports")
        missing, from_game = check_plugin_imports(plugin, game)
        if missing:
            bad += 1
            print(f"  MISSING: {len(missing)} symbol(s) the game libraries do not export:")
            for s in missing[:20]:
                print(f"    {s}")
        else:
            print(f"  ok    all imports resolve ({from_game} from the game's libtier0 / libsteam_api)")

    print("\n" + ("ALL GOOD" if not bad else f"{bad} PROBLEM(S) -- see above"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
