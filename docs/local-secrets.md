# 本地凭据与 JWT 密钥

发布副本不包含原有私钥或本机服务凭据。`application.yml` 从环境变量读取数据库、Redis、Canal、AI 与 OSS 配置，原本机配置不随仓库发布。

在仓库根目录运行（需要 OpenSSL）：

```powershell
New-Item -ItemType Directory -Force .local/keys
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out .local/keys/private.pem
openssl pkey -in .local/keys/private.pem -pubout -out .local/keys/public.pem
```

`.local/` 与所有 PEM 文件均已加入 `.gitignore` 和 Docker 构建排除规则。JVM 默认从 `.local/keys/` 读取，Compose 将同一目录只读挂载到容器。可用 `AUTH_JWT_PRIVATE_KEY` 和 `AUTH_JWT_PUBLIC_KEY` 指定其他 Spring Resource 路径。

根据自己的服务设置以下环境变量：

| 用途 | 变量 |
| --- | --- |
| 数据源 | `SPRING_DATASOURCE_URL`、`SPRING_DATASOURCE_USERNAME`、`SPRING_DATASOURCE_PASSWORD` |
| Redis | `SPRING_DATA_REDIS_HOST`、`SPRING_DATA_REDIS_PORT`、`SPRING_DATA_REDIS_PASSWORD` |
| Canal | `CANAL_HOST`、`CANAL_USERNAME`、`CANAL_PASSWORD` |
| AI | `DEEPSEEK_API_KEY`、`OPENAI_API_KEY` |
| OSS | `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_BUCKET`、`OSS_PUBLIC_DOMAIN` |

直接运行 JVM 时，PowerShell 使用 `$env:变量名='自己的值'`；Compose 可读取仓库根目录的 `.env`，但该文件不会自动被 Spring Boot 的本地 JVM 加载。勿提交 `.env`。Compose 数据库与 Redis 密码的默认值见其文件；本地 JVM 的环境变量应与实际中间件配置一致。

JWT 单元测试在内存中生成临时 RSA 密钥，不依赖本地密钥文件。
