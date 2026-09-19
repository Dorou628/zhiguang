# Elasticsearch 搜索模块技术文档

## 目录

- [1. 概述](#1-概述)
- [2. 系统架构](#2-系统架构)
- [3. ES 配置详解](#3-es-配置详解)
- [4. 索引设计与 Mapping](#4-索引设计与-mapping)
- [5. 核心功能实现](#5-核心功能实现)
- [6. 高级搜索技术](#6-高级搜索技术)
- [7. 数据同步机制](#7-数据同步机制)
- [8. RAG 向量检索](#8-rag-向量检索)
- [9. 性能优化策略](#9-性能优化策略)
- [10. 面试考点汇总](#10-面试考点汇总)

---

## 1. 概述

### 1.1 模块定位

本项目中的 Elasticsearch（ES）搜索模块承担着**全文检索**与**向量检索**双重职责：

- **传统关键词搜索**：支持知文内容的全文检索、标签过滤、高亮显示
- **RAG 向量搜索**：基于 Spring AI + Elasticsearch 实现语义检索，支持智能问答

### 1.2 技术栈

| 组件 | 版本/技术 | 用途 |
|------|----------|------|
| Spring Boot | 3.x | 基础框架 |
| Elasticsearch Client | 8.x | Java API 客户端 |
| Spring AI | 最新版 | RAG 向量检索封装 |
| IK Analyzer | - | 中文分词器 |
| Kafka + Canal | - | CDC 数据同步 |
| Redis | - | 缓存与计数器 |

---

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│   MySQL     │ ───► │ Canal + Kafka│ ───► │ SearchIndexService│
│  (主数据库)  │      │  (CDC 监听)   │      │   (ES 索引写入)    │
└─────────────┘      └──────────────┘      └────────┬────────┘
                                                    │
                    ┌───────────────────────────────┼───────────────────────────────┐
                    │                               ▼                               │
                    │                  ┌────────────────────────┐                   │
                    │                  │  Elasticsearch Cluster │                   │
                    │                  │  zhiguang_content_index│                   │
                    │                  │  (全文检索索引)          │                   │
                    │                  └────────────────────────┘                   │
                    │                  ┌────────────────────────┐                   │
                    │                  │  zhiguang-ai-index     │                   │
                    │                  │  (RAG 向量索引)          │                   │
                    │                  └────────────────────────┘                   │
                    │                               ▲                               │
                    └───────────────────────────────┼───────────────────────────────┘
                                                    │
                    ┌───────────────────────────────┴───────────────────────────────┐
                    │                               │                               │
        ┌───────────▼───────────┐      ┌───────────▼───────────┐      ┌───────────▼───────────┐
        │  SearchController     │      │  RagQueryService      │      │  KnowPostController   │
        │  (关键词搜索)          │      │  (向量检索 +RAG)       │      │  (业务触发索引)        │
        └───────────────────────┘      └───────────────────────┘      └───────────────────────┘
```

### 2.2 数据流向

**正向流程（内容发布）**：
1. 用户发布知文 → MySQL 持久化
2. Canal 监听到 binlog 变化 → 发送 Kafka 消息
3. `CanalOutboxConsumerSearch` 消费消息 → 调用 `SearchIndexService.upsertKnowPost()`
4. ES 索引更新 → 支持实时检索

**反向流程（删除/软删）**：
1. 用户删除知文 → MySQL 软删除（status=deleted）
2. Canal 捕获变更 → Kafka 转发
3. ES 执行软删除（更新 status 字段）→ 搜索结果过滤

---

## 3. ES 配置详解

### 3.1 application.yml 配置

```yaml
spring:
  elasticsearch:
    uris: http://localhost:9200  # 支持集群多节点
    # username: elastic          # 未启用 xpack.security，无需账号密码
    # password: xxx
  
  ai:
    vectorstore:
      elasticsearch:
        initialize-schema: true              # 自动初始化向量索引
        index-name: zhiguang-ai-index        # RAG 专用索引名
        dimensions: 1536                     # 向量维度（与 embedding 模型一致）
```

### 3.2 Java 配置类

#### ElasticsearchConfig.java

```java
@Configuration
@EnableConfigurationProperties(EsProperties.class)
public class ElasticsearchConfig {
    
    private final EsProperties props;
    
    @Bean
    public ElasticsearchClient elasticsearchClient() {
        // 1. 认证配置（可选）
        BasicCredentialsProvider creds = new BasicCredentialsProvider();
        if (StringUtils.hasText(props.getUsername())) {
            creds.setCredentials(AuthScope.ANY,
                new UsernamePasswordCredentials(props.getUsername(), props.getPassword()));
        }
        
        // 2. 构建 RestClient
        RestClientBuilder builder = RestClient.builder(
                org.apache.http.HttpHost.create(props.getHost()))
            .setHttpClientConfigCallback(httpClientBuilder -> 
                httpClientBuilder.setDefaultCredentialsProvider(creds));
        
        // 3. 使用 Jackson 序列化器
        RestClient restClient = builder.build();
        RestClientTransport transport = new RestClientTransport(
            restClient, new JacksonJsonpMapper());
        
        return new ElasticsearchClient(transport);
    }
}
```

**关键点**：
- 使用 `JacksonJsonpMapper` 替代默认的 JSON-B，性能更好
- 支持多节点集群（通过 `uris` 列表）
- 兼容无安全认证的开发环境

### 3.3 属性类 EsProperties

```java
@Data
@ConfigurationProperties(prefix = "spring.elasticsearch")
public class EsProperties {
    private List<String> uris;    // 支持多个 ES 节点
    
    // RAG 索引名（从 Spring AI 配置注入）
    @Value("${spring.ai.vectorstore.elasticsearch.index-name:}")
    private String index;         // e.g., zhiguang-ai-index
    
    public String getHost() {
        return (uris == null || uris.isEmpty()) ? null : uris.getFirst();
    }
}
```

---

## 4. 索引设计与 Mapping

### 4.1 全文检索索引：zhiguang_content_index

#### 4.1.1 Mapping 定义代码

```java
@Service
public class SearchIndexInitializer {
    private static final String INDEX = "zhiguang_content_index";
    
    @PostConstruct
    public void ensureIndex() {
        es.indices().create(c -> c.index(INDEX).mappings(m -> m
            // 数值型字段
            .properties("content_id", p -> p.long_(LongNumberProperty.of(b -> b)))
            .properties("author_id", p -> p.long_(LongNumberProperty.of(b -> b)))
            .properties("publish_time", p -> p.date(DateProperty.of(b -> b)))
            .properties("like_count", p -> p.integer(IntegerNumberProperty.of(b -> b)))
            .properties("favorite_count", p -> p.integer(IntegerNumberProperty.of(b -> b)))
            .properties("view_count", p -> p.integer(IntegerNumberProperty.of(b -> b)))
            
            // 关键词字段（不分词，用于精确匹配/过滤）
            .properties("content_type", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("tags", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("author_avatar", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("author_nickname", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("author_tag_json", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("status", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("img_urls", p -> p.keyword(KeywordProperty.of(b -> b)))
            .properties("is_top", p -> p.keyword(KeywordProperty.of(b -> b)))
            
            // 文本字段（全文检索，使用 IK 分词）
            .properties("description", p -> p.text(TextProperty.of(b -> b.analyzer("ik_max_word"))))
            .properties("title", p -> p.text(TextProperty.of(b -> b
                .analyzer("ik_max_word")
                .searchAnalyzer("ik_smart"))))  // 搜索时使用更粗粒度的分词
            .properties("body", p -> p.text(TextProperty.of(b -> b.analyzer("ik_max_word"))))
            
            // 补全建议字段（Completion Suggester）
            .properties("title_suggest", p -> p.completion(CompletionProperty.of(b -> b)))
        ));
    }
}
```

#### 4.1.2 字段设计策略

| 字段类型 | 字段名 | 数据类型 | 分析器 | 用途 |
|---------|--------|---------|--------|------|
| **主键** | content_id | Long | - | 文档唯一标识 |
| **类型** | content_type | Keyword | - | 内容类型过滤 |
| **标题** | title | Text | ik_max_word / ik_smart | 检索 + 高亮 |
| **正文** | body | Text | ik_max_word | 全文检索主体 |
| **描述** | description | Text | ik_max_word | 摘要展示 |
| **标签** | tags | Keyword | - | 标签过滤 |
| **作者** | author_id | Long | - | 权限判断 |
| **时间** | publish_time | Date | - | 排序 |
| **计数** | like_count | Integer | - | 加权排序 |
| **状态** | status | Keyword | - | 软删除过滤 |
| **补全** | title_suggest | Completion | - | 联想输入 |

**面试考点**：
- **Keyword vs Text**：Keyword 不分词，适合精确匹配；Text 分词，适合全文检索
- **IK 分词器选择**：`ik_max_word`（细粒度，用于索引）vs `ik_smart`（粗粒度，用于搜索）
- **Completion Suggester**：专门用于自动补全，性能优于 Term Suggester

### 4.2 向量检索索引：zhiguang-ai-index

由 Spring AI 自动管理，存储结构：

```json
{
  "text": "知文片段内容",
  "metadata": {
    "postId": "123456",
    "chunkId": "123456#0",
    "position": 0,
    "contentEtag": "abc123",
    "contentSha256": "sha256_hash",
    "contentUrl": "http://...",
    "title": "知文标题"
  },
  "vector": [0.123, -0.456, ...]  // 1536 维浮点数组
}
```

---

## 5. 核心功能实现

### 5.1 关键词搜索

#### 5.1.1 API 接口

```java
@RestController
@RequestMapping("/api/v1/search")
public class SearchController {
    
    @GetMapping
    public SearchResponse search(
        @RequestParam("q") @NotBlank String q,      // 搜索关键词
        @RequestParam(value = "size", defaultValue = "20") int size,
        @RequestParam(value = "tags", required = false) String tagsCsv,  // 标签过滤
        @RequestParam(value = "after", required = false) String after,   // 游标分页
        @AuthenticationPrincipal Jwt jwt             // 当前用户（用于点赞状态）
    ) {
        Long userId = (jwt == null) ? null : jwtService.extractUserId(jwt);
        return searchService.search(q, size, tagsCsv, after, userId);
    }
}
```

#### 5.1.2 搜索服务实现

```java
@Service
public class SearchServiceImpl implements SearchService {
    
    public SearchResponse search(String q, int size, String tagsCsv, String after, Long userId) {
        // 1. 解析参数
        List<String> tags = parseCsv(tagsCsv);
        List<FieldValue> afterValues = parseAfter(after);
        
        // 2. 构建复合排序（相关性 > 时间 > 互动数据 > ID）
        List<SortOptions> sorts = new ArrayList<>();
        sorts.add(SortOptions.of(s -> s.score(o -> o.order(SortOrder.Desc))));
        sorts.add(SortOptions.of(s -> s.field(f -> f.field("publish_time").order(SortOrder.Desc))));
        sorts.add(SortOptions.of(s -> s.field(f -> f.field("like_count").order(SortOrder.Desc))));
        sorts.add(SortOptions.of(s -> s.field(f -> f.field("view_count").order(SortOrder.Desc))));
        sorts.add(SortOptions.of(s -> s.field(f -> f.field("content_id").order(SortOrder.Desc))));
        
        // 3. 执行搜索
        co.elastic.clients.elasticsearch.core.SearchResponse<Map<String, Object>> resp;
        try {
            resp = es.search(s -> {
                var b = s.index(INDEX)
                    .size(size)
                    // 核心查询：bool + function_score
                    .query(qb -> qb.functionScore(fs -> fs
                        // bool 查询：多字段匹配 + 过滤
                        .query(qb2 -> qb2.bool(bq -> {
                            bq.must(m -> m.multiMatch(mm -> mm.query(q)
                                    .fields("title^3", "body")));  // title 权重×3
                            bq.filter(f -> f.term(t -> t.field("status")
                                    .value(v -> v.stringValue("published"))));
                            
                            if (tags != null && !tags.isEmpty()) {
                                bq.filter(f -> f.terms(t -> t.field("tags")
                                        .terms(tv -> tv.value(tags.stream()
                                            .map(FieldValue::of).toList()))));
                            }
                            return bq;
                        }))
                        // 互动数据加权（对数函数避免极端值）
                        .functions(fn -> fn.fieldValueFactor(fvf -> fvf
                            .field("like_count")
                            .modifier(FieldValueFactorModifier.Log1p))
                            .weight(2.0))
                        .functions(fn -> fn.fieldValueFactor(fvf -> fvf
                            .field("view_count")
                            .modifier(FieldValueFactorModifier.Log1p))
                            .weight(1.0))
                        .boostMode(FunctionBoostMode.Sum)  // 加权模式
                    ))
                    // 高亮设置
                    .highlight(h -> h
                        .fields(new NamedValue<>("title", new HighlightField.Builder().build()))
                        .fields(new NamedValue<>("body", new HighlightField.Builder().build())))
                    .sort(sorts);
                
                // 游标分页
                if (afterValues != null && !afterValues.isEmpty()) {
                    b = b.searchAfter(afterValues);
                }
                return b;
            }, Map.class);
        } catch (Exception e) {
            return new SearchResponse(Collections.emptyList(), null, false);
        }
        
        // 4. 结果处理（省略...）
    }
}
```

**技术亮点**：
1. **加权查询**：`title^3` 表示标题匹配权重是正文的 3 倍
2. **Function Score**：使用互动数据（点赞、浏览）对搜索结果进行二次加权
3. **对数修饰符**：`Log1p` 防止计数过大导致排序失衡（log(1+x)）
4. **复合排序**：先按相关性，再按时间、互动数据，最后按 ID 保证稳定性
5. **游标分页**：避免深度分页性能问题

### 5.2 联想建议（Completion Suggester）

```java
@GetMapping("/suggest")
public SuggestResponse suggest(
    @RequestParam("prefix") @NotBlank String prefix,  // 输入前缀
    @RequestParam(value = "size", defaultValue = "10") int size
) {
    return searchService.suggest(prefix, size);
}

// 服务实现
public SuggestResponse suggest(String prefix, int size) {
    co.elastic.clients.elasticsearch.core.SearchResponse<Map<String, Object>> resp;
    try {
        resp = es.search(s -> s.index(INDEX)
            .suggest(sug -> sug.suggesters("title_suggest",
                sc -> sc.prefix(prefix)  // 输入前缀
                    .completion(c -> c.field("title_suggest").size(size))))
            , Map.class);
    } catch (Exception e) {
        return new SuggestResponse(Collections.emptyList());
    }
    
    // 提取建议结果
    List<String> items = new ArrayList<>();
    var sugg = resp.suggest();
    List<Suggestion<Map<String, Object>>> entry = sugg.get("title_suggest");
    if (entry != null) {
        for (var s : entry) {
            var comp = s.completion();
            if (comp != null && comp.options() != null) {
                for (var opt : comp.options()) {
                    String text = opt.text();
                    if (text != null && !text.isBlank()) {
                        items.add(text);
                    }
                }
            }
        }
    }
    return new SuggestResponse(items);
}
```

**原理**：
- Completion Suggester 使用 FST（Finite State Transducers）数据结构
- 内存占用小，查询速度极快（微秒级）
- 适合标题、标签等结构化数据的自动补全

### 5.3 高亮显示

```java
// 构建高亮请求
.highlight(h -> h
    .fields(new NamedValue<>("title", new HighlightField.Builder().build()))
    .fields(new NamedValue<>("body", new HighlightField.Builder().build())))

// 合并高亮片段
private String buildSnippet(Hit<Map<String, Object>> hit) {
    StringBuilder sb = new StringBuilder();
    if (hit.highlight() != null) {
        List<String> ht = hit.highlight().get("title");
        if (ht != null && !ht.isEmpty()) {
            sb.append(String.join(" ", ht));
        }
        List<String> hb = hit.highlight().get("body");
        if (hb != null && !hb.isEmpty()) {
            if (!sb.isEmpty()) sb.append(" ");
            sb.append(String.join(" ", hb));
        }
    }
    return sb.isEmpty() ? null : sb.toString();
}
```

**效果**：
```html
<title><![CDATA[<em>Elasticsearch</em> 搜索优化]]></title>
<body><![CDATA[本文介绍 <em>Elasticsearch</em> 的几种优化策略...]]></body>
```

---

## 6. 高级搜索技术

### 6.1 Function Score 详解

**作用**：在相关性评分基础上，引入业务指标（如点赞数、浏览量）进行加权排序。

```java
.query(qb -> qb.functionScore(fs -> fs
    // 基础查询
    .query(qb2 -> qb2.bool(bq -> {
        bq.must(m -> m.multiMatch(mm -> mm.query(q)
                .fields("title^3", "body")));
        bq.filter(f -> f.term(t -> t.field("status")
                .value(v -> v.stringValue("published"))));
        return bq;
    }))
    // 点赞数加权（权重 2.0）
    .functions(fn -> fn.fieldValueFactor(fvf -> fvf
        .field("like_count")
        .modifier(FieldValueFactorModifier.Log1p))
        .weight(2.0))
    // 浏览量加权（权重 1.0）
    .functions(fn -> fn.fieldValueFactor(fvf -> fvf
        .field("view_count")
        .modifier(FieldValueFactorModifier.Log1p))
        .weight(1.0))
    // 加权模式：求和
    .boostMode(FunctionBoostMode.Sum)
))
```

**Modifier 类型对比**：
| Modifier | 公式 | 适用场景 |
|----------|------|---------|
| `none` | score * weight | 线性增长，易被大值主导 |
| `log1p` | log(1 + score) * weight | 推荐！平滑增长，避免极端值 |
| `sqrt` | √score * weight | 中等平滑 |
| `reciprocal` | 1/score * weight | 倒数（少用） |

### 6.2 游标分页（Search After）

**为什么不用 from/size？**
- `from + size` 方式：每页都要扫描前面所有文档，深度分页性能差
- `search_after`：基于上一次结果的 sort 值继续，性能稳定

```java
// 1. 首次请求
List<SortOptions> sorts = ...;  // 必须包含至少一个排序字段
SearchResponse resp = es.search(s -> s
    .index(INDEX)
    .size(20)
    .sort(sorts)
);

// 2. 提取最后一行的 sort 值
List<FieldValue> lastSort = resp.hits().hits().getLast().sort();

// 3. 下一页请求
String nextAfter = Base64.getUrlEncoder().withoutPadding()
    .encodeToString(String.join(",", lastSort).getBytes());

SearchResponse nextPage = es.search(s -> s
    .index(INDEX)
    .size(20)
    .sort(sorts)
    .searchAfter(lastSort)  // 携带上次的 sort 值
);
```

**注意事项**：
- 必须指定明确的排序（不能只用 `_score`）
- 适用于实时索引，不适用于静态快照
- 不能跳转到任意页码（只能顺序翻页）

### 6.3 布尔查询组合

```java
.query(qb -> qb.bool(bq -> {
    // must：必须匹配（贡献相关性得分）
    bq.must(m -> m.multiMatch(mm -> mm.query(q)
            .fields("title^3", "body")));
    
    // filter：必须匹配（不贡献得分，可缓存）
    bq.filter(f -> f.term(t -> t.field("status")
            .value(v -> v.stringValue("published"))));
    
    // should：可选匹配（提升相关性）
    // bq.should(...);
    
    // must_not：必须不匹配
    // bq.mustNot(...);
    
    return bq;
}))
```

**must vs filter**：
- `must`：计算相关性得分，无法缓存
- `filter`：不计算得分，结果可缓存，性能更好
- **最佳实践**：确定性条件（如 status、tags）用 filter，全文检索用 must

---

## 7. 数据同步机制

### 7.1 CDC + Outbox 模式

#### 7.1.1 架构设计

```
MySQL (主库)
   │
   ├─► binlog
   │     │
   │     ▼
   │  Canal Server (监听 binlog)
   │     │
   │     ▼
   │  Kafka (canal-outbox topic)
   │           │
   │           ▼
   └──────► CanalOutboxConsumerSearch (消费者组)
                 │
                 ▼
            SearchIndexService (更新 ES)
```

#### 7.1.2 消费者实现

```java
@Service
public class CanalOutboxConsumerSearch {
    
    @KafkaListener(topics = OutboxTopics.CANAL_OUTBOX, groupId = "search-index-consumer")
    public void onMessage(String message, Acknowledgment ack) {
        try {
            // 1. 解析 Canal 消息
            List<JsonNode> rows = OutboxMessageUtil.extractRows(objectMapper, message);
            
            for (JsonNode row : rows) {
                JsonNode payload = objectMapper.readTree(row.get("payload").asText());
                String entity = text(payload.get("entity"));  // 实体类型
                String op = text(payload.get("op"));          // 操作类型：insert/update/delete
                Long id = asLong(payload.get("id"));          // 实体 ID
                
                if (!"knowpost".equals(entity) || id == null) {
                    continue;
                }
                
                // 2. 根据操作类型更新索引
                if ("delete".equalsIgnoreCase(op)) {
                    indexService.softDeleteKnowPost(id);
                } else {
                    indexService.upsertKnowPost(id);  // insert/update 都走 upsert
                }
            }
            
            // 3. 手动提交 offset（保障至少一次消费）
            ack.acknowledge();
        } catch (Exception ignored) {
            // 异常时不提交 offset，等待重试
        }
    }
}
```

**关键特性**：
1. **幂等性**：upsert 操作覆盖写入同一文档 ID，重复消费无影响
2. **软删除**：仅更新 status=deleted，不物理删除文档
3. **容错机制**：异常时不提交 offset，Kafka 会自动重试

### 7.2 索引回灌（Backfill）

**场景**：应用首次启动或 ES 索引清空后，需要批量导入历史数据。

```java
@PostConstruct
public void ensureBackfill() {
    try {
        // 1. 检查索引是否已有数据
        long cnt = es.count(c -> c.index(INDEX)).count();
        if (cnt > 0) return;  // 已有数据则跳过
        
        // 2. 分页拉取 MySQL 数据
        int limit = 500;
        int offset = 0;
        while (true) {
            List<KnowPostFeedRow> rows = knowPostMapper.listFeedPublic(limit, offset);
            if (rows == null || rows.isEmpty()) break;
            
            for (KnowPostFeedRow r : rows) {
                upsertKnowPost(r.getId());
            }
            offset += rows.size();
        }
        
        log.info("Search index backfill completed: {} documents", 
            es.count(c -> c.index(INDEX)).count());
    } catch (Exception e) {
        log.warn("Search index backfill skipped: {}", e.getMessage());
    }
}
```

**优化策略**：
- 批量处理：每次 500 条，避免单次查询过大
- 增量判断：先检查索引是否为空
- 异常隔离：回灌失败不影响应用启动

### 7.3 刷新策略

```java
IndexRequest<Map<String, Object>> req = IndexRequest.of(b -> b
    .index(INDEX)
    .id(String.valueOf(id))
    .document(doc)
    .refresh(Refresh.WaitFor)  // 关键配置
);
```

**Refresh 类型对比**：
| 类型 | 说明 | 适用场景 |
|------|------|---------|
| `False`（默认） | 不立即刷新，依赖定期刷新 | 大批量导入 |
| `WaitFor` | 等待下一次刷新完成（默认 1 秒） | **推荐！实时性要求高** |
| `True` | 强制立即刷新 | 测试环境 |

---

## 8. RAG 向量检索

### 8.1 架构设计

```
┌─────────────────┐
│  用户提问        │
│  (postId +       │
│   question)      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  RagQueryService                    │
│  1. ensureIndexed(postId)           │
│  2. similaritySearch(question)      │
│  3. 构造 Prompt                      │
│  4. 流式调用 LLM                     │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  VectorStore (Spring AI 封装)        │
│  - 将 question 转换为向量             │
│  - 在 ES 中检索相似文档               │
│  - 返回 topK 个 Document              │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Elasticsearch (zhiguang-ai-index)  │
│  - 存储文本切片 + 元数据 + 向量       │
│  - 使用 HNSW 算法加速向量检索         │
└─────────────────────────────────────┘
```

### 8.2 索引服务：RagIndexService

#### 8.2.1 核心流程

```java
@Service
public class RagIndexService {
    
    public int reindexSinglePost(long postId) {
        // 1. 查询知文详情
        KnowPostDetailRow row = knowPostMapper.findDetailById(postId);
        if (row == null) return 0;
        
        // 2. 仅索引公开的已发布内容
        if (!"published".equalsIgnoreCase(row.getStatus()) || 
            !"public".equalsIgnoreCase(row.getVisible())) {
            return 0;
        }
        
        // 3. 指纹检测（避免重复索引）
        String currentSha = row.getContentSha256();
        String currentEtag = row.getContentEtag();
        if (isUpToDate(postId, currentSha, currentEtag)) {
            log.info("Post {} already indexed, skip", postId);
            return 0;
        }
        
        // 4. 抓取 Markdown 正文
        String text = fetchContent(row.getContentUrl());
        if (!StringUtils.hasText(text)) return 0;
        
        // 5. 文本切片（按标题 + 固定长度）
        List<String> chunks = chunkMarkdown(text);
        
        // 6. 删除旧切片（保证幂等）
        deleteExistingChunks(postId);
        
        // 7. 组装 Document（文本 + 元数据）
        List<Document> docs = new ArrayList<>();
        for (int i = 0; i < chunks.size(); i++) {
            Map<String, Object> meta = new HashMap<>();
            meta.put("postId", String.valueOf(postId));
            meta.put("chunkId", postId + "#" + i);
            meta.put("position", i);
            meta.put("contentEtag", currentEtag);
            meta.put("contentSha256", currentSha);
            docs.add(new Document(chunks.get(i), meta));
        }
        
        // 8. 批量写入向量库
        vectorStore.add(docs);
        return docs.size();
    }
}
```

#### 8.2.2 文本切片策略

```java
private List<String> chunkMarkdown(String text) {
    // 1. 按 Markdown 标题分段
    List<String> paras = new ArrayList<>();
    String[] lines = text.split("\r?\n");
    StringBuilder buf = new StringBuilder();
    for (String line : lines) {
        boolean isHeader = line.startsWith("#");
        if (isHeader && !buf.isEmpty()) {
            paras.add(buf.toString());  // 收束上一段
            buf.setLength(0);
        }
        buf.append(line).append('\n');
    }
    if (!buf.isEmpty()) paras.add(buf.toString());
    
    // 2. 固定长度切片（带重叠）
    return getChunks(paras);
}

private static List<String> getChunks(List<String> paras) {
    List<String> chunks = new ArrayList<>();
    for (String p : paras) {
        if (p.length() <= 800) {
            chunks.add(p);  // 短段落直接作为一片
        } else {
            // 长文本按 800 字符切片，片间重叠 100 字符
            int start = 0;
            while (start < p.length()) {
                int end = Math.min(start + 800, p.length());
                chunks.add(p.substring(start, end));
                if (end >= p.length()) break;
                start = Math.max(end - 100, start + 1);  // 重叠保留语义连续
            }
        }
    }
    return chunks;
}
```

**设计要点**：
- **按标题分段**：保持语义完整性
- **固定长度**：适配向量模型输入限制
- **重叠切片**：避免上下文断裂（重叠 100 字符）

#### 8.2.3 指纹去重机制

```java
private boolean isUpToDate(long postId, String currentSha, String currentEtag) {
    // 查询已索引文档的 metadata
    SearchResponse<Map> resp = es.search(s -> s
        .index(esProps.getIndex())
        .size(1)
        .query(q -> q.term(t -> t
            .field("metadata.postId")
            .value(v -> v.stringValue(String.valueOf(postId))))),
        Map.class);
    
    List<Hit<Map>> hits = resp.hits().hits();
    if (hits == null || hits.isEmpty()) return false;
    
    Map source = hits.getFirst().source();
    Object metaObj = source.get("metadata");
    if (!(metaObj instanceof Map<?, ?> meta)) return false;
    
    String indexedSha = asString(meta.get("contentSha256"));
    String indexedEtag = asString(meta.get("contentEtag"));
    
    // 优先比较 SHA256，其次 ETag
    if (StringUtils.hasText(currentSha) && StringUtils.hasText(indexedSha)) {
        return Objects.equals(currentSha, indexedSha);
    }
    if (StringUtils.hasText(currentEtag) && StringUtils.hasText(indexedEtag)) {
        return Objects.equals(currentEtag, indexedEtag);
    }
    return false;
}
```

**优势**：
- 避免重复索引，节省存储空间
- 内容未变更时跳过重建，提升效率

### 8.3 查询服务：RagQueryService

```java
@Service
public class RagQueryService {
    
    public Flux<String> streamAnswerFlux(long postId, String question, int topK, int maxTokens) {
        // 1. 保障索引最新
        indexService.ensureIndexed(postId);
        
        // 2. 检索上下文（宽召回 + 服务端过滤）
        List<String> contexts = searchContexts(String.valueOf(postId), question, topK);
        String context = String.join("\n\n---\n\n", contexts);
        
        // 3. 构造 Prompt
        String system = "你是中文知识助手。只能依据提供的知文上下文回答；无法确定的请说明不确定。";
        String user = "问题：" + question + "\n\n上下文如下（可能不完整）：\n" + context + 
                      "\n\n请基于以上上下文作答。";
        
        // 4. 流式调用 LLM
        return chatClient
            .prompt()
            .system(system)
            .user(user)
            .options(DeepSeekChatOptions.builder()
                .model("deepseek-chat")
                .temperature(0.2)  // 低温度，更稳健
                .maxTokens(maxTokens)
                .build())
            .stream()
            .content();  // 返回 Flux<String>
    }
    
    private List<String> searchContexts(String postId, String query, int topK) {
        // 宽召回：扩大初始检索集合，提高召回率
        int fetchK = Math.max(topK * 3, 20);
        List<Document> docs = vectorStore.similaritySearch(
            SearchRequest.builder().query(query).topK(fetchK).build());
        
        // 服务端过滤：仅保留当前帖子的切片
        List<String> out = new ArrayList<>(topK);
        for (Document d : docs) {
            Object pid = d.getMetadata().get("postId");
            if (pid != null && postId.equals(String.valueOf(pid))) {
                String txt = d.getText();
                if (txt != null && !txt.isEmpty()) {
                    out.add(txt);
                    if (out.size() >= topK) break;
                }
            }
        }
        return out;
    }
}
```

**关键技术**：
1. **宽召回策略**：先召回 3×topK 个文档，再过滤，避免漏检
2. **Metadata 过滤**：在向量检索后用 postId 过滤，防止跨帖子污染
3. **流式输出**：使用 WebFlux 的 Flux 实现 SSE 流式响应

### 8.4 向量模型配置

```yaml
spring:
  ai:
    openai:
      base-url: https://dashscope.aliyuncs.com/compatible-mode
      api-key: sk-xxx
      embedding:
        options:
          model: text-embedding-v4  # 通义千问向量模型
          dimensions: 1536          # 向量维度
```

**注意**：
- 向量维度必须与 ES 索引配置一致
- 不同模型的维度不同（如 text-embedding-ada-002 也是 1536 维）

---

## 9. 性能优化策略

### 9.1 索引层面优化

#### 9.1.1 字段级别优化

```java
// ✅ 好的实践
.properties("title", p -> p.text(TextProperty.of(b -> b
    .analyzer("ik_max_word")
    .searchAnalyzer("ik_smart"))))  // 搜索时使用更粗粒度分词

.properties("tags", p -> p.keyword(KeywordProperty.of(b -> b)))  // 精确匹配用 keyword

// ❌ 避免的做法
.properties("description", p -> p.text(TextProperty.of(b -> b
    .analyzer("standard"))))  // 中文场景不要用 standard 分词器
```

#### 9.1.2 Mapping 设计原则

1. **能 Keyword 不 Text**：不需要全文检索的字段用 Keyword
2. **关闭不必要的 doc_values**：如果字段不用于排序/聚合
3. **合理设置分词器**：中文场景使用 IK，英文使用 standard

### 9.2 查询层面优化

#### 9.2.1 Filter 上下文缓存

```java
// ✅ 使用 filter（可缓存）
bq.filter(f -> f.term(t -> t.field("status")
    .value(v -> v.stringValue("published"))));

// ❌ 避免在 must 中使用确定性条件
bq.must(m -> m.term(t -> t.field("status")
    .value(v -> v.stringValue("published"))));  // 会计算相关性，无法缓存
```

#### 9.2.2 避免深度分页

```java
// ✅ 使用 search_after（推荐）
.searchAfter(lastSort)

// ❌ 避免 deep pagination
.from(10000).size(20)  // 性能极差
```

#### 9.2.3 减少返回字段

```java
// ✅ 使用 _source 过滤
.source(s -> s.filter(f -> f.includes("title", "description", "publish_time")))

// ❌ 返回整个_source
// 默认行为，浪费网络带宽
```

### 9.3 写入优化

#### 9.3.1 批量写入

```java
// ✅ 批量写入（BulkRequest）
BulkRequest bulkRequest = new BulkRequest();
for (Document doc : docs) {
    bulkRequest.add(new IndexRequest(INDEX)
        .id(doc.getId())
        .source(doc.getSource()));
}
es.bulk(bulkRequest);

// ❌ 单条写入（循环调用 index）
for (Document doc : docs) {
    es.index(new IndexRequest(INDEX)...);  // 网络开销大
}
```

#### 9.3.2 刷新间隔调整

```java
// 批量导入场景
IndexRequest req = IndexRequest.of(b -> b
    .index(INDEX)
    .document(doc)
    .refresh(Refresh.False));  // 不立即刷新，依赖定期刷新

// 实时写入场景
IndexRequest req = IndexRequest.of(b -> b
    .index(INDEX)
    .document(doc)
    .refresh(Refresh.WaitFor));  // 等待下一次刷新（默认 1s）
```

### 9.4 缓存策略

#### 9.4.1 Query Cache

ES 自动缓存 filter 查询结果，以下场景可命中缓存：
- `term`、`terms` 查询
- `range` 查询
- `bool` 查询中的 filter 子句

**提升命中率**：
```java
// ✅ 复用相同的 filter 条件
bq.filter(f -> f.term(t -> t.field("status").value("published")));

// ❌ 动态值无法缓存
bq.filter(f -> f.range(r -> r.field("publish_time")
    .gte(System.currentTimeMillis())));  // 每次值不同
```

#### 9.4.2 Request Cache

适用于聚合查询结果缓存：
```yaml
# 配置示例
indices.queries.cache.size: 10%
```

### 9.5 硬件层面优化

| 资源 | 建议 | 原因 |
|------|------|------|
| **内存** | 至少 32GB，堆内存不超过 31GB | 避免 Compressed Oops 失效 |
| **磁盘** | SSD，RAID 0 | I/O 密集型场景 |
| **CPU** | 4 核以上 | 并行处理能力 |
| **网络** | 千兆内网 | 节点间通信 |

---

## 10. 面试考点汇总

### 10.1 基础概念

#### Q1: Elasticsearch 的核心概念有哪些？

**答案**：
1. **索引（Index）**：类似数据库中的"表"，是文档的集合
2. **文档（Document）**：基本数据单元，JSON 格式
3. **类型（Type）**：7.x 已废弃，一个索引只有一个类型
4. **分片（Shard）**：索引的数据分区，支持水平扩展
5. **副本（Replica）**：分片的备份，提供高可用
6. **Mapping**：定义字段类型和分析器，类似数据库 schema
7. **Analyzer**：分词器，决定文本如何被拆分和索引

#### Q2: Text 和 Keyword 的区别？

| 特性 | Text | Keyword |
|------|------|---------|
| **分词** | 是分词 | 不分词 |
| **分析器** | 需要指定 | 不适用 |
| **查询方式** | 全文检索（match） | 精确匹配（term） |
| **聚合/排序** | 不支持 | 支持 |
| **典型场景** | 文章正文、标题 | 标签、状态、枚举值 |

#### Q3: 倒排索引的原理？

**答案**：
倒排索引 = 术语词典（Term Dictionary） + 倒排列表（Posting List）

```
文档 1: "Elasticsearch 是一个搜索引擎"
文档 2: "Elasticsearch 支持全文检索"

倒排索引：
Elasticsearch → [文档 1, 文档 2]
是一个        → [文档 1]
搜索引擎      → [文档 1]
支持          → [文档 2]
全文检索      → [文档 2]
```

**优势**：
- 快速定位包含某个词的文档
- 支持布尔运算（AND/OR/NOT）
- 压缩存储（Frame of Reference、FORU）

### 10.2 查询优化

#### Q4: 如何提高搜索相关性？

**答案**：
1. **字段加权**：`title^3, body` 提升标题权重
2. **Function Score**：引入点赞、浏览等业务指标加权
3. **对数修饰符**：`Log1p` 防止计数过大导致排序失衡
4. **同义词扩展**：使用 synonym 分析器扩展查询词
5. **拼写纠错**：使用 term/fuzzy suggester 纠正拼写错误
6. **个性化排序**：根据用户画像调整排序策略

#### Q5: filter 和 query 的区别？

| 特性 | filter | query |
|------|--------|-------|
| **相关性得分** | 不计算 | 计算 |
| **缓存** | 可缓存 | 不可缓存 |
| **性能** | 更高 | 较低 |
| **适用场景** | 确定性条件（状态、时间范围） | 全文检索、模糊匹配 |

**最佳实践**：能用 filter 就不用 query

#### Q6: 深度分页有什么解决方案？

**答案**：
1. **search_after**（推荐）：基于上一次结果的 sort 值继续
2. **Scroll API**：适用于批量导出，不适用于实时搜索
3. **限制页数**：业务层面限制最大页码（如最多 100 页）
4. **游标编码**：将 sort 值 Base64 编码传递给前端

### 10.3 写入优化

#### Q7: 如何提升批量写入性能？

**答案**：
1. **批量写入**：使用 BulkRequest，每次 1000-5000 条
2. **调整刷新间隔**：`refresh_interval: 30s` 降低刷新频率
3. **禁用副本**：批量导入时设置 `number_of_replicas: 0`
4. **增加堆内存**：ES 堆内存设置为物理内存的 50%
5. **使用 BulkProcessor**：自动批量提交
6. **关闭_source**：如果不需要返回原始文档

#### Q8: refresh、flush、merge 的区别？

| 操作 | 作用 | 频率 |
|------|------|------|
| **refresh** | 使文档可被搜索 | 默认 1 秒 |
| **flush** | 将内存数据持久化到磁盘 | 默认 30 分钟或 translog 满 |
| **merge** | 合并小 segment 为大 segment | 后台线程自动 |

**Segment**：Lucene 的基本存储单元，每个 segment 是一个不可变的倒排索引

### 10.4 高可用架构

#### Q9: ES 集群如何实现高可用？

**答案**：
1. **副本分片**：每个主分片配置 1-N 个副本
2. **故障转移**：主节点故障时自动选举新主节点
3. **脑裂防护**：`discovery.zen.minimum_master_nodes: (N/2)+1`
4. **跨机房部署**：使用 shard allocation awareness
5. **监控告警**：监控节点健康度、JVM 内存、磁盘使用率

#### Q10: 分片策略如何设计？

**答案**：
1. **分片数量**：单个分片大小控制在 30-50GB
2. **分片公式**：`分片数 = 数据总量 / 50GB`（向上取整）
3. **预留扩展**：分片数略多于当前需求，支持未来增长
4. **路由优化**：自定义 routing 值，将相关文档路由到同一分片

### 10.5 实战场景

#### Q11: 如何实现中文搜索？

**答案**：
1. **安装 IK 分词器**：`elasticsearch-plugin install ik`
2. **配置分析器**：
   ```json
   "analyzer": {
     "ik_max_word": {"type": "ik_max_word"},  // 细粒度分词
     "ik_smart": {"type": "ik_smart"}          // 粗粒度分词
   }
   ```
3. **索引/搜索分离**：索引用 `ik_max_word`，搜索用 `ik_smart`
4. **同义词扩展**：配置 `synonym.txt` 文件
5. **拼音支持**：安装 pinyin 插件，支持拼音首字母搜索

#### Q12: 如何实现自动补全？

**答案**：
1. **Completion Suggester**（推荐）：
   - 使用 FST 数据结构，查询速度极快
   - 适合结构化数据（标题、标签）
   ```json
   "title_suggest": {
     "type": "completion"
   }
   ```
2. **Term Suggester**：
   - 基于词项统计，适合拼写纠错
3. **Phrase Suggester**：
   - 基于语言模型，适合整句补全

#### Q13: 如何保证数据一致性？

**答案**：
1. **CDC + Outbox**：通过 Canal 监听 binlog，保证可靠同步
2. **幂等写入**：upsert 操作覆盖同一文档 ID
3. **版本号控制**：使用 ES 的 `_version` 或外部版本号
4. **定时对账**：定期比对 MySQL 和 ES 数据，修复不一致
5. **事务消息**：通过 Kafka 事务保证 Exactly-Once 语义

### 10.6 RAG 相关

#### Q14: RAG 的工作原理是什么？

**答案**：
RAG（Retrieval-Augmented Generation）= 检索 + 生成

```
1. 用户提问
   ↓
2. 将问题转换为向量（Embedding）
   ↓
3. 在向量数据库中检索相似文档（TopK）
   ↓
4. 将检索到的上下文与问题组装为 Prompt
   ↓
5. 发送给 LLM 生成回答
   ↓
6. 返回给用户
```

**优势**：
- 减少 LLM 幻觉（基于事实作答）
- 支持私有知识库
- 降低上下文长度，节省 Token

#### Q15: 向量检索的原理？

**答案**：
1. **向量化**：使用 Embedding 模型将文本转换为向量（如 1536 维浮点数）
2. **相似度计算**：
   - 余弦相似度（Cosine Similarity）：最常用
   - 欧氏距离（Euclidean Distance）
   - 点积（Dot Product）
3. **近似最近邻（ANN）**：
   - HNSW（Hierarchical Navigable Small World）：ES 默认算法
   - IVF（Inverted File Index）：Faiss 使用
4. **过滤优化**：先宽召回再过滤，避免跨文档污染

#### Q16: 如何优化 RAG 的召回质量？

**答案**：
1. **文本切片策略**：
   - 按语义分段（标题、段落）
   - 固定长度 + 重叠（避免上下文断裂）
2. **宽召回 + 精排**：
   - 先召回 3×topK 个文档
   - 再用 Cross-Encoder 重排序
3. **Metadata 过滤**：
   - 按 postId、时间范围等过滤
4. **混合检索**：
   - 关键词检索（BM25）+ 向量检索
   - 使用 Reciprocal Rank Fusion（RRF）融合结果
5. **Prompt 优化**：
   - 明确指示 LLM 只基于上下文作答
   - 提供示例（Few-shot Learning）

---

## 附录：常见问题排查

### A.1 索引创建失败

**现象**：应用启动时报错 `index_already_exists_exception`

**解决**：
```java
try {
    boolean exists = es.indices().exists(e -> e.index(INDEX)).value();
    if (!exists) {
        es.indices().create(c -> c.index(INDEX).mappings(...));
    }
} catch (Exception e) {
    log.warn("Index creation failed: {}", e.getMessage());
}
```

### A.2 中文分词失效

**现象**：搜索中文无法匹配

**检查**：
1. IK 分词器是否安装：`GET /_cat/plugins?v`
2. Mapping 是否配置 analyzer：`GET /zhiguang_content_index/_mapping`
3. 测试分词效果：
   ```
   POST /_analyze
   {
     "analyzer": "ik_max_word",
     "text": "Elasticsearch 搜索"
   }
   ```

### A.3 向量检索报错

**现象**：`dimension_mismatch_exception`

**原因**：查询向量维度与索引配置不一致

**解决**：
1. 检查 embedding 模型配置的 dimensions
2. 确认 ES 索引的 vector 字段维度
3. 确保两者一致（如都是 1536 维）

### A.4 数据同步延迟

**现象**：MySQL 更新后 ES 搜索不到

**排查步骤**：
1. 检查 Canal 是否正常监听 binlog
2. 查看 Kafka 消息积压情况
3. 验证消费者组是否正常消费
4. 检查 ES 写入日志是否有异常

---

## 总结

本文档详细介绍了项目中 Elasticsearch 搜索模块的配置、使用和运维知识，涵盖：

1. **基础配置**：ES 客户端配置、索引 Mapping 设计
2. **核心功能**：关键词搜索、联想建议、高亮显示
3. **高级技术**：Function Score、游标分页、布尔查询
4. **数据同步**：CDC + Outbox 模式、索引回灌
5. **RAG 检索**：向量索引、文本切片、语义检索
6. **性能优化**：索引/查询/写入优化策略
7. **面试考点**：ES 核心概念、实战场景、RAG 原理

掌握这些知识不仅有助于理解项目代码，也能应对面试中的 ES 相关问题。
