#!/usr/bin/env python3
"""Read-only system inventory for GuraKilla research.

Usage: python3 -I inventory.py OUT.json [--label NAME]

Captures processes (+ code-signing team IDs), launchd plists and live state,
launchd disabled overrides, non-Apple package receipts, app bundles,
system/kernel extensions, known vendor directories, browser native-messaging
hosts, and GuraKilla's own detection output. Changes nothing on the system.
"""
import json, os, plistlib, subprocess, sys, time, glob, pwd

ENV = dict(os.environ, LC_ALL="C", LANG="C")
HOME = os.path.expanduser("~")
UID = os.getuid()
GURAKILLA = os.path.join(os.path.dirname(__file__), "..", "..", "build", "Build", "Products", "Debug",
                         "GuraKilla.app", "Contents", "MacOS", "GuraKilla")

VENDOR_DIRS = [
    "/Applications/TouchEn nxKey", "/Applications/Veraport", "/Applications/Delfino",
    "/Applications/CrossWebEX", "/Applications/CrossEX", "/Applications/AhnLab",
    "/Applications/IPinside.app", "/Applications/MagicLine4NX", "/Applications/nProtect",
    "/Applications/SoftForum", "/Applications/KSign", "/Applications/Interezen",
    "/Library/Application Support/raonsecure", "/Library/Application Support/wizvera",
    "/Library/Application Support/iniLINE", "/Library/Application Support/ahnlab",
    "/Library/Application Support/Initech", "/Library/Application Support/SoftForum",
    "/Library/Application Support/DreamSecurity", "/Library/Application Support/Interezen",
    "/Library/Application Support/nProtect", "/Library/Application Support/INCA",
    "/Library/Frameworks/CrossWebEXFramework.framework", "/Library/Internet Plug-Ins",
    "/Library/Extensions", "/Library/PrivilegedHelperTools",
]
NMH_DIRS = [
    "/Library/Google/Chrome/NativeMessagingHosts",
    "/Library/Application Support/Google/Chrome/NativeMessagingHosts",
    "/Library/Application Support/Mozilla/NativeMessagingHosts",
    HOME + "/Library/Application Support/Google/Chrome/NativeMessagingHosts",
    HOME + "/Library/Application Support/Mozilla/NativeMessagingHosts",
    HOME + "/Library/Application Support/Microsoft Edge/NativeMessagingHosts",
    HOME + "/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
    HOME + "/Library/Application Support/Arc/User Data/NativeMessagingHosts",
]


