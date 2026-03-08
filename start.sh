#!/bin/bash
# 快速启动脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 .env 文件
if [ ! -f ".env" ]; then
    echo_error ".env 文件不存在！"
    echo_info "正在创建 .env 文件..."
    cp .env.example .env
    echo_warn "请编辑 .env 文件，填入你的配置信息后重新运行此脚本"
    echo ""
    echo "必需配置项："
    echo "  - DOMAIN: 你的域名"
    echo "  - EMAIL: 你的邮箱"
    echo "  - QINIU_AK: 七牛云 AccessKey"
    echo "  - QINIU_SK: 七牛云 SecretKey"
    echo "  - DNS_API: DNS 验证方式（如 dns_dp）"
    echo "  - 对应 DNS 的 API 凭证"
    exit 1
fi

# 加载环境变量
source .env

# 验证必需的环境变量
check_env() {
    local missing=()

    [ -z "$DOMAIN" ] && missing+=("DOMAIN")
    [ -z "$EMAIL" ] && missing+=("EMAIL")
    [ -z "$QINIU_AK" ] && missing+=("QINIU_AK")
    [ -z "$QINIU_SK" ] && missing+=("QINIU_SK")
    [ -z "$DNS_API" ] && missing+=("DNS_API")

    if [ ${#missing[@]} -gt 0 ]; then
        echo_error "以下环境变量未设置: ${missing[*]}"
        echo_error "请检查 .env 文件"
        exit 1
    fi
}

echo_info "检查环境变量..."
check_env

echo_info "配置信息："
echo "  域名: $DOMAIN"
echo "  邮箱: $EMAIL"
echo "  DNS API: $DNS_API"
echo ""

# 构建镜像
echo_info "构建 Docker 镜像..."
docker-compose build

# 启动服务
echo_info "启动服务..."
docker-compose up -d

# 显示状态
echo_info "服务状态："
docker-compose ps

echo ""
echo_info "服务已启动！"
echo_info "查看日志: docker-compose logs -f"
echo_info "停止服务: docker-compose down"
