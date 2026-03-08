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
    log "ACME 服务器: ${ACME_SERVER:-letsencrypt}"
    log "续期阈值: ${RENEW_DAYS:-7} 天"
    log "检查间隔: ${CHECK_INTERVAL:-86400} 秒"
    if [ -n "$DNS_API" ]; then
        log "验证方式: DNS ($DNS_API)"
    else
        log "验证方式: HTTP (standalone)"
    fi
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

    # 判断使用 DNS 验证还是 HTTP 验证
    if [ -n "$DNS_API" ]; then
        # DNS 验证方式
        setup_dns_vars
        issue_cert_dns
    else
        # HTTP 验证方式 (standalone 模式)
        log "使用 HTTP standalone 模式验证（确保域名 A 记录指向当前机器）"
        issue_cert_http
    fi

    # 部署证书到七牛云
    deploy_cert
}

# 设置 DNS API 环境变量
setup_dns_vars() {
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
}

# 使用 DNS 验证申请证书
issue_cert_dns() {
    log "使用 DNS 验证方式申请证书..."

    if /root/.acme.sh/acme.sh --issue --dns "$DNS_API" -d "$DOMAIN" \
        --keylength 2048 \
        --server "${ACME_SERVER:-letsencrypt}"; then
        log "证书申请成功"
    else
        error "证书申请失败"
    fi
}

# 使用 HTTP 验证申请证书
issue_cert_http() {
    log "使用 HTTP standalone 验证方式申请证书..."

    # 检查 80 端口是否可用
    if nc -z localhost 80 2>/dev/null; then
        log "警告: 80 端口已被占用，尝试使用 8080 端口..."
        HTTP_PORT=8080
    else
        HTTP_PORT=80
    fi

    if /root/.acme.sh/acme.sh --issue -d "$DOMAIN" \
        --standalone \
        --httpport "$HTTP_PORT" \
        --keylength 2048 \
        --server "${ACME_SERVER:-letsencrypt}"; then
        log "证书申请成功"
    else
        error "证书申请失败（请确保域名 A 记录指向当前机器且 80 端口可访问）"
    fi
}

# 续期证书
renew_cert() {
    log "检查证书续期..."

    # acme.sh 会自动检查证书有效期，只有接近过期才会真正续期
    if /root/.acme.sh/acme.sh --renew -d "$DOMAIN" --force --days "${RENEW_DAYS:-7}"; then
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
        CERT_INFO=$(/root/.acme.sh/acme.sh --list | grep "$DOMAIN")
        if [ -n "$CERT_INFO" ]; then
            log "证书信息: $CERT_INFO"
        fi
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
        if /root/.acme.sh/acme.sh --renew -d "$DOMAIN" --days "${RENEW_DAYS:-7}"; then
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
