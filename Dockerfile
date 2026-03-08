FROM alpine:3.19

# 安装依赖
RUN apk add --no-cache \
    curl \
    openssl \
    socat \
    tzdata \
    jq

# 设置时区为上海
ENV TZ=Asia/Shanghai

# 安装 acme.sh
RUN curl https://get.acme.sh | sh

# 设置工作目录
WORKDIR /acme.sh

# 复制启动脚本和七牛部署脚本
COPY deploy-qiniu.sh /acme.sh/
COPY entrypoint.sh /acme.sh/
COPY healthcheck.sh /acme.sh/

# 设置权限
RUN chmod +x /acme.sh/deploy-qiniu.sh /acme.sh/entrypoint.sh /acme.sh/healthcheck.sh

# 设置环境变量默认值
ENV ACME_SERVER=letsencrypt \
    RENEW_DAYS=7 \
    CHECK_INTERVAL=86400

# 入口点
ENTRYPOINT ["/acme.sh/entrypoint.sh"]

# 健康检查
HEALTHCHECK --interval=1h --timeout=30s --start-period=60s --retries=3 \
    CMD /acme.sh/healthcheck.sh
