#!/usr/bin/env python3
"""Compares two inventory snapshots (from inventory.py) and prints a Markdown report.

Usage: python3 -I diff_inventory.py BEFORE.json AFTER.json
Process comparison uses executable paths (PIDs change on every restart);
certificates use SHA-256; launchd uses domain/label plus loaded state.
"""
import json, sys

IGNORE_PROC_PREFIX = ("/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/", "/private/var/folders/")


def load(p):
    return json.load(open(p))


def proc_paths(s):
    return {p["path"] for p in s["processes"] if p["path"].startswith("/") and not p["path"].startswith(IGNORE_PROC_PREFIX)}


def jobs(s):
    return {f'{j["domain"]}/{j["label"]}': j for j in s["launchd"]["jobs"] if j.get("label")}


def certs(s):
    # Keyed by subject + expiry + keychain: older snapshots lack sha256 (LibreSSL prints "SHA256 Fingerprint=").
    return {f'{c.get("subject")}|{c.get("notAfter")}|{c.get("keychain")}': c for c in s.get("certificates", [])}


def section(title, added, removed, fmt=str):
    out = [f"### {title}", ""]
    if not added and not removed:
        out.append("No change.")
    for a in sorted(added):
        out.append(f"- **added** {fmt(a)}")
    for r in sorted(removed):
        out.append(f"- **removed** {fmt(r)}")
    return out + [""]


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    out = [f"## Inventory diff: `{a['label']}` ({a['capturedAt']}) → `{b['label']}` ({b['capturedAt']})", ""]

    out += section("Package receipts", {r["id"] for r in b["receipts"]} - {r["id"] for r in a["receipts"]},
                   {r["id"] for r in a["receipts"]} - {r["id"] for r in b["receipts"]})

    ja, jb = jobs(a), jobs(b)
    out += section("launchd jobs", set(jb) - set(ja), set(ja) - set(jb))
    changed = [k for k in set(ja) & set(jb)
               if (ja[k].get("loaded"), ja[k].get("disabledKey")) != (jb[k].get("loaded"), jb[k].get("disabledKey"))]
    ov_a, ov_b = a["launchd"]["disabledOverrides"], b["launchd"]["disabledOverrides"]
    changed += [f"override {k}: {ov_a.get(k)} → {ov_b.get(k)}" for k in set(ov_a) | set(ov_b) if ov_a.get(k) != ov_b.get(k)]
    if changed:
        out += ["Changed state:", ""] + [f"- {c}" for c in sorted(changed)] + [""]

    ca, cb = certs(a), certs(b)
    out += section("Certificates (by subject + expiry)", set(cb) - set(ca), set(ca) - set(cb),
                   lambda h: f'{(cb.get(h) or ca.get(h)).get("commonName")} (expires {h.split("|")[1]})')
    trust_changed = [h for h in set(ca) & set(cb) if ca[h].get("trustDomains") != cb[h].get("trustDomains")]
    if trust_changed:
        out += ["Trust changed:", ""] + [f'- {ca[h]["commonName"]}: {ca[h]["trustDomains"]} → {cb[h]["trustDomains"]}' for h in trust_changed] + [""]

    out += section("Non-system process executables", proc_paths(b) - proc_paths(a), proc_paths(a) - proc_paths(b))

    ea, eb = a["extensions"], b["extensions"]
    out += section("System extensions", set(eb["systemextensionsctl"]) - set(ea["systemextensionsctl"]),
                   set(ea["systemextensionsctl"]) - set(eb["systemextensionsctl"]))
    out += section("/Library/Extensions", set(eb["libraryExtensions"]) - set(ea["libraryExtensions"]),
                   set(ea["libraryExtensions"]) - set(eb["libraryExtensions"]))

    def flat(d):
        return {f"{k}/{n}" for k, v in d.items() for n in (v if isinstance(v, list) else v.keys())}
    out += section("Vendor directories", flat(b["vendorDirectories"]) - flat(a["vendorDirectories"]),
                   flat(a["vendorDirectories"]) - flat(b["vendorDirectories"]))
    out += section("Browser native-messaging hosts", flat(b["nativeMessagingHosts"]) - flat(a["nativeMessagingHosts"]),
                   flat(a["nativeMessagingHosts"]) - flat(b["nativeMessagingHosts"]))

    ga = {p["id"] for p in a.get("gurakilla", {}).get("products", [])}
    gb = {p["id"] for p in b.get("gurakilla", {}).get("products", [])}
    out += section("GuraKilla detections", gb - ga, ga - gb)
    print("\n".join(out))


if __name__ == "__main__":
    main()
