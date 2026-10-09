import { chromium } from "playwright";
import AxeBuilder from "@axe-core/playwright";
import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";

const url = (process.env.WEBSITE_URL || "http://127.0.0.1:8081").replace(/\/$/, "");
const output = new URL("../test-results/", import.meta.url);
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: "chrome", headless: true });
const report = { url, viewports: [], checks: [], errors: [], accessibility: [] };
try {
  const context = await browser.newContext({ reducedMotion: "reduce", deviceScaleFactor: 1 });
  const page = await context.newPage();
  if (new URL(url).hostname === "suixiangji.icu") {
    const canonicalResponse = await page.goto("https://www.suixiangji.icu/");
    assert.equal(canonicalResponse.status(), 200);
    assert.equal(new URL(page.url()).origin, url);
    assert.equal(await page.title(), "随想记 - 极简至上，越用越懂你的 AI 记账");
    report.checks.push("valid HTTPS www redirects to the official apex homepage, without a blog redirect");
  }
  page.on("pageerror", (e) => report.errors.push(e.message));
  page.on("console", (msg) => {
    if (msg.type() === "error") report.errors.push(msg.text());
  });
  for (const width of [1920, 1440, 1366, 1024, 768, 390, 375]) {
    await page.setViewportSize({ width, height: width < 600 ? 844 : 960 });
    const response = await page.goto(url);
    assert.equal(response.status(), 200);
    await page.locator('[data-download-slot="android"] a').waitFor();
    const overflow = async () =>
      page.evaluate(() => ({
        width: innerWidth,
        scroll: document.documentElement.scrollWidth,
        body: document.body.scrollWidth,
      }));
    let dimensions = await overflow();
    assert.ok(
      dimensions.scroll <= width && dimensions.body <= width,
      `overflow at ${width}: ${JSON.stringify(dimensions)}`,
    );
    for (const id of ["cleanup", "shared", "categories", "again"]) {
      await page.locator(`#tab-${id}`).click();
      assert.equal(await page.locator(`#panel-${id}`).isVisible(), true);
      dimensions = await overflow();
      assert.ok(dimensions.scroll <= width && dimensions.body <= width, `${id} overflows at ${width}`);
    }
    report.viewports.push({
      width,
      documentWidth: dimensions.scroll,
      overflow: false,
      sceneSwitches: "PASS",
    });
    for (const id of ["recurring", "refund", "attribution", "first"])
      await page.locator(`#tab-${id}`).click();
    const accessibility = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    report.accessibility.push({
      width,
      violations: accessibility.violations.map((v) => ({
        id: v.id,
        impact: v.impact,
        nodes: v.nodes.map((n) => n.target),
      })),
    });
    assert.equal(accessibility.violations.length, 0, JSON.stringify(report.accessibility.at(-1)));
    if ([1440, 390].includes(width)) {
      await page.evaluate(() => scrollTo(0, 0));
      await page.screenshot({
        path: new URL(`preview-${width}.png`, output).pathname.replace(/^\/(\w:)/, "$1"),
        fullPage: true,
      });
      await page.screenshot({
        path: new URL(`hero-${width}.png`, output).pathname.replace(/^\/(\w:)/, "$1"),
      });
    }
  }
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(url);
  const menu = page.locator(".menu-toggle");
  await menu.focus();
  await page.keyboard.press("Enter");
  assert.equal(await menu.getAttribute("aria-expanded"), "true");
  await page.locator('#primary-nav a[href="#ai"]').focus();
  await page.keyboard.press("Escape");
  assert.equal(await menu.getAttribute("aria-expanded"), "false");
  assert.equal(await page.locator(".menu-toggle:focus").count(), 1);
  assert.equal(await page.locator("#primary-nav").evaluate((el) => el.inert), true);
  await menu.click();
  await page.locator('#primary-nav a[href="#download"]').first().click();
  assert.equal(await menu.getAttribute("aria-expanded"), "false");
  await page.waitForFunction(() => location.hash === "#download");
  assert.ok(
    await page
      .locator("#download")
      .evaluate((el) => el.getBoundingClientRect().top >= 72 && el.getBoundingClientRect().top < 160),
  );
  report.checks.push(
    "mobile menu: keyboard open, Escape close, focus return, inert hidden links, navigation anchor",
  );
  await menu.click();
  await page.locator("#download-title").click();
  assert.equal(await menu.getAttribute("aria-expanded"), "false");
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.waitForFunction(() => document.querySelector("#primary-nav").inert === false);
  assert.equal(await page.locator("#primary-nav").evaluate((el) => el.inert), false);
  assert.equal(await page.locator(".site-header.scrolled").count(), 1);
  for (const href of ["#home", "#ai", "#devices", "#download"]) {
    await page.locator(`#primary-nav a[href="${href}"]`).first().click();
    assert.equal(new URL(page.url()).hash, href);
  }
  report.checks.push("desktop navigation: all four section anchors, header scroll state");
  await page.locator("#tab-recurring").focus();
  await page.keyboard.press("ArrowRight");
  assert.equal(await page.locator("#tab-cleanup").getAttribute("aria-selected"), "true");
  await page.keyboard.press("Home");
  assert.equal(await page.locator("#tab-recurring").getAttribute("aria-selected"), "true");
  await page.locator('[data-demo-action="remember"]').click();
  assert.ok((await page.locator("#recurring-result").textContent()).includes("演示"));
  await page.locator('[data-demo-action="ignore"]').click();
  assert.ok((await page.locator("#recurring-result").textContent()).includes("忽略"));
  await page.locator("#tab-cleanup").click();
  await page.locator('[data-demo-action="cleanup"]').click();
  assert.equal(await page.locator("#cleanup-details").isVisible(), true);
  await page.locator('[data-demo-action="cleanup"]').click();
  assert.equal(await page.locator("#cleanup-details").isVisible(), false);
  report.checks.push("scene tabs: keyboard arrows and Home, demonstration actions, cleanup disclosure");
  assert.equal(await page.locator('[data-download-slot="windows"] a').count(), 0);
  assert.equal(await page.locator('[data-download-slot="windows"] button').isDisabled(), true);
  assert.ok((await page.locator('[data-download-slot="android"] a').getAttribute("href")).endsWith(".apk"));
  assert.equal(await page.locator('a[href=""], a[href="javascript:"]').count(), 0);
  const brokenFragments = await page.evaluate(() =>
    [...document.querySelectorAll('a[href^="#"]')]
      .filter((a) => !document.getElementById(a.hash.slice(1)))
      .map((a) => a.hash),
  );
  assert.deepEqual(brokenFragments, []);
  report.checks.push("download state: Android enabled, Windows disabled without link; no broken anchors");
  assert.equal(await page.locator("h1").count(), 1);
  assert.equal(await page.locator("html").getAttribute("lang"), "zh-CN");
  assert.equal(await page.title(), "随想记 - 极简至上，越用越懂你的 AI 记账");
  assert.ok(await page.locator('meta[name="description"]').getAttribute("content"));
  assert.equal(await page.locator('link[rel="canonical"]').getAttribute("href"), "https://suixiangji.icu/");
  for (const property of ["og:title", "og:description", "og:image", "og:url"])
    assert.ok(await page.locator(`meta[property="${property}"]`).getAttribute("content"));
  for (const path of [
    "/assets/images/favicon.svg",
    "/assets/images/og-image.png",
    "/styles/main.css",
    "/js/main.js",
  ]) {
    assert.equal(await page.evaluate(async (path) => (await fetch(path)).status, path), 200);
  }
  report.checks.push(
    "SEO and resources: title, description, canonical, OG, favicon, one H1, language, all assets served",
  );
  const downloads = await page.evaluate(
    async () => (await import("/js/site-config.js")).siteConfig.downloads,
  );
  assert.equal(downloads.android.artifactVerified, true);
  const liveConfig = await page.evaluate(async () => (await fetch("/js/site-config.js")).text());
  const unsafeContext = await browser.newContext();
  const unsafePage = await unsafeContext.newPage();
  await unsafePage.route("**/js/site-config.js", async (route) => {
    let body = liveConfig;
    body +=
      '\nsiteConfig.downloads.android.url = ""; siteConfig.downloads.windows.enabled = true; siteConfig.downloads.windows.url = "";';
    await route.fulfill({ status: 200, contentType: "text/javascript", body });
  });
  await unsafePage.goto(url);
  assert.equal(await unsafePage.locator('[data-download-slot="android"] button').isDisabled(), true);
  assert.equal(await unsafePage.locator('[data-download-slot="windows"] button').isDisabled(), true);
  assert.equal(await unsafePage.locator("[data-download-slot] a").count(), 0);
  report.checks.push("empty URLs fail closed even when enabled is true");
  await unsafeContext.close();
  assert.equal(await page.locator('[data-download-slot="android"] a').count(), 1);
  assert.equal(await page.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior), "auto");
  report.checks.push("reduced motion: smooth scrolling and reveal animation disabled");
  const noJs = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
  const fallback = await noJs.newPage();
  await fallback.goto(url);
  assert.equal(await fallback.locator("h1").isVisible(), true);
  assert.equal(await fallback.locator('[data-download-slot="android"] button').isDisabled(), true);
  assert.equal(await fallback.locator("noscript a").isVisible(), true);
  assert.equal(await fallback.evaluate(() => document.documentElement.scrollWidth), 390);
  await noJs.close();
  report.checks.push("no-JS fallback: content visible, download safely disabled, Releases link present");
  const animated = await browser.newContext({
    reducedMotion: "no-preference",
    viewport: { width: 1440, height: 960 },
  });
  const animatedPage = await animated.newPage();
  await animatedPage.goto(url);
  assert.equal(
    await animatedPage.evaluate(() => getComputedStyle(document.documentElement).scrollBehavior),
    "smooth",
  );
  await animatedPage.locator(".story-routine").scrollIntoViewIfNeeded();
  await animatedPage.waitForFunction(() =>
    document.querySelector(".story-routine").classList.contains("is-visible"),
  );
  await animated.close();
  report.checks.push("normal motion: smooth scroll enabled, intersection reveal visible");
  assert.deepEqual(report.errors, []);
  await context.close();
  report.result = "PASS";
} catch (error) {
  report.result = "FAIL";
  report.failure = error.stack;
  throw error;
} finally {
  await writeFile(new URL("browser-results.json", output), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  await browser.close();
}
