# 知光：一键启动

## Windows

1. 安装并启动 [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)，使用 Linux 容器 / WSL 2。
2. 解压整个项目目录，双击 **`start.cmd`**。
3. 第一次会下载镜像、编译前后端、初始化数据库并生成 JWT 密钥。看到 `Ready` 后浏览器自动打开 **http://127.0.0.1:15173**。

无需在主机安装 Java、Maven、Node.js、MySQL 或 OpenSSL。建议给 Docker 至少 6 GB 内存；两个项目一起运行建议 10 GB 以上可用内存，并预留约 30 GB 磁盘。首次启动需要能访问 Docker Hub、Maven Central、npm 等软件源；后续启动直接复用已有镜像。源码更新后用 `rebuild.cmd` 重新构建；macOS / Linux 用 `sh start.sh --rebuild`。

演示账号：**`demo@example.com`**；密码：**`DemoPass123!`**。在登录页选择邮箱、密码登录。该账号只用于绑定本机回环地址的本地演示，勿把本 Compose 直接作为公网部署配置。

## 日常操作

| 操作 | 双击文件 |
| --- | --- |
| 启动 / 应用 .env 配置 | `start.cmd` |
| 源码修改后重新编译并启动 | `rebuild.cmd` |
| 停止，保留数据 | `stop.cmd` |
| 查看服务状态 | `status.cmd` |
| 查看日志（Ctrl+C 退出查看） | `logs.cmd` |

命令行也可以运行：

```powershell
.\launch.ps1 -Action start -NoBrowser
.\launch.ps1 -Action stop
```

macOS / Linux：在解压目录运行 `sh start.sh`，停止运行 `sh stop.sh`。Docker 必须已安装并启动。

## 默认能用什么

Compose 启动 MySQL、Redis、Kafka、Elasticsearch、Canal、后端和前端。数据库自动装入示例用户和内容，JWT 密钥自动生成到独立数据卷，前端通过 Nginx 代理访问后端。

登录、资料、Feed、关注、点赞收藏等社区功能使用本地中间件。本地搜索使用 Elasticsearch 内置 `standard` 分词器，启动时回灌示例标题、标签和描述，无需安装 IK；中文分词精度与 IK 不同。默认不抓取外部正文 URL；内容地址可访问时可在 `.env` 设置 `SEARCH_FETCH_CONTENT=true`，用于后续索引写入。原有非 Docker 配置仍默认使用 IK。

AI 和 OSS 是外部服务，需要自己的账号配置：

1. 首次启动自动把 `.env.example` 复制为 `.env`；也可以在第一次启动前手动复制。
2. 在 `.env` 中填入 `DEEPSEEK_API_KEY`，启用摘要；RAG 还需 `OPENAI_API_KEY`（项目默认连接 DashScope 的向量模型）。
3. 上传头像、图片和 Markdown 正文需要 `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_BUCKET`，必要时加 `OSS_PUBLIC_DOMAIN`。OSS 桶须自行配置允许浏览器直传的 CORS 与对应访问权限。
4. 再双击 `start.cmd` 应用修改。

缺少 AI 密钥时，本地社区仍可启动，AI 请求返回明确的未配置提示，不会生成假结果。缺少 OSS 配置时上传不可用。原始种子数据中部分图片和文章链接属于外部示例资源，其可用性不由本地启动包保证。

## 端口与数据

- 页面：`15173`；后端：`18082`。可在 `.env` 修改 `ZHIGUANG_WEB_PORT` / `ZHIGUANG_API_PORT` 后重新启动。
- 所有主机端口仅绑定 `127.0.0.1`；数据库、Redis、Kafka、Canal、Elasticsearch 不直接暴露主机端口。
- 数据保存在 `resume-zhiguang` 项目的 Docker 命名卷，移动解压目录不需要重建数据库。
- `stop.cmd` 执行 `down`，不会删除数据卷。**不要执行 `docker compose down -v`，除非你明确想清空数据。**
- 首次初始化脚本只在新数据库卷运行。修改种子 SQL 不会重置已保存的数据。

## 启动失败

先双击 `status.cmd` 与 `logs.cmd`，按第一个失败服务定位。脚本只有在容器健康检查通过后才显示 Ready。

- Docker Engine 不可用：打开 Docker Desktop 处理其错误窗口，不能只安装 CLI。
- 镜像下载或 Maven/npm 超时：检查网络以及 Docker Desktop 的系统代理；Windows 脚本也会把简单的系统 HTTP 代理传给 Docker 构建客户端。
- 端口占用：修改 `.env` 中页面 / API 端口，不需要停止其他项目。
- Elasticsearch 内存不足：增加 Docker 可用内存后重新启动。
- 使用包含中文或空格的路径时，务必完整解压并保留目录结构，不要直接从压缩软件内运行脚本。

本次实际验证结果见 [打包验证](docs/oneclick-validation.md)。
