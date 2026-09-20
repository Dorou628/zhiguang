# Docker 一键包验证

日期：2026-09-20。环境：Windows、Docker Desktop 的 Linux/amd64 容器、Docker 29.4.3、Compose 5.1.4。

## 已实测

- Java 21 / Spring Boot 3.4.13 Maven 测试通过：4 个测试，0 失败、0 错误；包括未配置 AI 凭据的处理。
- Docker 构建后端和前端成功；前端执行 TypeScript 检查及 Vite 生产构建。
- MySQL、Redis、Kafka、Elasticsearch、Canal、后端、前端 7 个服务均 healthy，`launch.ps1` 返回 Ready。
- MySQL 首次初始化 schema、20 条示例内容和演示账号；JWT 私钥由 OpenSSL 自动生成，存入专用卷。
- 浏览器显示示例 Feed，通过邮箱密码表单登录后页面显示“本地演示用户”。
- 内置 standard 分词器成功建立索引并回灌 20 条示例内容；登录后查询 `Spring` 返回 2 条结果，前缀联想返回对应标题。
- 经 Nginx 同源代理调用登录、`auth/me` 和 Feed 成功；测试点赞 / 取消点赞、关注 / 取消关注均成功，测试关系已复原。
- 关注操作产生的 Outbox 事件经 Canal 写入 Kafka，`canal-outbox` 分区末端偏移为 2。
- 未填 DeepSeek 密钥时摘要接口返回 HTTP 400 和明确的配置提示。
- 从含中文和空格的解压目录执行总停止、总启动，两个项目均恢复；JWT 公钥 SHA-256 与停止前一致，演示账号及数据库可继续使用。
- 最终交付目录的 `start-all.cmd` 实际执行返回 0，并自动打开两个项目页面。

## 范围

未使用真实 AI / DashScope / OSS 凭据测试模型调用、RAG 或上传。原始示例的外部正文和图片链接不保证可用；本地搜索默认索引标题、标签、描述，不在启动时访问示例外链。此包是本机演示配置，端口仅绑定回环地址。

首次换机启动需要联网获取镜像和依赖，不是离线镜像包。已构建后 `start.cmd` 复用镜像；源码修改后用 `rebuild.cmd`。macOS / Linux shell 入口未在对应宿主系统上实测。
