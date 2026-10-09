import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { siteConfig, verifiedDownload, safeHttpsUrl } from "../js/site-config.js";

test("only the verified current Android release can be downloaded", () => {
  const apk = verifiedDownload("android");
  assert.ok(apk);
  assert.equal(apk.version, "1.0.4");
  assert.equal(apk.sizeBytes, 80143658);
  assert.ok(apk.url.includes(`/releases/download/${siteConfig.release.tag}/`));
  assert.equal(verifiedDownload("windows"), null);
});
test("empty, unsafe, stale, disabled or unverified URLs fail closed", () => {
  for (const changes of [
    { url: "" },
    { url: "javascript:alert(1)" },
    { url: "http://example.com/app.apk" },
    { url: "https://user:password@example.com/app.apk" },
    { enabled: false },
    { artifactVerified: false },
    { sizeBytes: 0 },
    { file: "source-folder" },
    { url: siteConfig.downloads.android.url.replaceAll("v1.0.4", "v1.0.3") },
    { url: "https://github.com/another/repo/releases/download/v1.0.4/app.apk" },
  ]) {
    const config = structuredClone(siteConfig);
    Object.assign(config.downloads.android, changes);
    assert.equal(verifiedDownload("android", config), null, JSON.stringify(changes));
  }
  assert.equal(verifiedDownload("nonexistent"), null);
  assert.equal(safeHttpsUrl(""), null);
});
test("feature audit covers every story and cannot assert complete implementation", () => {
  assert.equal(Object.keys(siteConfig.aiFeatures).length, 7);
  assert.equal(Object.values(siteConfig.aiFeatures).filter((f) => f.status === "PLANNED").length, 4);
  assert.equal(Object.values(siteConfig.aiFeatures).filter((f) => f.status === "PARTIAL").length, 3);
});
test("SEO is served in the initial HTML and follows the central configuration", async () => {
  const html = await readFile(new URL("../index.html", import.meta.url), "utf8");
  assert.equal((html.match(/<h1\b/g) || []).length, 1);
  assert.ok(html.includes('lang="zh-CN"'));
  assert.ok(html.includes(`<title>${siteConfig.name} - ${siteConfig.tagline}</title>`));
  assert.ok(html.includes(`<link rel="canonical" href="${siteConfig.siteUrl}">`));
  assert.ok(html.includes(`<meta name="description" content="${siteConfig.description}">`));
});
