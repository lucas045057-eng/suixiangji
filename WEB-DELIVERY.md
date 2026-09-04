# 随想记 Web/PWA 交付说明

交付目录：`outputs/wealthmate/`

## 打开方式

在工作区根目录运行：

```text
python -m http.server 8080 --directory outputs/wealthmate
```

然后打开 <http://127.0.0.1:8080/>。使用静态服务器是因为 Service Worker 不会在 `file://` 页面启用。

## 已包含

- 首页总览：收入、支出、储蓄率、净资产、预算和近期账目
- 手工记账、编辑、软删除
- 一句话记账：金额/分类/账户草稿，必须点击“确认入账”后才会写入
- 财富页：资产、负债、净资产、应急金目标
- 预算页：80% 接近上限、100% 已超支状态
- 洞察与月报摘要
- localStorage 本地保存、恢复演示数据、JSON 导出
- Web App Manifest 与离线缓存 Service Worker

## 验收记录（2026-09-03）

- `npm test`：PASS，6/6
- `node --check outputs/wealthmate/app.js`：PASS
- `node --check outputs/wealthmate/service-worker.js`：PASS
- manifest JSON 解析：PASS
- 桌面浏览器：PASS。首页指标可见；“今天中午外卖 32 元，支付宝”生成 98% 餐饮支出草稿；确认前保持 12 笔，确认后变为 13 笔，支出变为 ¥5,320，净资产变为 ¥14,108，餐饮预算变为 ¥428 / ¥620。
- 刷新保留：PASS。确认后的 13 笔记录在刷新后仍然存在。
- 移动视口 390×844：PASS。实际 CSS 视口为 375px，文档 `scrollWidth` 为 375px，无横向滚动；底部/窄屏导航规则生效。

## 已知限制

这是本地 Web/PWA 演示版，不连接交接文档中的真实后端，不提供真实 JWT 登录、局域网同步、推送、Android APK 或 Windows 安装包。复杂投资组合、银行连接、外部 LLM、XLSX 导出和周度报告统计口径按文档保持未实现。