def run(*args, timeout=60):
    try:
        r = subprocess.run(args, capture_output=True, text=True, env=ENV, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except Exception as e:  # noqa: BLE001
        return -1, "", str(e)


_sig_cache = {}


def signing(path):
    if path in _sig_cache:
        return _sig_cache[path]
    code, _, err = run("/usr/bin/codesign", "-dv", "--verbose=2", path)
    info = {"signed": code == 0}
    for line in err.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            if k in ("Identifier", "TeamIdentifier", "Authority") and k not in info:
                info[k] = v
    if code == 0:
        vcode, _, verr = run("/usr/bin/codesign", "--verify", "--no-strict", path)
        info["valid"] = vcode == 0
        if vcode != 0:
            info["verifyError"] = verr.strip()[:300]
    _sig_cache[path] = info
    return info


def system_path(p):
    return p.startswith(("/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/")) or "/Xcode" in p


def processes():
    _, out, _ = run("/bin/ps", "-axww", "-o", "pid=,ppid=,uid=,pcpu=,rss=,lstart=,comm=")
    rows = []
    for line in out.splitlines():
        parts = line.split(None, 10)
        if len(parts) < 11:
            continue
        pid, ppid, uid, cpu, rss = parts[:5]
        lstart = " ".join(parts[5:10])
        comm = parts[10]
        row = {"pid": int(pid), "ppid": int(ppid), "uid": int(uid), "cpu": float(cpu), "rssKB": int(rss),
               "start": lstart, "path": comm}
        try:
            row["user"] = pwd.getpwuid(int(uid)).pw_name
        except KeyError:
            pass
        if comm.startswith("/") and not system_path(comm) and os.path.exists(comm):
            row["signing"] = signing(comm)
        rows.append(row)
    return rows


def plist(path):
    try:
        with open(path, "rb") as f:
            return plistlib.load(f)
    except Exception as e:  # noqa: BLE001
        # Some vendor plists lack the <?xml ...?> header; launchd and plutil accept them, plistlib doesn't.
        code, out, _ = run("/usr/bin/plutil", "-convert", "xml1", "-o", "-", path)
        try:
            return plistlib.loads(out.encode()) if code == 0 else {"_error": str(e)}
        except Exception:  # noqa: BLE001
            return {"_error": str(e)}


def launchd():
    locs = [("/Library/LaunchAgents", f"gui/{UID}"), ("/Library/LaunchDaemons", "system"),
            (HOME + "/Library/LaunchAgents", f"gui/{UID}")]
    jobs = []
    for d, domain in locs:
        for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if not name.endswith(".plist"):
                continue
            p = os.path.join(d, name)
            data = plist(p)
            label = data.get("Label") if isinstance(data, dict) else None
            job = {"plist": p, "symlinkTarget": os.path.realpath(p) if os.path.islink(p) else None,
                   "domain": domain, "label": label,
                   "program": data.get("Program"), "programArguments": data.get("ProgramArguments"),
                   "runAtLoad": data.get("RunAtLoad"), "keepAlive": data.get("KeepAlive"),
                   "disabledKey": data.get("Disabled"), "owner": pwd.getpwuid(os.lstat(p).st_uid).pw_name}
            if label:
                code, out, _ = run("/bin/launchctl", "print", f"{domain}/{label}")
                job["loaded"] = code == 0
                for line in out.splitlines():
                    if line.startswith("\t") and not line.startswith("\t\t"):
                        s = line.strip()
                        if s.startswith("state = "):
                            job["state"] = s[8:]
                        elif s.startswith("pid = "):
                            job["pid"] = int(s[6:])
                        elif s.startswith("last exit code = "):
                            job["lastExit"] = s[17:]
                        elif s.startswith("runs = "):
                            job["runs"] = int(s[7:])
            jobs.append(job)
    overrides = {}
    for domain in (f"gui/{UID}", "system"):
        _, out, _ = run("/bin/launchctl", "print-disabled", domain)
        for line in out.splitlines():
            s = line.strip()
            if s.startswith('"') and '" => ' in s:
                lbl, val = s[1:].split('" => ', 1)
                overrides[f"{domain}/{lbl}"] = val.strip()
    return jobs, overrides


def receipts():
    _, out, _ = run("/usr/sbin/pkgutil", "--pkgs")
    res = []
    for pkg in sorted(out.split()):
        if pkg.startswith("com.apple."):
            continue
        _, info, _ = run("/usr/sbin/pkgutil", "--pkg-info", pkg)
        d = {"id": pkg}
        for line in info.splitlines():
            if ": " in line:
                k, v = line.split(": ", 1)
                d[k.strip()] = v.strip()
        res.append(d)
    return res


def bundles():
    res = []
    for pattern in ["/Applications/*.app", "/Applications/*/*.app", "/Applications/*/*/*.app",
                    "/Library/Application Support/*/*.app", "/Library/Application Support/*/*/*.app",
                    "/Library/Application Support/*/*/*/*.app"]:
        for p in glob.glob(pattern):
            info = plist(os.path.join(p, "Contents", "Info.plist"))
            res.append({"path": p, "bundleID": info.get("CFBundleIdentifier"),
                        "version": info.get("CFBundleShortVersionString"),
                        "teamID": signing(p).get("TeamIdentifier") if not system_path(p) else None})
    return sorted(res, key=lambda b: b["path"])


def extensions():
    _, sysext, _ = run("/usr/bin/systemextensionsctl", "list")
    _, kexts, kerr = run("/usr/bin/kmutil", "showloaded", "--list-only", "--show", "loaded", timeout=120)
    third_party = [l.strip() for l in kexts.splitlines() if "com.apple" not in l and l.strip()]
    lib_ext = sorted(os.listdir("/Library/Extensions")) if os.path.isdir("/Library/Extensions") else []
    return {"systemextensionsctl": sysext.strip().splitlines(),
            "loadedThirdPartyKexts": third_party, "kmutilError": kerr.strip()[:300] or None,
            "libraryExtensions": lib_ext}


def vendor_dirs():
    out = {}
    for d in VENDOR_DIRS:
        if os.path.exists(d):
            try:
                out[d] = sorted(os.listdir(d)) if os.path.isdir(d) else ["<file>"]
            except PermissionError:
                out[d] = ["<permission denied>"]
    return out


def native_messaging():
    out = {}
    for d in NMH_DIRS:
        if os.path.isdir(d):
            out[d] = {}
            for n in sorted(os.listdir(d)):
                try:
                    with open(os.path.join(d, n)) as f:
                        j = json.load(f)
                    out[d][n] = {"path": j.get("path"), "allowed": j.get("allowed_origins") or j.get("allowed_extensions")}
                except Exception as e:  # noqa: BLE001
                    out[d][n] = {"_error": str(e)}
    return out


def certificates():
    """Non-Apple certificates in System + login keychains, with trust-setting membership."""
    import tempfile
    trusted = {}
    for flag, domain in (("-d", "admin"), ("", "user")):
        args = ["/usr/bin/security", "dump-trust-settings"] + ([flag] if flag else [])
        _, out, _ = run(*args)
        for line in out.splitlines():
            if line.startswith("Cert ") and ": " in line:
                trusted.setdefault(line.split(": ", 1)[1].strip(), []).append(domain)
    res = []
    for kc in ("/Library/Keychains/System.keychain", HOME + "/Library/Keychains/login.keychain-db"):
        _, out, _ = run("/usr/bin/security", "find-certificate", "-a", "-p", kc)
        for block in out.split("-----END CERTIFICATE-----"):
            if "BEGIN CERTIFICATE" not in block:
                continue
            pem = block.strip() + "\n-----END CERTIFICATE-----\n"
            r = subprocess.run(["/usr/bin/openssl", "x509", "-noout", "-subject", "-issuer", "-enddate",
                                "-startdate", "-fingerprint", "-sha256", "-text", "-nameopt", "RFC2253"],
                               input=pem, capture_output=True, text=True, env=ENV)
            d = {"keychain": kc}
            for line in r.stdout.splitlines():
                line = line.strip()
                for key, pre in (("subject", "subject="), ("issuer", "issuer="), ("notAfter", "notAfter="),
                                 ("notBefore", "notBefore="), ("sha256", "sha256 Fingerprint=")):
                    if line.lower().startswith(pre.lower()):  # LibreSSL prints "SHA256 Fingerprint="
                        d[key] = line[len(pre):]
                if line.startswith("CA:"):
                    d["isCA"] = line.startswith("CA:TRUE")
                if line.startswith("Public Key Algorithm:"):
                    d["keyAlgorithm"] = line.split(":", 1)[1].strip()
            subj = d.get("subject", "")
            if "Apple" in subj and "Apple" in d.get("issuer", ""):
                continue
            cn = next((part.split("=", 1)[1] for part in subj.split(",") if part.strip().startswith("CN=")), subj)
            if "\\" in cn:  # RFC2253 hex escapes (\\ED\\95...) -> UTF-8
                import re
                raw = re.sub(r"\\([0-9A-Fa-f]{2})", lambda m: chr(int(m.group(1), 16)), cn)
                cn = raw.encode("latin-1", "ignore").decode("utf-8", "replace")
            d["commonName"] = cn
            d["selfSigned"] = d.get("subject") == d.get("issuer")
            d["trustDomains"] = trusted.get(cn, [])
            res.append(d)
    return res


def gurakilla():
    if not os.path.exists(GURAKILLA):
        return {"_error": "GuraKilla Debug build not found"}
    code, out, err = run(GURAKILLA, "--scan-json", timeout=180)
    try:
        return json.loads(out)
    except Exception:  # noqa: BLE001
        return {"_error": err[-500:] or out[-500:]}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    label = sys.argv[sys.argv.index("--label") + 1] if "--label" in sys.argv else "snapshot"
    started = time.time()
    jobs, overrides = launchd()
    _, osver, _ = run("/usr/bin/sw_vers", "-productVersion")
    _, build, _ = run("/usr/bin/sw_vers", "-buildVersion")
    _, sip, _ = run("/usr/bin/csrutil", "status")
    snap = {
        "label": label,
        "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "host": {"macOS": osver.strip(), "build": build.strip(), "arch": os.uname().machine, "sip": sip.strip()},
        "processes": processes(),
        "launchd": {"jobs": jobs, "disabledOverrides": overrides},
        "receipts": receipts(),
        "bundles": bundles(),
        "extensions": extensions(),
        "vendorDirectories": vendor_dirs(),
        "nativeMessagingHosts": native_messaging(),
        "certificates": certificates(),
        "gurakilla": gurakilla(),
    }
    snap["captureSeconds"] = round(time.time() - started, 1)
    with open(sys.argv[1], "w") as f:
        json.dump(snap, f, indent=2, ensure_ascii=False, default=str)
    print(f"wrote {sys.argv[1]} in {snap['captureSeconds']}s: "
          f"{len(snap['processes'])} processes, {len(jobs)} launchd jobs, {len(snap['receipts'])} receipts")


if __name__ == "__main__":
    main()
