// Run after editing site-config.js; generated HTML retains metadata without JS.
import { readFile, writeFile } from "node:fs/promises";
import { siteConfig, safeHttpsUrl } from "../js/site-config.js";
const htmlPath = new URL("../index.html", import.meta.url);
const escape = (value) =>
  value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
if (!safeHttpsUrl(siteConfig.siteUrl)) throw new Error("siteUrl must be an absolute HTTPS URL");
const title = `${siteConfig.name} - ${siteConfig.tagline}`;
const base = new URL(siteConfig.siteUrl);
const og = new URL(siteConfig.screenshots.og, base).href;
let html = await readFile(htmlPath, "utf8");
html = html.replace(/<title>.*?<\/title>/, `<title>${escape(title)}</title>`);
html = html.replace(
  /<link\s+rel="canonical"\s+href="[^"]*"\s*\/?\s*>/,
  `<link rel="canonical" href="${escape(base.href)}">`,
);
for (const [attribute, key, value] of [
  ["name", "description", siteConfig.description],
  ["property", "og:site_name", siteConfig.name],
  ["property", "og:title", title],
  ["property", "og:description", siteConfig.description],
  ["property", "og:url", base.href],
  ["property", "og:image", og],
  ["property", "og:image:alt", `${siteConfig.name}：记账，可以越来越简单。`],
])
  html = html.replace(
    new RegExp(`<meta\\s+${attribute}="${key}"\\s+content="[^"]*"\\s*\\/?\\s*>`),
    `<meta ${attribute}="${key}" content="${escape(value)}">`,
  );
await writeFile(htmlPath, html);
console.log("Static SEO metadata synchronized from site-config.js.");
