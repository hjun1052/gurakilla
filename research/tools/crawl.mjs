// Run with: ego-browser nodejs < crawl.mjs   (uses ego-browser's Node runtime fetch)
// Crawls a bank's security-install pages and the JS they load, saving raw
// copies and printing every line that references a macOS package or version.
const fs = await import("node:fs/promises");
const RAW = "/path/to/gurakilla/research/raw/";
const UA = { "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36", "accept-language": "ko-KR,ko;q=0.9" };
const BANKS = JSON.parse(await fs.readFile(RAW + "../tools/banks.json", "utf8"));
const only = (globalThis.process?.argv || []).find((a) => a.startsWith("--bank="))?.slice(7);

async function get(url) {
  try {
    const r = await fetch(url, { headers: UA, redirect: "follow", signal: AbortSignal.timeout(20000) });
    const buf = Buffer.from(await r.arrayBuffer());
    let text = buf.toString("utf8");
    if (/charset=(euc-kr|ks_c_5601)/i.test(r.headers.get("content-type") || "") || /charset=["']?euc-kr/i.test(text.slice(0, 2000))) {
      text = new TextDecoder("euc-kr").decode(buf);
    }
    return { ok: r.ok, status: r.status, url: r.url, text };
  } catch (e) { return { ok: false, status: 0, url, text: "", error: e.message }; }
}
const abs = (u, base) => { try { return new URL(u, base).href; } catch { return null; } };
const safe = (u) => u.replace(/^https?:\/\//, "").replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 150);

for (const bank of BANKS) {
  if (only && bank.id !== only) continue;
  const out = { bank: bank.id, pages: [], scripts: [], hits: [] };
  const queue = [...bank.start];
  const seen = new Set();
  while (queue.length && out.pages.length < (bank.maxPages || 6)) {
    const u = queue.shift();
    if (seen.has(u)) continue; seen.add(u);
    const r = await get(u);
    out.pages.push({ url: u, final: r.url, status: r.status, error: r.error });
    if (!r.text) continue;
    await fs.writeFile(RAW + bank.id + "__" + safe(r.url) + ".html", r.text);
    // follow security / install links on the same site
    for (const m of r.text.matchAll(/<a[^>]+href=["']([^"'#]+)["'][^>]*>([\s\S]{0,120}?)<\/a>/gi)) {
      const label = m[2].replace(/<[^>]+>/g, "").trim();
      if (/보안프로그램|보안센터|프로그램 설치|설치안내|보안모듈/.test(label)) {
        const a = abs(m[1], r.url); if (a && !seen.has(a) && /^https?:/.test(a)) queue.push(a);
      }
    }
    for (const m of r.text.matchAll(/<script[^>]+src=["']([^"']+)["']/gi)) {
      const a = abs(m[1], r.url);
      if (a && !out.scripts.includes(a) && /install|wizvera|veraport|delfino|astx|ahnlab|raon|touchen|nxkey|initech|crossweb|inisafe|anysign|xecure|ipinside|interezen|magicline|dream|nprotect|nos|ksign|kings|crossex|iniline|config|sec|secu/i.test(a)) out.scripts.push(a);
    }
  }
  for (const s of out.scripts.slice(0, bank.maxScripts || 40)) {
    const r = await get(s);
    if (!r.text) continue;
    await fs.writeFile(RAW + bank.id + "__" + safe(s) + ".js", r.text);
    r.text.split(/\n|;/).forEach((line) => {
      if (/(\.pkg|\.dmg)\b/i.test(line) || (/mac/i.test(line) && /(version|ver\b|down|url|pkg|install)/i.test(line) && line.length < 400)) {
        out.hits.push({ script: s, line: line.trim().slice(0, 260) });
      }
    });
  }
  await fs.writeFile(RAW + bank.id + "__summary.json", JSON.stringify(out, null, 2));
  console.log(`\n##### ${bank.id}: ${out.pages.length} pages, ${out.scripts.length} scripts, ${out.hits.length} hits`);
  out.pages.forEach((p) => console.log("  page", p.status, p.final || p.url, p.error || ""));
  [...new Map(out.hits.map((h) => [h.line, h])).values()].slice(0, 60).forEach((h) => console.log("  ", h.script.split("/").pop().split("?")[0], "|", h.line));
}
