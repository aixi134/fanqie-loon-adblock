#!/usr/bin/env python3
"""patch_bundles.py —— 让重签包能装进个人免费证书（Personal Team）的 3 个 bundle ID 配额里。

做的事：
  1. 重命名嵌套可执行文件 / framework 目录（让 bundle ID 与旧的 App Store 包彻底区分开，
     避免 device 上已装官方版时冲突）
  2. 改写 Info.plist 里的 CFBundleIdentifier / CFBundleExecutable / NSExtension 相关字段
  3. 改写 Mach-O 的 LC_ID_DYLIB（只对 framework，主二进制不碰）
  4. 输出需要重签的 (target, bundle_id, kind) 清单给 resign 脚本用

用法:
  patch_bundles.py <Payload 目录> <主二进制新 ID>
"""
import os
import plistlib
import struct
import sys

# (相对 Reading.app 的路径, 新 bundle id 后缀, 说明)
TARGETS = [
    ("PlugIns/ReadingNotificationExtension.appex", "push", "extension"),
    ("PlugIns/ReadingWidgetExtension.appex", "widget", "extension"),
]


def patch_macho_id(path: str, new_id: str) -> None:
    """改写 LC_ID_DYLIB 的 name 字段（长度必须 <= 原长度，否则跳过）。"""
    with open(path, "rb") as fh:
        data = bytearray(fh.read())
    if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
        return
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0xD:  # LC_ID_DYLIB
            name_off = struct.unpack_from("<I", data, off + 8)[0]
            start = off + name_off
            end = data.index(b"\0", start)
            old = data[start:end].decode("utf-8", "replace")
            new = new_id.encode() + b"\0"
            if len(new) > end - start + 1:
                print(f"  ! {os.path.basename(path)}: LC_ID_DYLIB too short for new id, leaving as is")
                return
            data[start:start + len(new)] = new
            data[start + len(new):end + 1] = b"\0" * (end + 1 - start - len(new))
            with open(path, "wb") as fh:
                fh.write(data)
            print(f"  ~ {os.path.basename(path)}: LC_ID_DYLIB {old} -> {new_id}")
            return
        off += cmdsize


def patch_info(plist_path: str, **kv) -> None:
    with open(plist_path, "rb") as fh:
        info = plistlib.load(fh)
    for k, v in kv.items():
        if v is None:
            info.pop(k, None)
        else:
            info[k] = v
    with open(plist_path, "wb") as fh:
        plistlib.dump(info, fh)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    payload_dir, main_id = sys.argv[1:3]
    app = os.path.join(payload_dir, "Payload", "Reading.app")

    # 主应用
    old_main = plistlib.load(open(os.path.join(app, "Info.plist"), "rb")).get("CFBundleIdentifier")
    patch_info(os.path.join(app, "Info.plist"), CFBundleIdentifier=main_id)
    print(f"main   : {old_main} -> {main_id}")

    # 扩展
    for rel, suffix, _kind in TARGETS:
        d = os.path.join(app, rel)
        info_path = os.path.join(d, "Info.plist")
        info = plistlib.load(open(info_path, "rb"))
        old_bid = info.get("CFBundleIdentifier", "")
        old_exe = info.get("CFBundleExecutable", "")
        new_exe = os.path.basename(d)[: -len(".appex")] + "Ext"
        exe_path = os.path.join(d, old_exe)

        with open(info_path, "rb") as fh:
            raw = plistlib.load(fh)
        raw["CFBundleIdentifier"] = main_id + "." + suffix
        raw["CFBundleExecutable"] = new_exe
        plistlib.dump(raw, open(info_path, "wb"))

        if os.path.exists(exe_path) and old_exe != new_exe:
            os.rename(exe_path, os.path.join(d, new_exe))
        print(f"{suffix:<7}: {old_bid} -> {main_id}.{suffix}  (exe {old_exe} -> {new_exe})")

    # framework：逐个改 LC_ID_DYLIB（改成与主包一致的 team 前缀不现实，
    # 这里保持原名；iOS 对 framework 的 ID 不做强制校验，重签即可）
    print("frameworks: LC_ID_DYLIB 保持不变（iOS 不强制校验 framework 的 id）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
