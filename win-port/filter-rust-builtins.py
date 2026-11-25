"""Keep Zig's f128 compiler-runtime ABI when linking the Windows Rust archive."""

import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path


def conflicting_members(path: Path) -> list[str]:
    archive = path.read_bytes()
    if not archive.startswith(b"!<arch>\n"):
        raise ValueError(f"Expected a GNU static archive at {path}")

    symbols = names = b""
    offset = 8
    while offset < len(archive):
        header = archive[offset:offset + 60]
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError(f"Invalid archive member header at {offset}")
        size = int(header[48:58])
        start = offset + 60
        end = start + size
        if end > len(archive):
            raise ValueError(f"Truncated archive member at {offset}")
        name = header[:16].rstrip()
        if name == b"/":
            symbols = archive[start:end]
        elif name == b"//":
            names = archive[start:end]
        offset = end + size % 2

    if len(symbols) < 4:
        raise ValueError(f"Missing GNU symbol table in {path}")
    count, = struct.unpack_from(">I", symbols)
    offsets = struct.iter_unpack(">I", symbols[4:4 + 4 * count])
    symbol_names = symbols[4 + 4 * count:].split(b"\0", count)
    if len(symbol_names) != count + 1:
        raise ValueError(f"Invalid GNU symbol table in {path}")

    remove = set()
    for (offset,), symbol in zip(offsets, symbol_names):
        if not re.fullmatch(rb"(?:__[a-z0-9]*tf[a-z0-9]*|[a-z_]+f128)", symbol):
            continue
        name = archive[offset:offset + 16].rstrip()
        if name.startswith(b"/"):
            long_name_offset = int(name[1:])
            name = names[long_name_offset:].split(b"/\n", 1)[0]
        else:
            name = name.removesuffix(b"/")
        if name.startswith(b"compiler_builtins-"):
            remove.add(name.decode("ascii"))
    return sorted(remove)


def main() -> None:
    zig, source, output = sys.argv[1:]
    source = Path(source)
    output = Path(output)
    members = conflicting_members(source)
    shutil.copyfile(source, output)
    if members:
        subprocess.run([zig, "ar", "d", output, *members], check=True)
        if conflicting_members(output):
            raise RuntimeError("Rust compiler_builtins still provide f128 symbols")


if __name__ == "__main__":
    main()
