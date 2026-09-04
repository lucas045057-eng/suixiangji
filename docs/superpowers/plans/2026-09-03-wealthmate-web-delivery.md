# WealthMate Web/PWA Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a polished, self-contained WealthMate Web/PWA package that can be opened locally and demonstrates the V1 accounting and wealth-planning loop.

**Architecture:** Reuse the existing dependency-free single-page WealthMate implementation as the domain/UI baseline, copy it into the current output directory, then add an installable web manifest, an offline service worker, and a small smoke-test harness. The app remains local-first and stores data in browser localStorage; no network or backend is required for the demo.

**Tech Stack:** HTML5, CSS3, ES modules, browser localStorage, SVG/CSS charts, Web App Manifest, Service Worker, Node built-in test runner.

**Spec:** `docs/superpowers/specs/2026-09-03-wealthmate-dual-track-design.md`

## Global Constraints

- 中文界面，产品名使用 `WealthMate`，副标题使用“你的钱，有自己的节奏”。
- 自然语言记账只生成待确认草稿，不能绕过确认直接入账。
- 净资产 = 资产账户余额之和 − 负债账户余额之和；储蓄率 = (收入−支出)/收入。
- 不引入第三方运行时依赖；产品必须由静态服务器直接提供。
- Web 交付位于 `outputs/wealthmate/`。

---

### Task 1: Copy and baseline the existing Web product

**Files:**
- Create: `outputs/wealthmate/index.html`
- Create: `outputs/wealthmate/styles.css`
- Create: `outputs/wealthmate/app.js`
- Test: `tests/wealthmate.test.mjs`
- Modify: `package.json`

**Interfaces:**
- Reuse `createSeedState()`, `deriveMetrics()`, `parseNaturalLanguage()`, `addTransaction()`, `getMonthlySeries()`, and `generateInsights()` from the existing Web MVP.
- `npm test` runs the domain regression suite from `tests/wealthmate.test.mjs`.

- [ ] **Step 1: Copy the known-good Web files into the current output path**

  Copy the existing `index.html`, `styles.css`, and `app.js` from `C:/Users/Admin/Documents/Codex/2026-09-01/https-workbuddy-link-p-ybtdnkq578vk89wsavr42q-https/outputs/wealthmate/` into `outputs/wealthmate/`, and copy `tests/wealthmate.test.mjs` plus `package.json` into the current workspace so the implementation is preserved as a baseline rather than retyped.

- [ ] **Step 2: Run the domain tests before adding packaging changes**

  Run `npm test` from the workspace root. Expected: the five existing domain tests pass, covering seed metrics, natural-language parsing, transaction updates, monthly series, and insight priority.

- [ ] **Step 3: Add the Web/PWA metadata test first**

  Extend `tests/wealthmate.test.mjs` with a test that reads `outputs/wealthmate/manifest.webmanifest` and `outputs/wealthmate/index.html` and asserts the manifest has name `WealthMate`, `display` `standalone`, and that `index.html` links to the manifest and registers `service-worker.js`.

- [ ] **Step 4: Run the new test and verify it fails for the missing packaging files**

  Run `npm test`. Expected: the existing domain tests pass and the new packaging test fails because the manifest and service-worker registration do not yet exist.

- [ ] **Step 5: Implement the minimal PWA packaging**

  Add the manifest and service worker described in Task 2, update `index.html` with `<link rel="manifest" href="./manifest.webmanifest" />`, and register the service worker from the module entry point only when `navigator.serviceWorker` is available. Keep the service worker cache limited to the three app assets and the manifest.

- [ ] **Step 6: Re-run the complete Node test suite**

  Run `npm test`. Expected: all domain and packaging tests pass with exit code 0.

### Task 2: Offline package and delivery notes

**Files:**
- Create: `outputs/wealthmate/manifest.webmanifest`
- Create: `outputs/wealthmate/service-worker.js`
- Modify: `outputs/wealthmate/index.html`
- Modify: `outputs/wealthmate/app.js`
- Create: `WEB-DELIVERY.md`

**Interfaces:**
- `manifest.webmanifest` exposes the product name, Chinese short name, standalone display, theme color, and 512/192 icons only if supplied by existing assets; do not invent binary assets.
- `service-worker.js` installs an immutable cache named `wealthmate-v1` and serves cached app assets before network fallback.
- `WEB-DELIVERY.md` documents how to serve the folder locally, localStorage behavior, and the acceptance flows.

- [ ] **Step 1: Write the manifest and service-worker files**

  Use valid JSON for the manifest and a small `install`/`fetch` service worker. The fetch handler must return the cached response for known static assets, then attempt the network, then return the cached `index.html` for navigation fallback.

- [ ] **Step 2: Add service-worker registration**

  Append a guarded registration call at the end of `outputs/wealthmate/app.js`; it must not execute in Node tests where `window` or `navigator` is missing.

- [ ] **Step 3: Write the delivery guide**

  Include the exact local static-server command `python -m http.server 8080 --directory outputs/wealthmate`, the URL `http://127.0.0.1:8080`, the fact that `file://` does not activate service workers, and the known scope limits from the specification.

- [ ] **Step 4: Run static syntax and packaging checks**

  Run `node --check outputs/wealthmate/app.js`, `node --check outputs/wealthmate/service-worker.js`, parse the manifest with `node -e "JSON.parse(require('fs').readFileSync('outputs/wealthmate/manifest.webmanifest','utf8'))"`, and run `npm test`. Expected: all commands exit 0.

### Task 3: Browser smoke verification

**Files:**
- Modify: `outputs/wealthmate/index.html` only if smoke verification finds a defect.
- Modify: `outputs/wealthmate/styles.css` only if smoke verification finds a layout defect.
- Modify: `outputs/wealthmate/app.js` only if smoke verification finds an interaction defect.

**Interfaces:**
- The product must render the dashboard without a console error, support navigation, open the natural-language composer, keep the draft unposted until confirmation, and update the budget/account metrics after confirmation.

- [ ] **Step 1: Start the static server**

  Serve `outputs/wealthmate/` on localhost and open the page in the available browser inspection surface.

- [ ] **Step 2: Verify desktop acceptance flows**

  Confirm the dashboard shows income, expense, savings rate, net worth, and recent transactions; open “一句话记账”; enter `今天中午外卖 32 元，支付宝`; verify the draft says 32 元/餐饮/支付宝/支出 and that no transaction is added before “确认入账”; click confirmation and verify the ledger, expense total, account balance, and food budget update.

- [ ] **Step 3: Verify persistence and recovery**

  Reload the page and verify the confirmed transaction remains. Use the restore-demo-data action and verify the seed totals return.

- [ ] **Step 4: Verify mobile layout**

  Inspect the page at a narrow viewport and verify bottom navigation, stacked cards, modal form controls, and no horizontal scroll.

- [ ] **Step 5: Record the actual result**

  Add a dated “Web acceptance” section to `WEB-DELIVERY.md` listing the commands and browser checks actually performed. Any unavailable browser or service-worker check must be recorded as BLOCKED, not PASS.
