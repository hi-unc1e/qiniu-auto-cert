# 七牛云 CDN SSL 证书自动续期解决方案

> 让 Let's Encrypt 免费证书在七牛云 CDN 上永久有效的自动化方案

## 问题背景

七牛云 CDN 是国内常用的 CDN 服务之一，但很多用户在使用免费 SSL 证书时遇到了一个共同的痛点：

**七牛云上传的 SSL 证书有效期为 90 天，到期后需要手动更新。**

这个限制源于 Let's Encrypt 等 ACME 协议的 CA 颁发的免费证书本身只有 90 天有效期。虽然这是为了安全考虑，但对于运维人员来说，每 90 天手动更新一次证书是一件繁琐且容易忘记的事情。

### 传统解决方案的痛点

1. **手动续期**：设置日历提醒，每 90 天手动申请证书并上传到七牛云
2. **使用付费证书**：购买有效期 1 年的付费证书，但成本较高
3. **自建脚本**：编写自动化脚本，但需要维护服务器和定时任务

这些方案要么费时费力，要么成本较高，都不是理想的解决方案。

## 我们的解决方案

我们开发了一个基于 Docker 的自动化方案，结合 **acme.sh** 和七牛云 API，实现了证书的自动申请和续期：

### 核心特性

- ✅ **全自动续期**：剩余 7 天内自动续期，无需人工干预
- ✅ **多种验证方式**：支持 DNS 验证（Cloudflare、DNSPod、阿里云等）和 HTTP 验证
- ✅ **安全可靠**：所有敏感信息通过环境变量注入，不硬编码
- ✅ **数据持久化**：证书数据持久化存储，容器重启不会丢失
- ✅ **健康检查**：内置健康检查，确保证书状态正常
- ✅ **开箱即用**：提供 Docker Hub 镜像，一行命令即可部署

## 工作原理

```
┌─────────────┐      DNS/HTTP 验证      ┌──────────────┐
│   acme.sh   │ ─────────────────────▶  │ Let's Encrypt│
│  (证书申请)  │ ◀─────────────────────  │   (CA 服务器) │
└─────────────┘      获取证书            └──────────────┘
       │
       │  证书文件
       ▼
┌─────────────┐      API 上传            ┌──────────────┐
│  自动部署脚本 │ ─────────────────────▶  │   七牛云 CDN  │
└─────────────┘      更新证书            └──────────────┘
       │
       │  定时检查（每天）
       ▼
┌─────────────┐
│  守护进程   │ ◀── 剩余天数 < 7 天 ──┐
└─────────────┘                      │
                                     │
         ┌──────────────────────────┘
         │
         ▼
   重新申请和部署
```

### 续期流程

1. 容器启动时检查证书是否存在
2. 如不存在，使用 DNS 或 HTTP 验证申请新证书
3. 自动上传证书到七牛云 CDN
4. 每日检查证书有效期
5. 剩余天数 < 7 天时，自动续期并上传

## 快速开始

### 方式一：使用 Docker Hub 镜像

```bash
docker run -d \
  --name qiniu-auto-cert \
  --restart always \
  -e DOMAIN="buildbuffer.cdn.zuoxueba.org" \
  -e EMAIL="your-email@example.com" \
  -e QINIU_AK="your_qiniu_access_key" \
  -e QINIU_SK="your_qiniu_secret_key" \
  -e DNS_API="dns_cf" \
  -e CF_Token="your_cloudflare_token" \
  -v qiniu-acme-data:/root/.acme.sh \
  yingdao/qiniu-auto-cert:latest
```

### 方式二：使用 Docker Compose

```yaml
version: '3.8'

services:
  qiniu-auto-cert:
    image: yingdao/qiniu-auto-cert:latest
    container_name: qiniu-auto-cert
    restart: always
    environment:
      - DOMAIN=buildbuffer.cdn.zuoxueba.org
      - EMAIL=your-email@example.com
      - QINIU_AK=your_qiniu_access_key
      - QINIU_SK=your_qiniu_secret_key
      - DNS_API=dns_cf
      - CF_Token=your_cloudflare_token
    volumes:
      - acme-data:/root/.acme.sh

volumes:
  acme-data:
    driver: local
```

