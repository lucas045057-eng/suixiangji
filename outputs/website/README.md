# 随想记官方网站首页

完整独立单页官网，使用 HTML、CSS、Vanilla JavaScript；运行时无框架、无第三方脚本、无构建步骤。不会覆盖 `outputs/wealthmate/` Web/PWA。

## 本地运行

在项目仓库根目录执行：

```powershell
python -m http.server 8081 --bind 127.0.0.1 --directory outputs/website
```

访问 http://127.0.0.1:8081/ 。如果下载的是独立 website 文件夹，进入该文件夹，执行 `python -m http.server 8081 --bind 127.0.0.1`。需要静态 HTTP 服务以加载 ES modules，不要双击以 file:// 打开。

## 修改内容

`js/site-config.js` 集中管理产品名、Slogan、Description、canonical 域名、GitHub、Release、平台版本/大小/URL/状态、图片路径、AI 能力状态与提示。

- 下载入口默认安全降级：只有 enabled、artifactVerified、版本、实际文件大小及匹配当前 Release 的 HTTPS URL 全部有效时才渲染链接。
- Android 更新：先重新核实 GitHub 正式 Release 资产、完整下载与摘要，再更新全部相关字段。不要仅改 enabled。Windows 在公开正式安装包与验收存在之前保持禁用。
- AI 状态更新：先复审代码；状态、label、note 同时修改。场景文案与演示标签在 index.html 中明确标记当前状态，能力上线后一起更新。
- 真实截图：放入 assets/images/，更新 screenshots.android / windows 相对路径；自动替换对应 CSS UI；图片加载失败自动回退。保留原说明或替换成准确的截图说明。
- SEO 修改后运行 `node outputs/website/tools/sync-metadata.mjs`，同步初始 HTML 的 Title、Description、canonical 与 Open Graph。og-image.png 是本站自绘 1200×630 品牌占位图，发布前如需可替换。
- 正式地址为 https://suixiangji.icu/，已配置独立 HTTPS 并通过 Chrome 公网验收。www 自动跳转到主域名；HTTP 目前仍有阿里云备案拦截。

## 验证

根项目回归（仓库根目录）：`npm test`。

官网配置检查（无需安装依赖）：

```powershell
node --test outputs/website/tests/config.test.mjs
node --check outputs/website/js/main.js
```

浏览器验收仅使用开发依赖，页面运行无需 npm install。进入 outputs/website/ 后：

```powershell
npm ci
npm run test:browser
```

先启动 8081 静态服务器。浏览器验收使用已安装的 Google Chrome，无需下载浏览器。可用 `WEBSITE_URL` 指向其他本地端口。测试覆盖七种宽度、所有场景切换、无横向滚动、手机菜单、键盘操作、下载安全降级、资源/SEO、WCAG A/AA 自动检查、减少动态效果与无 JS 回退。结果及截图写入被忽略的 test-results/。

审计详情见 docs/PRODUCT-AUDIT.md；本轮真实验收见 docs/ACCEPTANCE.md。自动无障碍检查不等于完整人工读屏验收。

## 目录

```text
index.html                语义结构与静态 SEO
styles/main.css           品牌、Mockup、响应式与减少动态效果
js/site-config.js         集中配置与下载校验
js/main.js                导航、菜单、场景和下载入口
assets/images/            favicon、OG 占位图、可替换截图
tools/sync-metadata.mjs    集中配置同步至静态 SEO
tests/                    配置与真实浏览器验收
docs/                     产品审计与验收报告
```

部署只需要 index.html、styles/、js/、assets/。package.json、tests/、docs/、README 供维护与验收，可不放到公开服务器。

## HTTPS 部署与维护

部署工具和当前验收记录在 deployment/。在仓库根目录运行 `python outputs/website/tools/package-deployment.py`，生成 outputs/website/dist/suixiangji-website-deploy.tar.gz。部署包仅含官网运行文件、摘要清单和宿主机 Nginx 部署助手，不包含开发依赖或其他产品代码。

上传到已检查的服务器并解包后，运行 `sudo bash deploy-website.sh`。脚本校验摘要与 DNS，仅更新官网独立入口，备份旧版本；失败自动恢复。尚无官网证书时，默认尝试 HTTP-01。当前 HTTP 验证被拦截，因此实际部署先手工完成 DNS-01，脚本随后复用了官网有效证书。`--stage-http` 模式保留 HTTP 源站，并拒绝待签发官网 HTTPS 域名落入博客入口。

证书有效期至 2027-01-07（北京时间），当前没有自动续期，需到期前重新进行 DNS 验证并 reload Nginx。完整部署及网络探测范围见 deployment/DEPLOYMENT.md。源码同步不会重新发布已部署的官网。
