#!/usr/bin/env python3
"""Static inspection of downloaded installers. Never installs anything.

For each .pkg: signature + notarization, Distribution/PackageInfo metadata,
payload file list, install scripts and what they touch (launchd, certificates,
kexts, browser hosts). For .dmg: mounted read-only, inner .pkg/.app inspected.
Usage: python3 -I inspect_installers.py   (paths are fixed to research/)
"""
import json, os, re, glob, shutil, subprocess, xml.etree.ElementTree as ET

R = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DL, EX = os.path.join(R, "downloads"), os.path.join(R, "expanded")
ENV = dict(os.environ, LC_ALL="C")


def run(*a, timeout=300):
    r = subprocess.run(a, capture_output=True, text=True, env=ENV, timeout=timeout)
    return r.returncode, r.stdout, r.stderr


PATTERNS = {
    "launchd": r"Launch(Agents|Daemons)/[\w.\-]+\.plist|launchctl\s+(load|bootstrap|enable|kickstart|start)\b[^\n]*",
    "certificate": r"security\s+(add-trusted-cert|add-certificates|import|delete-certificate|remove-trusted-cert)[^\n]*|certutil\s+-[AD][^\n]*",
    "kext": r"[\w.\-]+\.kext|kextload|kmutil\s+load[^\n]*",
    "nativeMessaging": r"NativeMessagingHosts/[\w.\-]+\.json|NaviteMessagingHosts[^\n]*",
    "browserExtension": r"External Extensions|ExternalExtensions|extensions\.json|chrome-extension://\w+",
    "privilegedHelper": r"PrivilegedHelperTools/[\w.\-]+|SMJobBless",
    "killall": r"\b(killall|pkill)\s+[^\n]*",
    "rm": r"\brm\s+-[rf]+[^\n]*",
    "consoleUser": r"getconsoleuser|stat -f\s*'?%Su'?\s*/dev/console|\$\(users\)",
    "networkPorts": r"\b(127\.0\.0\.1|localhost):?\d{2,5}",
}


def scan_text(text):
    found = {}
    for k, p in PATTERNS.items():
        hits = sorted({m.group(0).strip()[:200] for m in re.finditer(p, text)})
        if hits:
            found[k] = hits[:40]
    return found


def signature(path):
    code, out, err = run("/usr/sbin/pkgutil", "--check-signature", path)
    txt = out + err
    info = {"raw": txt.strip().splitlines()[:8]}
    m = re.search(r"Status: (.+)", txt)
    info["status"] = m.group(1).strip() if m else None
    m = re.search(r"Developer ID Installer: (.+?) \((\w{10})\)", txt)
    if m:
        info["signer"], info["teamID"] = m.group(1), m.group(2)
    info["notarized"] = "Notarization: trusted by the Apple notary service" in txt
    _, so, se = run("/usr/sbin/spctl", "-a", "-vv", "-t", "install", path)
    info["spctl"] = (so + se).strip().splitlines()[:4]
    _, so, se = run("/usr/bin/xcrun", "stapler", "validate", path)
    info["stapled"] = "worked" in (so + se)
    return info


def parse_distribution(path):
    try:
        root = ET.parse(path).getroot()
    except Exception as e:  # noqa: BLE001
        return {"_error": str(e)}
    d = {"title": (root.findtext("title") or "").strip()}
    opts = root.find("options")
    if opts is not None:
        d["hostArchitectures"] = opts.get("hostArchitectures")
        d["requireScripts"] = opts.get("require-scripts")
    vol = root.find("volume-check/allowed-os-versions/os-version")
    if vol is not None:
        d["minOS"] = vol.get("min")
    d["pkgRefs"] = [{"id": p.get("id"), "version": p.get("version"), "auth": p.get("auth"),
                     "file": (p.text or "").strip() or None} for p in root.iter("pkg-ref") if p.get("version") or p.text]
    scripts = root.findtext("script") or ""
    if scripts.strip():
        d["installerJS"] = scan_text(scripts)
        m = re.findall(r"system\.version\.ProductVersion[^;]{0,80}", scripts)
        d["osChecks"] = m[:5]
    return d


