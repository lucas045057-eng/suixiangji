# 随想记官网 HTTPS 部署

官网：[https://suixiangji.icu/](https://suixiangji.icu/)。验收日期：2026-10-09（北京时间）。www 使用有效证书并自动跳转到主域名。

## 当前发布

- 官网独立入口：`/etc/nginx/conf.d/suixiangji-website.conf`。
- 版本目录：`/var/www/suixiangji-website/releases/20261009T024737Z-2074353`。
- 当前版本链接：`/var/www/suixiangji-website/current`。
- 发布前备份：`/var/www/suixiangji-website/backups/20261009T024737Z-2074353`。
- 证书：Let's Encrypt，覆盖 `suixiangji.icu` 和 `www.suixiangji.icu`。
- 证书到期：**2027-01-07 09:47:43（北京时间）**。

官网独立 HTTPS 源站返回 200，www 返回 301 到官网主域名；IPv4/IPv6 均通过证书和路由检查。6 个运行文件的安装文件与 HTTPS 响应 SHA-256 均符合 manifest.json。该清单的 sourceHead 为原开发基线，当前官网提交以 Git 历史为准。

原有 6 个 Nginx 配置文件摘要未变，4 个容器 ID 和镜像未变；博客和 API 的源站 HTTPS 检查正常。未修改后端、数据库、客户端或其他站点入口。

## 打包与发布

在仓库根目录运行：

```sh
python outputs/website/tools/package-deployment.py
```

输出 `outputs/website/dist/suixiangji-website-deploy.tar.gz`，包含官网 HTML、CSS、JS、图片、运行文件摘要和 deploy-website.sh，无开发依赖或其他产品代码。

上传到已检查的服务器，在独立目录解包后：

```sh
sudo bash deploy-website.sh
```

部署助手要求宿主机 Nginx 已运行，域名解析与预设服务器一致。它校验全部文件摘要、检查域名冲突、新建版本、备份官网自己的配置和入口，复用有效官网证书，验证配置后 reload 并等待就绪。失败时恢复官网原配置与版本入口。

`--stage-http` 用于尚未签发证书的 HTTP 源站准备，并拒绝官网域名的 HTTPS 请求落到默认博客站点。有效证书缺失时，正式模式默认尝试 Certbot HTTP-01；需要公网 HTTP 验证路径可达。

## DNS 验证与续期

当前公网 HTTP 与 HTTP-01 验证被阿里云备案系统返回 403。实际部署使用 DNS-01 验证取得独立官网证书，正式助手随后复用证书完成发布。需要使用 HTTPS 地址访问官网。

**当前没有自动续期。** 手工 DNS 验证的证书需在到期前重新验证；新申请会产生新的 TXT 值。完成续期后，通过 Nginx 配置检查并 reload。HTTP 验证恢复后，可切换到 webroot 并验证自动续期。[Certbot 手工验证说明](https://eff-certbot.readthedocs.io/en/stable/using.html#manual)

## 浏览器验收与网络范围

Chrome 公网访问和完整交互检查通过，未忽略 HTTPS 证书错误。覆盖七种宽度、手机菜单、桌面锚点、场景切换、下载安全状态、SEO、全部资源、无 JS 回退、减少动态效果；axe 自动检查均为零问题，控制台无错误。证据：browser-results.json。

当前工作区 curl.exe 直接 HTTPS 请求仍被连接重置，博客也有同样现象；上述 Chrome 公网访问正常。验收记录分别描述客户端结果，不宣称所有网络均可访问。

第一次直接运行本地浏览器脚本时，跨断点立即断言早于异步 resize 事件，随后已改为等待实际导航状态；资源与安全降级检查通过真实浏览器网络获取配置，以支持浏览器使用系统代理的环境。

## 回滚

备份包含 `website.conf.before` 与 `current.before`。恢复配置及其中记录的原版本链接，验证 Nginx 后 reload。此次发布前备份是官网尚未启用 HTTPS 的状态，回滚会暂停官网 HTTPS；博客和 API 配置不涉及回滚。
