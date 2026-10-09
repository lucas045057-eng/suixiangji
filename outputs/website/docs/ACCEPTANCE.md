# 官网交付与验收

验收日期：2026-10-09（北京时间）。官网开发与本地验收完成；随后按用户授权部署到服务器。独立 HTTPS 已启用，公网 Chrome 浏览器验收通过；HTTP 与直接 curl 客户端限制详见 ../deployment/DEPLOYMENT.md。

```text
=== Website ===

Branch: feat/official-website
Base HEAD: 6a87b0ef694ae87ad5e8780839f5d568692ea09a
Website path: outputs/website/
Local URL: http://127.0.0.1:8081/

=== Current Product ===

Latest release: v1.0.4
Android version: 1.0.4 / build 7
Android APK: v1.0.4-build7-regression.apk
Android size: 80,143,658 bytes (80.14 MB)
Android URL: https://github.com/lucas045057-eng/suixiangji/releases/download/v1.0.4/v1.0.4-build7-regression.apk
Android verified: YES — complete download, size and SHA-256 matched
Android SHA-256: 93acc15e02095d06480ab6806a3d564de55bfab93e3d6ef11587257a75f2f3bd

Windows artifact: NOT AVAILABLE (no current public Release artifact)

=== AI Feature Audit ===

Recurring expenses: PLANNED
Ledger cleanup: PLANNED
Refund matching: PLANNED
AA / advance: PLANNED
Spending attribution: PARTIAL
Adaptive categories: PARTIAL
Personal aliases: PARTIAL

=== UI ===

Desktop: PASS
Tablet: PASS
Mobile: PASS
Horizontal overflow: NO
Navigation: PASS
Download: PASS
SEO: PASS
Accessibility basics: PASS
HTML validation: PASS (0 errors)
Console errors: NONE

=== Regression ===

Existing Web/PWA modified: NO
Flutter modified: NO
Backend modified: NO
Database modified: NO
npm test: PASS — existing root Web/PWA 7/7
Website config tests: PASS — 4/4

=== Files ===

Created:
outputs/website/.gitignore
outputs/website/index.html
outputs/website/styles/main.css
outputs/website/js/main.js
outputs/website/js/site-config.js
outputs/website/assets/images/favicon.svg
outputs/website/assets/images/og-image.png
outputs/website/package.json
outputs/website/package-lock.json
outputs/website/README.md
outputs/website/tools/sync-metadata.mjs
outputs/website/.gitattributes
outputs/website/tools/package-deployment.py
outputs/website/deployment/deploy-website.sh
outputs/website/deployment/manifest.json
outputs/website/deployment/DEPLOYMENT.md
outputs/website/deployment/browser-results.json
outputs/website/tests/config.test.mjs
outputs/website/tests/browser.mjs
outputs/website/docs/PRODUCT-AUDIT.md
outputs/website/docs/ACCEPTANCE.md

Modified: NONE — no existing tracked project files modified

=== Final ===

Website ready for server deployment: YES (static source and local acceptance ready)
Production deployment performed: YES — independent website HTTPS certificate and Nginx route deployed
Production availability: HTTPS PASS in real Chrome; HTTP blocked; direct curl HTTPS reset
Real Android/Windows device acceptance this round: NOT VERIFIED
Safari/Firefox this round: NOT VERIFIED
Full manual screen-reader audit: NOT VERIFIED
```

## 测试证据

真实浏览器：本机 Google Chrome，由 Playwright 控制；不是只做静态推断。

| 宽度 | 文档宽度 | 横向滚动 | 初始场景与切换后 |
|---|---|---|---|
| 1920 | 1920 | NO | PASS |
| 1440 | 1440 | NO | PASS |
| 1366 | 1366 | NO | PASS |
| 1024 | 1024 | NO | PASS |
| 768 | 768 | NO | PASS |
| 390 | 390 | NO | PASS |
| 375 | 375 | NO | PASS |

- 每个宽度都检查默认场景和清理、AA、分类、称呼第二次记录状态，确认根文档与 body 宽度没有超出视口。
- 桌面：首页/AI/多端/下载锚点全部点击通过，滚动后导航状态生效。
- 手机：键盘打开菜单、Escape 关闭、焦点回到按钮、隐藏菜单不可聚焦、点击锚点关闭菜单与正确停靠、点击外部关闭、跨断点恢复桌面导航通过。
- 场景：所有 Tab 点击切换；键盘方向键与 Home；记住/忽略演示反馈；清理项目展开/收起通过。演示不连接后台、不写入账本。
- 下载：Android 按真实配置显示可用 APK 链接；Windows disabled，DOM 中没有 Windows 下载链接；配置为 enabled=true 且空 URL 时仍安全禁用。
- SEO：单一 H1、zh-CN、初始 HTML Title/Description/canonical/OG；favicon、OG PNG、CSS、JS 返回 200。
- axe-core WCAG 2 A/AA、2.1 AA 自动检查：七种宽度默认场景均 0 violations；可见按钮、导航与 Tab 键盘基础另有真实交互验证。
- 普通动态效果：smooth scroll 与进入视口后可见通过；prefers-reduced-motion 时取消平滑滚动和动效通过。
- 禁用 JS：核心页面内容可见、下载保持安全禁用、GitHub Releases 回退入口可见、390px 无横向滚动。
- 控制台：正常浏览器验收没有 pageerror 或 console error。
- W3C Nu HTML Checker：0 errors。格式化工具产生的 47 条提示均为 void element 尾随斜线无效的格式提示；所有属性均已引用，不影响有效结构或浏览器解析。
- 人工视觉核查：1440px 首屏与全页、768px 首屏、390px 首屏/个人称呼场景/下载区；布局、文字与两种产品 Mockup 正常。
- 配置测试 4/4：有效正式下载、空/不安全/过期/未核实 URL 的禁用、七项审计状态、静态 SEO 与集中配置一致。
- `node --check`：main.js、site-config.js、sync-metadata.mjs 均通过。
- 根 `npm test`：真实执行，7 passed、0 failed；未改根测试脚本或原产品文件。
- 运行时资源约 138 KB（HTML+CSS+JS+favicon+OG 占位图；OG 不在首屏加载）；运行时没有第三方脚本、远程字体或图片请求。未执行 Lighthouse，因此不提供 Lighthouse 分数。

独立交付中的 verification/browser-results.json、verification/html-validation.json、verification/download-verification.json 与 Release 资产快照保存证据。test-results/ 和 node_modules/ 不进入源码补丁或源码 ZIP。

## 仓库与部署维护

官网从当时最新 origin/main 的基线 6a87b0ef694ae87ad5e8780839f5d568692ea09a 创建 feat/official-website 开发分支。源码和维护工具全部位于 outputs/website/；现有产品文件未修改。官网提交编号与合并状态以 Git 历史和 GitHub 合并请求为准，不将开发基线称作官网提交。

当前官网已启用独立 HTTPS，并通过 Chrome 公网验收。部署状态、当前目录、网络范围和手工证书续期要求见 ../deployment/DEPLOYMENT.md，公网浏览器证据见 ../deployment/browser-results.json。

部署工具还包括 .gitattributes、tools/package-deployment.py、deployment/deploy-website.sh 和 deployment/manifest.json。工具只打包官网运行文件；dist/、node_modules/ 与 test-results/ 不提交。

本地运行及维护方式见 ../README.md。上传源码到 GitHub 不会重启后端、修改客户端或重新发布官网。
