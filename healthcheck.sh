#!/bin/sh
# 健康检查脚本

# 检查证书是否在有效期内
check_cert_validity() {
    DOMAIN="${DOMAIN:-}"
    if [ -z "$DOMAIN" ]; then
        echo "ERROR: DOMAIN 环境变量未设置" >&2
        exit 1
    fi

    # 检查证书文件是否存在
    CERT_PATH="/root/.acme.sh/${DOMAIN}/${DOMAIN}.cer"
    if [ ! -f "$CERT_PATH" ]; then
        echo "WARNING: 证书文件不存在: $CERT_PATH" >&2
        exit 1
    fi

    # 获取证书过期时间
    EXPIRY_DATE=$(openssl x509 -in "$CERT_PATH" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

    echo "证书信息: $DOMAIN"
    echo "过期时间: $EXPIRY_DATE"
    echo "剩余天数: $DAYS_LEFT"

    if [ $DAYS_LEFT -lt 7 ]; then
        echo "WARNING: 证书即将过期 ($DAYS_LEFT 天)" >&2
        exit 1
    fi

    exit 0
}

# 执行检查
check_cert_validity
