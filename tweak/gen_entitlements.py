#!/usr/bin/env python3
"""生成各 target 的 entitlements plist。

用法:
  gen_entitlements.py <profile.plist> <bundle_id> <team_id> <out.plist> [profile_kind]

profile_kind:
  ent        企业 / 通配符描述文件（ProvisionsAllDevices=true 或 App ID 以 * 结尾）
              -> keychain / app-group 用 <team>.* 和 <team>.<bundle>.shared
  free       个人免费描述文件（Personal Team，7 天有效）
              -> 只保留 application-identifier + team-identifier + get-task-allow
                 （免费账号不支持 app groups / keychain 共享，带上反而会装不上）
  omit       不生成，直接返回 1（由调用方决定跳过该 target）

绑定具体 App ID 的描述文件（如企业包里写死 com.x.widget 的那种）会直接拒绝。
"""
import plistlib
import sys


def is_wildcard(profile: dict) -> bool:
    app_id = profile.get("Entitlements", {}).get("application-identifier", "")
    return app_id.endswith("*")


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    profile_plist, bundle_id, team_id, out = sys.argv[1:5]
    kind = sys.argv[5] if len(sys.argv) > 5 else "ent"

    if kind == "omit":
        print(f"skip {bundle_id} (profile does not cover it)", file=sys.stderr)
        return 1

    with open(profile_plist, "rb") as fh:
        profile = plistlib.load(fh)

    if not is_wildcard(profile):
        app_id = profile.get("Entitlements", {}).get("application-identifier", "?")
        print(f"profile App ID is '{app_id}' (not a wildcard) -> cannot sign '{bundle_id}'", file=sys.stderr)
        return 1

    ent = {
        "application-identifier": f"{team_id}.{bundle_id}",
        "com.apple.developer.team-identifier": team_id,
        "get-task-allow": bool(profile.get("Entitlements", {}).get("get-task-allow", False)),
    }

    if kind == "ent":
        ent["keychain-access-groups"] = [f"{team_id}.*"]
        ent["com.apple.security.application-groups"] = [f"{team_id}.{bundle_id}.shared"]

    with open(out, "wb") as fh:
        plistlib.dump(ent, fh)
    print(f"wrote {out} ({kind}) for {bundle_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
