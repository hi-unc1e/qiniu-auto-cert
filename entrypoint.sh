#!/bin/sh
# 入口脚本 - 初始化并启动证书续期服务

set -e

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
    exit 1
}

# 显示配置信息
show_config() {
    log "======================================"
    log "七牛云 CDN SSL 证书自动续期服务"
    log "======================================"
    log "域名: $DOMAIN"
    log "邮箱: $EMAIL"
    log "ACME 服务器: $ACME_SERVER"
    log "续期阈值: $RENEW_DAYS 天"
    log "检查间隔: $CHECK_INTERVAL 秒"
    log "DNS API: $DNS_API"
    if [ -n "$QINIU_CDN_DOMAIN" ]; then
        log "七牛 CDN 域名: $QINIU_CDN_DOMAIN"
    fi
    log "======================================"
}

# 验证环境变量
validate_env() {
    # 必需的环境变量
    [ -n "$DOMAIN" ] || error "环境变量 DOMAIN 未设置"
    [ -n "$EMAIL" ] || error "环境变量 EMAIL 未设置"
    [ -n "$QINIU_AK" ] || error "环境变量 QINIU_AK 未设置"
    [ -n "$QINIU_SK" ] || error "环境变量 QINIU_SK 未设置"

    # DNS 验证方式
    if [ -z "$DNS_API" ]; then
        error "环境变量 DNS_API 未设置，请指定 DNS 验证方式 (如: dns_dp, dns_ali, dns_cf 等)"
    fi

    log "环境变量验证通过"
}

# 设置 acme.sh 配置
setup_acme() {
    log "配置 acme.sh..."

    # 设置默认 CA 服务器
    export DEFAULT_ACME_SERVER="${ACME_SERVER:-letsencrypt}"

    # 注册账号（如果尚未注册）
    if [ ! -f "/root/.acme.sh/account.conf" ]; then
        log "注册 ACME 账号..."
        /root/.acme.sh/acme.sh --register-account -m "$EMAIL" --server "$ACME_SERVER" || log "账号可能已注册，继续..."
    fi

    log "acme.sh 配置完成"
}

# 初始证书申请
initial_cert() {
    log "检查是否需要申请证书..."

    # 检查证书是否已存在
    if /root/.acme.sh/acme.sh --list | grep -q "$DOMAIN"; then
        log "证书已存在，检查是否需要续期..."
        renew_cert
        return $?
    fi

    log "首次申请证书..."

    # 根据不同的 DNS API 设置相应的环境变量
    case "$DNS_API" in
        dns_dp)
            [ -n "$DP_Id" ] || error "DNS_API=dns_dp 需要 DP_Id 环境变量"
            [ -n "$DP_Key" ] || error "DNS_API=dns_dp 需要 DP_Key 环境变量"
            export DP_Id DP_Key
            ;;
        dns_ali)
            [ -n "$Ali_Key" ] || error "DNS_API=dns_ali 需要 Ali_Key 环境变量"
            [ -n "$Ali_Secret" ] || error "DNS_API=dns_ali 需要 Ali_Secret 环境变量"
            export Ali_Key Ali_Secret
            ;;
        dns_cf)
            [ -n "$CF_Token" ] || error "DNS_API=dns_cf 需要 CF_Token 环境变量"
            export CF_Token
            ;;
        dns_cx)
            [ -n "$CX_Key" ] || error "DNS_API=dns_cx 需要 CX_Key 环境变量"
            [ -n "$CX_Secret" ] || error "DNS_API=dns_cx 需要 CX_Secret 环境变量"
            export CX_Key CX_Secret
            ;;
        dns_gd)
            [ -n "$GD_Key" ] || error "DNS_API=dns_gd 需要 GD_Key 环境变量"
            [ -n "$GD_Secret" ] || error "DNS_API=dns_gd 需要 GD_Secret 环境变量"
            export GD_Key GD_Secret
            ;;
        *)
            log "警告: DNS_API '$DNS_API' 可能需要额外的环境变量"
            ;;
    esac

    # 申请证书
    if /root/.acme.sh/acme.sh --issue --dns "$DNS_API" -d "$DOMAIN" \
        --keylength 2048 \
        --server "$ACME_SERVER"; then
        log "证书申请成功"
    else
        error "证书申请失败"
    fi

    # 部署证书到七牛云
    deploy_cert
}

# 续期证书
renew_cert() {
    log "检查证书续期..."

    # 强制续期（用于测试证书是否有效）
    # acme.sh 会自动检查证书有效期，只有接近过期才会真正续期
    if /root/.acme.sh/acme.sh --renew -d "$DOMAIN" --force --days "$RENEW_DAYS"; then
        log "证书检查/续期完成"
        deploy_cert
    else
        log "证书检查完成，无需续期"
    fi
}

# 部署证书到七牛云
deploy_cert() {
    log "部署证书到七牛云 CDN..."

    # 设置七牛云环境变量
    export QINIU_AK QINIU_SK
    [ -n "$QINIU_CDN_DOMAIN" ] && export QINIU_CDN_DOMAIN

    # 使用内置的七牛部署钩子
    if /root/.acme.sh/acme.sh --deploy -d "$DOMAIN" --deploy-hook qiniu; then
        log "证书部署成功"

        # 记录部署信息
        log "证书已上传到七牛云，certID: $(/root/.acme.sh/acme.sh --list | grep "$DOMAIN" | awk '{print $3}')"
        return 0
    else
        log "证书部署失败"
        return 1
    fi
}

# 启动定时检查
start_daemon() {
    log "启动定时检查服务..."

    # 计算检查间隔（默认每天一次）
    INTERVAL="${CHECK_INTERVAL:-86400}"

    # 立即执行一次
    initial_cert

    # 设置循环检查
    while true; do
        log "等待 $INTERVAL 秒后进行下一次检查..."
        sleep "$INTERVAL"

        log "执行定期检查..."
        if /root/.acme.sh/acme.sh --renew -d "$DOMAIN" --days "$RENEW_DAYS"; then
            deploy_cert
        fi
    done
}

# 主函数
main() {
    log "服务启动..."

    # 验证环境变量
    validate_env

    # 显示配置
    show_config

    # 设置 acme.sh
    setup_acme

    # 启动守护进程
    start_daemon
}

# 执行主函数
main "$@"
