#!/usr/bin/env python3
"""在 Mach-O 主二进制里追加一条 LC_LOAD_DYLIB 注解，指向 /usr/lib/NoAd.dylib。

做法（不改动任何已有段/节的偏移，避免 __TEXT 签名哈希区间整体位移）：
  1. 在最后一个 load command 之后插入新的 LC_LOAD_DYLIB（64 字节）
  2. 新命令落在 __TEXT 段尾部、__DATA_CONST 之前，属于已映射文件内容：
     - 该区域原本是 __TEXT 的零填充/未使用字节，写进去后由 codesign 重新哈希即可
  3. ncmds +1，sizeofcmds +64；__TEXT.vmsize 不变，故不影响 __DATA_CONST 的 vmaddr

用法: patch_loadcmd.py <binary> <dylib_path>
"""
import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch_loadcmd.py <binary> <dylib_path>", file=sys.stderr)
        return 2
    binary, dylib = sys.argv[1], sys.argv[2]
    dylib_bytes = dylib.encode("utf-8") + b"\0"

    data = bytearray(open(binary, "rb").read())

    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, _res = struct.unpack_from(
        "<IiiIIIII", data, 0
    )
    if magic != 0xFEEDFACF:
        print(f"not a 64-bit little-endian Mach-O (magic={magic:#x})", file=sys.stderr)
        return 1

    # 走一遍 load commands，找到最后一条的结束位置和 __TEXT 段的边界
    off = 32
    end_of_cmds = 32
    text_filesize = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        end_of_cmds = off + cmdsize
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = bytes(data[off + 8 : off + 24]).split(b"\0")[0]
            if segname == b"__TEXT":
                _vmaddr, _vmsize, _fileoff, text_filesize = struct.unpack_from("<QQQQ", data, off + 24)
        off += cmdsize

    if text_filesize is None:
        print("no __TEXT segment found", file=sys.stderr)
        return 1
    if end_of_cmds + 64 > text_filesize:
        print("no slack between end of load commands and __TEXT end", file=sys.stderr)
        return 1

    # LC_LOAD_DYLIB: cmd(4) cmdsize(4) name_offset(4) timestamp(4)
    #                current_version(4) compat_version(4) + name
    name_off = 24
    cmdsize = (name_off + len(dylib_bytes) + 7) & ~7  # 8 字节对齐
    if end_of_cmds + cmdsize > text_filesize:
        print("dylib path too long for available slack", file=sys.stderr)
        return 1

    blk = bytearray(cmdsize)
    struct.pack_into("<IIIIII", blk, 0, 0xC, cmdsize, name_off, 2, 0x10000, 0x10000)
    blk[name_off : name_off + len(dylib_bytes)] = dylib_bytes
    data[end_of_cmds : end_of_cmds + cmdsize] = blk

    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmdsize)
    open(binary, "wb").write(data)

    print(f"added LC_LOAD_DYLIB {dylib!r} ({cmdsize} bytes) at {end_of_cmds:#x}")
    print(f"ncmds {ncmds} -> {ncmds + 1}, sizeofcmds {sizeofcmds} -> {sizeofcmds + cmdsize}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
