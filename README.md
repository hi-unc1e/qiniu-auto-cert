# 七牛云 CDN SSL 证书自动续期 Docker 服务

基于 `acme.sh` 的七牛云 CDN SSL 证书自动申请和续期服务。

## 功能特点

- 支持 Let's Encrypt / ZeroSSL 等 ACME 协议的 CA
- 自动续期（剩余 7 天内自动续期）
- 自动上传证书到七牛云 CDN
- 支持多种 DNS 验证方式（DNSPod、阿里云、Cloudflare 等）
- 每日自动检查，无需人工干预
- 支持健康检查
- 所有敏感信息通过环境变量注入，不硬编码

## 快速开始

### 方式一：使用 Docker Hub 镜像（推荐）

```bash
docker run -d \
  --name qiniu-auto-cert \
  --restart always \
  -e DOMAIN="buildbuffer.cdn.zuoxueba.org" \
  -e EMAIL="your-email@example.com" \
  -e QINIU_AK="your_qiniu_access_key" \
  -e QINIU_SK="your_qiniu_secret_key" \
  -e DNS_API="dns_dp" \
  -e DP_Id="your_dnspod_id" \
  -e DP_Key="your_dnspod_key" \
  yingdao/qiniu-auto-cert:latest
```

### 方式二：使用 Docker Compose

1. 克隆仓库
```bash
git clone https://github.com/yingdao/qiniu-auto-cert.git
cd qiniu-auto-cert
```

2. 复制并编辑配置文件
```bash
cp .env.example .env
# 编辑 .env 文件，填入你的配置
```

3. 启动服务
```bash
docker-compose up -d
```

### 方式三：本地构建

```bash
# 构建镜像
docker build -t qiniu-auto-cert:latest .

# 运行容器
docker run -d \
  --name qiniu-auto-cert \
  --restart always \
  -e DOMAIN="buildbuffer.cdn.zuoxueba.org" \
  -e EMAIL="your-email@example.com" \
  -e QINIU_AK="your_qiniu_access_key" \
  -e QINIU_SK="your_qiniu_secret_key" \
  -e DNS_API="dns_dp" \
  -e DP_Id="your_dnspod_id" \
  -e DP_Key="your_dnspod_key" \
  qiniu-auto-cert:latest
```

## 准备工作

### 1. 获取七牛云 AK/SK

访问 [七牛云密钥管理](https://portal.qiniu.com/user/key) 获取 AccessKey 和 SecretKey。

### 2. 开通 CDN 域名 HTTPS

访问 [七牛云 CDN 域名管理](https://portal.qiniu.com/cdn/domain) 确保目标域名已开启 HTTPS 功能。

### 3. 准备 DNS 验证凭证

根据你的 DNS 服务商准备相应的 API 凭证：

| DNS 服务商 | DNS_API 值 | 所需环境变量 |
|-----------|-----------|-------------|
| DNSPod | `dns_dp` | `DP_Id`, `DP_Key` |
| 阿里云 | `dns_ali` | `Ali_Key`, `Ali_Secret` |
| Cloudflare | `dns_cf` | `CF_Token` |
| 腾讯云 | `dns_cx` | `CX_Key`, `CX_Secret` |
| GoDaddy | `dns_gd` | `GD_Key`, `GD_Secret` |

更多支持请参考 [acme.sh dnsapi 文档](https://github.com/acmesh-official/acme.sh/wiki/dnsapi)。

## 环境变量说明

### 必需变量

| 变量 | 说明 | 示例 |
|-----|------|-----|
| `DOMAIN` | 要申请证书的域名 | `buildbuffer.cdn.zuoxueba.org` |
| `EMAIL` | ACME 账号邮箱 | `admin@example.com` |
| `QINIU_AK` | 七牛云 AccessKey | `Siog4cdE4bG...` |
| `QINIU_SK` | 七牛云 SecretKey | `xxx...` |
| `DNS_API` | DNS 验证方式 | `dns_dp` / `dns_ali` / `dns_cf` |

### 可选变量

| 变量 | 说明 | 默认值 |
|-----|------|-------|
| `ACME_SERVER` | ACME 服务器 | `letsencrypt` |
| `RENEW_DAYS` | 续期阈值（天） | `7` |
| `CHECK_INTERVAL` | 检查间隔（秒） | `86400` (1天) |
| `QINIU_CDN_DOMAIN` | 七牛 CDN 实际域名（泛域名证书需要） | - |

## 工作流程

```
启动容器
    ↓
验证环境变量
    ↓
注册 ACME 账号
    ↓
首次申请证书（使用 DNS 验证）
    ↓
上传证书到七牛云
    ↓
每日检查证书有效期
    ↓
剩余天数 < 7 天 → 自动续期并上传
```

## 查看日志

```bash
# Docker
docker logs -f qiniu-auto-cert

# Docker Compose
docker-compose logs -f
```

## 手动续期

```bash
docker exec qiniu-auto-cert /root/.acme.sh/acme.sh --renew -d buildbuffer.cdn.zuoxueba.org --force
```

## 健康检查

容器内置健康检查，每 1 小时检查一次证书状态：

```bash
docker inspect --format='{{.State.Health.Status}}' qiniu-auto-cert
```

## 故障排查

1. **证书申请失败**
   - 检查 DNS API 凭证是否正确
   - 检查域名是否已正确解析
   - 查看容器日志定位具体错误

2. **七牛云上传失败**
   - 确认七牛云 CDN 域名已开启 HTTPS
   - 检查 AK/SK 是否有相应权限
   - 确认域名在七牛云中已添加

3. **证书未自动续期**
   - 检查 `RENEW_DAYS` 设置
   - 确认容器正在运行
   - 查看日志是否有错误信息

## 安全建议

1. 不要将 `.env` 文件提交到版本控制
2. 定期更换 AK/SK
3. 限制七牛云 AK/SK 的权限范围
4. 使用 Docker secrets 或 Swarm secrets 管理敏感信息

## Docker Hub

https://hub.docker.com/r/yingdao/qiniu-auto-cert

## License

MIT
