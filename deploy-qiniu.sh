#!/bin/sh
# 七牛云证书部署脚本 (使用 acme.sh 内置部署功能)
# 环境变量:
#   QINIU_AK - 七牛云 AccessKey
#   QINIU_SK - 七牛云 SecretKey

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 检查必要参数
if [ -z "$QINIU_AK" ] || [ -z "$QINIU_SK" ]; then
    log "错误: QINIU_AK 和 QINIU_SK 环境变量必须设置"
    exit 1
fi

# 获取参数
DOMAIN="$1"
DOMAIN_CERT="$2"
DOMAIN_KEY="$3"
DOMAIN_CA="$4"
DOMAIN_FULLCHAIN="$5"
DOMAIN_CREDENTIALS="$6"

log "开始部署证书到七牛云 CDN: $DOMAIN"

# 使用 acme.sh 内置的七牛部署
# 设置七牛 CDN 域名（如果是泛域名证书）
if [ -n "$QINIU_CDN_DOMAIN" ]; then
    export QINIU_CDN_DOMAIN
fi

# 调用 acme.sh 的内置七牛部署脚本
ACME_SH_HOME="/root/.acme.sh"
DEPLOY_HOOK="$ACME_SH_HOME/deploy/qiniu.sh"

if [ -f "$DEPLOY_HOOK" ]; then
    . "$DEPLOY_HOOK"
    log "证书部署完成"
else
    log "错误: 七牛部署脚本不存在"
    exit 1
fi
