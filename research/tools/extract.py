#!/usr/bin/env python3
"""Builds processes.json and launchd.json (vendor-related only) from an inventory snapshot.

Usage: python3 -I extract.py SNAPSHOT.json OUTDIR
Attribution uses only exact identifiers: signing team, vendor install roots, launchd labels.
"""
import json, os, sys

# team -> product ids (verified from code signatures on this Mac)
TEAMS = {
    "9TKT2BJHQF": "RaonSecure", "C86MGS2A3T": "Wizvera", "BN4D26VM76": "Initech",
    "W77CBPNBYQ": "iniLINE", "G99MLRF664": "AhnLab", "BQNTQCRV77": "Interezen",
    "PVRBEFNNC6": "DreamSecurity", "R2PBZJ465V": "INCA Internet",
}
ROOTS = {
    "/Applications/TouchEn nxKey": "touchen-nxkey", "/Library/Application Support/raonsecure/TouchEn nxKey": "touchen-nxkey",
    "/Applications/Veraport": "wizvera-veraport", "/Applications/Delfino": "wizvera-delfino",
    "/Applications/CrossWebEX": "initech-crosswebex", "/Library/Application Support/iniLINE/CrossWebEX": "initech-crosswebex",
    "/Applications/CrossEX": "iniline-crossex", "/Library/Application Support/iniLINE/CrossEX": "iniline-crossex",
    "/Applications/AhnLab/ASTx": "ahnlab-astx", "/Applications/IPinside.app": "interezen-ipinside",
    "/Applications/MagicLine4NX": "dreamsecurity-magicline", "/Applications/nProtect": "inca-nprotect",
}
LABELS = {
    "com.raon.agent.touchen.nxkey": "touchen-nxkey", "com.raon.touchen.UserAgent": "touchen-nxkey",
    "com.raon.touchen.nxkey": "touchen-nxkey", "com.wizvera.veraport": "wizvera-veraport",
    "com.wizvera.delfino": "wizvera-delfino", "com.initech.INISAFECrossWebEXSvc": "initech-crosswebex",
    "kr.co.iniline.crossex-service": "iniline-crossex", "com.astx.firewall.Agent": "ahnlab-astx",
    "com.astx.firewall.Daemon": "ahnlab-astx", "com.interezen.nwsdaemon": "interezen-ipinside",
    "com.dreamsecurity.MagicLine4NX": "dreamsecurity-magicline", "com.nprotect.nosintgdmn": "inca-nprotect",
}


def under(path, root):
    return path == root or path.startswith(root.rstrip("/") + "/")


def product_for_path(path):
    for root, pid in ROOTS.items():
        if path and under(path, root):
            return pid
    return None


def main():
    snap = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    job_pids = {j["pid"]: LABELS[j["label"]] for j in snap["launchd"]["jobs"] if j.get("label") in LABELS and j.get("pid")}

    # ps reports argv[0]; GuraKilla's proc_pidpath gives the real executable.
    real = {q["pid"]: q["path"] for g in (snap.get("gurakilla") or {}).get("products", []) for q in g["processes"]}

    procs = []
    for p in snap["processes"]:
        if p["pid"] in real and real[p["pid"]] != p["path"]:
            import subprocess
            err = subprocess.run(["/usr/bin/codesign", "-dv", real[p["pid"]]], capture_output=True, text=True).stderr
            team = next((l.split("=", 1)[1] for l in err.splitlines() if l.startswith("TeamIdentifier=")), None)
            p = {**p, "argv0": p["path"], "path": real[p["pid"]], "signing": {"TeamIdentifier": team, "valid": None}}
        team = (p.get("signing") or {}).get("TeamIdentifier")
        prod = job_pids.get(p["pid"]) or product_for_path(p["path"])
        if not prod and team not in TEAMS:
            continue
        procs.append({
            "product": prod, "pid": p["pid"], "ppid": p["ppid"], "user": p.get("user"), "path": p["path"],
            "argv0": p.get("argv0"),
            "teamID": team, "vendor": TEAMS.get(team), "signatureValid": (p.get("signing") or {}).get("valid"),
            "cpu": p["cpu"], "rssKB": p["rssKB"], "runsAsRoot": p["uid"] == 0,
            "managedBy": next((j["domain"] + "/" + j["label"] for j in snap["launchd"]["jobs"] if j.get("pid") == p["pid"]), None),
            "evidence": "Verified",
        })

    jobs = []
    for j in snap["launchd"]["jobs"]:
        exe = j.get("program") or (j.get("programArguments") or [None])[0]
        prod = LABELS.get(j.get("label")) or product_for_path(exe or "") or product_for_path(j.get("symlinkTarget") or "")
        if not prod:
            continue
        target = f'{j["domain"]}/{j["label"]}'
        jobs.append({**j, "product": prod, "executable": exe,
                     "override": snap["launchd"]["disabledOverrides"].get(target),
                     "autoStart": bool(j.get("runAtLoad") or j.get("keepAlive")) and snap["launchd"]["disabledOverrides"].get(target) not in ("disabled", "true"),
                     "evidence": "Verified"})

    meta = {"source": os.path.basename(sys.argv[1]), "capturedAt": snap["capturedAt"], "host": snap["host"]}
    json.dump({**meta, "processes": procs}, open(os.path.join(out, "processes.json"), "w"), indent=2, ensure_ascii=False)
    json.dump({**meta, "jobs": jobs}, open(os.path.join(out, "launchd.json"), "w"), indent=2, ensure_ascii=False)
    print(f"{len(procs)} vendor processes, {len(jobs)} vendor launchd jobs")
    for p in procs:
        print(f'  {str(p["product"]):26} pid {p["pid"]:>6} {p["user"]:9} team={p["teamID"]} {p["path"]}')


if __name__ == "__main__":
    main()