def inspect_pkg(pkg, label):
    out = {"file": os.path.relpath(pkg, R), "signature": signature(pkg)}
    os.makedirs(EX, exist_ok=True)
    dest = os.path.join(EX, label)
    shutil.rmtree(dest, ignore_errors=True)
    code, _, err = run("/usr/sbin/pkgutil", "--expand", pkg, dest)
    if code != 0:
        out["_expandError"] = err.strip()
        return out
    dist = os.path.join(dest, "Distribution")
    if os.path.exists(dist):
        out["distribution"] = parse_distribution(dist)
    comps = []
    for pi in sorted(glob.glob(os.path.join(dest, "**", "PackageInfo"), recursive=True)):
        comp_dir = os.path.dirname(pi)
        root = ET.parse(pi).getroot()
        c = {"identifier": root.get("identifier"), "version": root.get("version"),
             "installLocation": root.get("install-location"), "auth": root.get("auth"),
             "dir": os.path.relpath(comp_dir, dest)}
        sc = root.find("scripts")
        c["declaredScripts"] = {s.tag: s.get("file") for s in sc} if sc is not None else {}
        bom = os.path.join(comp_dir, "Bom")
        if os.path.exists(bom):
            _, lst, _ = run("/usr/bin/lsbom", "-s", "-f", bom)  # files only
            base = c["installLocation"] or "/"
            files = [os.path.normpath(os.path.join(base, f.lstrip("./"))) for f in lst.split("\n") if f.strip()]
            c["payloadFileCount"] = len(files)
            tops = sorted({"/".join(f.split("/")[:4]) for f in files})
            c["payloadTopLevel"] = tops[:60]
            c["payloadHighlights"] = sorted({f for f in files if re.search(
                r"Launch(Agents|Daemons)/|\.kext|NativeMessagingHosts|PrivilegedHelperTools|\.(cer|crt|pem|der|p12)$|/MacOS/[^/]+$", f)})[:80]
        sdir = os.path.join(comp_dir, "Scripts")
        if os.path.isdir(sdir):
            c["scripts"] = {}
            for f in sorted(os.listdir(sdir)):
                p = os.path.join(sdir, f)
                if os.path.isfile(p):
                    _, ftype, _ = run("/usr/bin/file", "-b", p)
                    entry = {"type": ftype.strip()[:80], "bytes": os.path.getsize(p)}
                    if "text" in ftype or "script" in ftype:
                        entry["touches"] = scan_text(open(p, errors="ignore").read())
                    c["scripts"][f] = entry
        comps.append(c)
    out["components"] = comps
    return out


def inspect_dmg(dmg, label):
    out = {"file": os.path.relpath(dmg, R)}
    _, so, se = run("/usr/bin/codesign", "-dv", "--verbose=2", dmg)
    out["dmgSignature"] = [l for l in (so + se).splitlines() if l.startswith(("Authority", "TeamIdentifier"))]
    mnt = os.path.join("/tmp", "gk-" + label)
    os.makedirs(mnt, exist_ok=True)
    code, _, err = run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mnt, dmg)
    if code != 0:
        out["_mountError"] = err.strip()
        return out
    try:
        out["contents"] = sorted(os.listdir(mnt))
        inner = []
        for p in glob.glob(os.path.join(mnt, "**", "*.pkg"), recursive=True) + glob.glob(os.path.join(mnt, "*.mpkg")):
            inner.append(inspect_pkg(p, label + "-" + os.path.basename(p).replace(" ", "_")))
        for a in glob.glob(os.path.join(mnt, "*.app")):
            _, so, se = run("/usr/bin/codesign", "-dv", "--verbose=2", a)
            inner.append({"app": os.path.basename(a), "signature": [l for l in (so + se).splitlines()
                                                                  if l.startswith(("Authority", "TeamIdentifier", "Identifier"))]})
            # Installer apps often embed a pkg in Resources.
            for p in glob.glob(os.path.join(a, "Contents", "Resources", "**", "*.pkg"), recursive=True):
                inner.append(inspect_pkg(p, label + "-" + os.path.basename(p).replace(" ", "_")))
        out["inner"] = inner
    finally:
        run("/usr/bin/hdiutil", "detach", mnt, "-force")
    return out


def main():
    manifest = json.load(open(os.path.join(DL, "manifest.json")))
    results = []
    for m in manifest:
        path = os.path.join(DL, m["file"])
        r = inspect_dmg(path, m["id"]) if path.endswith(".dmg") else inspect_pkg(path, m["id"])
        results.append({**m, "inspection": r})
        sig = r.get("signature") or {}
        print(f'{m["id"]:24} {sig.get("status") or r.get("dmgSignature")} team={sig.get("teamID")} notarized={sig.get("notarized")}')
    json.dump(results, open(os.path.join(R, "installers.json"), "w"), indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