## 环境变量配置

| 变量 | 必需 | 说明 | 示例 |
|-----|------|------|-----|
| `DOMAIN` | ✅ | 要申请证书的域名 | `buildbuffer.cdn.zuoxueba.org` |
| `EMAIL` | ✅ | ACME 账号邮箱 | `admin@example.com` |
| `QINIU_AK` | ✅ | 七牛云 AccessKey | 从七牛云控制台获取 |
| `QINIU_SK` | ✅ | 七牛云 SecretKey | 从七牛云控制台获取 |
| `DNS_API` | ❌ | DNS 验证方式 | `dns_cf` / `dns_dp` / `dns_ali` 等 |
| `ACME_SERVER` | ❌ | ACME 服务器 | `letsencrypt` (默认) |
| `RENEW_DAYS` | ❌ | 续期阈值（天） | `7` (默认) |
| `CHECK_INTERVAL` | ❌ | 检查间隔（秒） | `86400` (默认，1天) |

### 支持的 DNS 验证方式

| DNS 服务商 | DNS_API 值 | 所需环境变量 |
|-----------|-----------|-------------|
| Cloudflare | `dns_cf` | `CF_Token` |
| DNSPod | `dns_dp` | `DP_Id`, `DP_Key` |
| 阿里云 | `dns_ali` | `Ali_Key`, `Ali_Secret` |
| 腾讯云 | `dns_cx` | `CX_Key`, `CX_Secret` |
| GoDaddy | `dns_gd` | `GD_Key`, `GD_Secret` |

更多支持的 DNS 服务商请参考 [acme.sh dnsapi 文档](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)。

### 如何获取 Cloudflare API Token

1. 访问 [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. 点击 **Create Token**
3. 选择 **Create Custom Token**
4. 配置权限：
   - **Zone** → **DNS** → **Edit**
   - **Zone Resources** → **Include** → **Specific zone** → 选择你的域名
5. 创建后复制 Token

## 部署到 Zeabur

如果你使用 Zeabur 等云平台部署，只需：

1. 创建新服务，选择 **Docker Image**
2. 输入镜像地址：`yingdao/qiniu-auto-cert:latest`
3. 添加环境变量
4. 添加持久化卷（可选）：
   - 容器路径：`/root/.acme.sh`

## 查看运行日志

```bash
# Docker
docker logs -f qiniu-auto-cert

# 查看证书状态
docker exec qiniu-auto-cert /root/.acme.sh/acme.sh --list
```

## 常见问题

### Q1: 为什么需要 DNS 验证？

如果你的域名通过 CNAME 指向七牛云 CDN，Let's Encrypt 验证时会访问到七牛云的服务器，而不是你的服务器。这种情况下，HTTP 验证无法工作，必须使用 DNS 验证。

### Q2: 容器重启后会重新申请证书吗？

不会。证书数据存储在 `/root/.acme.sh` 目录，如果配置了持久化卷，容器重启后证书会保留。

### Q3: 如何手动触发续期？

```bash
docker exec qiniu-auto-cert /root/.acme.sh/acme.sh --renew -d your-domain.com --force
```

### Q4: 支持通配符证书吗？

支持。将 `DOMAIN` 设置为 `*.yourdomain.com` 即可。

## 开源地址

- **GitHub**: https://github.com/hi-unc1e/qiniu-auto-cert
- **Docker Hub**: https://hub.docker.com/r/yingdao/qiniu-auto-cert

欢迎 Star ⭐ 和提 Issue！

## 总结

这个方案彻底解决了七牛云 CDN SSL 证书的续期问题：

- 🎯 **自动化**：一次配置，永久自动续期
- 💰 **免费**：使用 Let's Encrypt 免费证书
- 🔒 **安全**：DNS 验证不依赖服务器网络环境
- 🚀 **简单**：Docker 部署，开箱即用

如果你也在使用七牛云 CDN，不妨试试这个方案，彻底告别手动更新证书的烦恼！
