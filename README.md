# 知光 · 知识分享社区

Java 21 / Spring Boot 后端与 React / Vite 前端的学习实践仓库。后端位于根目录，前端位于 `frontend/`。

本仓库导入已有本地代码并按模块组织提交。来源为 [G-Pegasus/zhiguang_be](https://github.com/G-Pegasus/zhiguang_be) 和 [G-Pegasus/zhiguang_fe](https://github.com/G-Pegasus/zhiguang_fe)；原始说明保存在 [上游 README](docs/upstream-readme.md)。导入提交用于梳理代码结构，不代表这些模块在提交当天从零开发。此次整理补充了环境变量配置、密钥隔离和可移植的容器路径。

## 模块导航

| 模块 | 代码入口 | 职责 |
| --- | --- | --- |
| 认证与用户 | `src/main/java/com/tongji/auth`、`user`、`profile` | JWT 双令牌、验证码、用户资料 |
| 内容发布与 Feed | `knowpost`、`storage`、`cache` | 知文发布、OSS 直传、三级缓存与热点检测 |
| 计数与关系 | `counter`、`relation` | 点赞收藏、Redis Lua、关注关系、Outbox / Canal / Kafka |
| 搜索与 AI | `search`、`llm` | Elasticsearch 检索、摘要生成与 RAG |
| 前端 | `frontend/src` | 登录、首页、发布、搜索与个人主页 |

## 本地开发

1. 安装 JDK 21、Maven、Node.js 和 Docker（完整服务链需要 Docker 中间件或自行配置服务）。
2. 按 [凭据与密钥配置](docs/local-secrets.md) 生成 JWT 密钥并设置自己的环境变量。
3. `mvn test` 运行单元测试；`mvn package` 构建后端。完整启动还需要 MySQL、Redis、Kafka、Elasticsearch 和 Canal，参见 [Docker 部署](docs/docker-local-setup.md)。
4. 前端执行 `cd frontend`、`npm ci`、`npm run dev`，默认地址 `http://localhost:5173`，API 代理至 `http://localhost:8080`。
5. 前端生产构建执行 `npm run build`。

`docker compose --profile full-stack up --build -d` 使用本仓库内的前后端目录；启动前须生成 `.local/keys/` 密钥。Compose 中的示例密码仅用于本地开发。AI 和 OSS 功能需要各自有效的配置。

架构说明见 `docs/`，流程笔记见 `Record/`。导入时执行的检查及范围见 [导入验证](docs/import-validation.md)。
