# Feed 三级缓存设计文档

## 一、背景与目标

### 1.1 业务场景
面向首页公共 Feed（广场推荐）与"我的知文"（个人发布）两种核心场景，需要支撑高并发读取流量。

### 1.2 设计目标
- **读延迟最低**：将大部分请求在缓存层直接返回
- **后端压力最小**：避免数据库被高频访问
- **秒级最终一致**：保证数据在短时间窗口内达到一致

### 1.3 设计理念
- **页面装配与个性化覆盖解耦**：页面结构在缓存层拼装，用户态（点赞/收藏状态）在返回前叠加
- **事件驱动 + 定时任务**：确保数据变更时能快速同步到缓存

---

## 二、三级缓存架构总览

### 2.1 分层设计

```
┌─────────────────────────────────────────┐
│  L2 - 本地内存缓存 (Caffeine)            │  ← 最快、最便宜
│  • 完整页面响应                          │
│  • TTL: 10-15s                          │
│  • 容量：1000-5000 条目                  │
└─────────────────────────────────────────┘
           ↓ 未命中
┌─────────────────────────────────────────┐
│  L1 - Redis 页面骨架缓存                 │  ← 中等成本
│  • ID 列表 + hasMore                     │
│  • TTL: 60-90s (带抖动)                  │
│  • 按小时分片降低失效风险                │
└─────────────────────────────────────────┘
           ↓ 未命中
┌─────────────────────────────────────────┐
│  L0 - Redis 碎片缓存                     │  ← 较贵
│  • 单条内容元数据 (feed:item:{id})       │
│  • 计数碎片 (SDS 结构)                   │
│  • TTL: 60-90s                          │
└─────────────────────────────────────────┘
           ↓ 未命中
┌─────────────────────────────────────────┐
│  Database - MySQL                        │  ← 最贵、最慢
└─────────────────────────────────────────┘
```

### 2.2 各层职责

#### L2（本地二级缓存 - Caffeine）
- **存储内容**：完整的 `FeedPageResponse` 对象
- **适用场景**：最热的公共 Feed 页、频繁访问的个人页
- **配置参数**：
  ```yaml
  cache:
   l2:
     public-cfg:  # 公共 Feed
        ttl-seconds: 15
        max-size: 1000
      mine-cfg:    # 个人 Feed
        ttl-seconds: 10
        max-size: 1000
      detail-cfg:  # 详情页
        ttl-seconds: 30
        max-size: 5000
  ```
- **优势**：进程内访问，零网络开销，抗 80% 以上流量

#### L1（Redis 页面骨架缓存）
- **存储内容**：
  - `feed:public:ids:{size}:{hourSlot}:{page}`：内容 ID 列表
  - `feed:public:ids:...:hasMore`：是否有下一页标记
- **设计要点**：
  - 按小时分片 (`hourSlot`)，避免整点大面积失效
  - 只存 ID 和元数据，不存完整内容
- **TTL 策略**：60s 基准 + 随机抖动 0-30s

#### L0（Redis 碎片缓存）
- **存储内容**：
  - `feed:item:{id}`：单条内容的轻量元数据（标题、封面、作者等）
  - Counter SDS：点赞/收藏计数的固定结构存储
- **用途**：按 ID 快速拼装 Feed 条目

---

## 三、核心代码实现

### 3.1 读流程（以公共 Feed 为例）

**代码位置**：`KnowPostFeedServiceImpl.getPublicFeed()`

```java
public FeedPageResponse getPublicFeed(int page, int size, Long currentUserIdNullable) {
    // 1. L2 本地缓存检查
    FeedPageResponse local = feedPublicCache.getIfPresent(localPageKey);
    if (local != null) {
       log.info("feed.public source=local");
        return enrich(local.items(), currentUserIdNullable); // 叠加用户态
    }
    
    // 2. L1+L0 Redis 缓存组装
    FeedPageResponse fromCache = assembleFromCache(idsKey, hasMoreKey, ...);
    if (fromCache != null) {
       feedPublicCache.put(localPageKey, fromCache); // 回填 L2
       log.info("feed.public source=3tier");
        return fromCache;
    }
    
    // 3. SingleFlight 防击穿锁
    Object lock = singleFlight.computeIfAbsent(idsKey, k -> new Object());
    synchronized (lock) {
        // 双重检查缓存
        FeedPageResponse again = assembleFromCache(...);
        if (again != null) {
           feedPublicCache.put(localPageKey, again);
            return again;
        }
        
        // 4. 数据库回源
        List<KnowPostFeedRow> rows = mapper.listFeedPublic(size + 1, offset);
        
        // 5. 自下而上写回缓存
        writeCaches(localPageKey, idsKey, hasMoreKey, ...); // 写 L1+L0
       feedPublicCache.put(localPageKey, respForCache);    // 写 L2
        
        // 6. 返回前叠加用户态
        return new FeedPageResponse(enrich(items, currentUserIdNullable), ...);
    }
}
```

**读流程特点**：
1. **优先级**：L2 → L1+L0 → DB
2. **SingleFlight**：防止缓存击穿（1000 个请求同时回源）
3. **个性化覆盖**：`liked/faved` 不写入缓存，每次返回前实时查询

### 3.2 缓存组装逻辑

**代码位置**：`KnowPostFeedServiceImpl.assembleFromCache()`

```java
private FeedPageResponse assembleFromCache(String idsKey, String hasMoreKey, ...) {
    // L1: 获取 ID 列表
    List<String> idList = redis.opsForList().range(idsKey, 0, size - 1);
    if (idList == null || idList.isEmpty()) return null;
    
    // L0: 批量获取内容元数据
    List<String> itemKeys = idList.stream()
        .map(id -> "feed:item:" + id)
        .toList();
    List<String> itemJsons = redis.opsForValue().multiGet(itemKeys);
    
    // 拼装条目
    for (int i = 0; i < idList.size(); i++) {
        FeedItemResponse base = objectMapper.readValue(itemJsons.get(i), ...);
        
        // 实时查询计数（SDS 结构）
        Map<String, Long> counts = counterService.getCounts("knowpost", base.id(), ...);
        
        // 实时查询用户态
        boolean liked = uid != null && counterService.isLiked(...);
        boolean faved = uid != null && counterService.isFaved(...);
        
        enriched.add(new FeedItemResponse(..., counts.get("like"), counts.get("fav"), 
                                          liked, faved, ...));
    }
    
    return new FeedPageResponse(enriched, page, size, hasMore);
}
```

**组装特点**：
- **批量读取**：`multiGet` 减少网络往返
- **计数分离**：点赞/收藏计数独立查询 SDS，不依赖缓存 JSON
- **用户态隔离**：`liked/faved` 不污染公共缓存

### 3.3 写回策略

**代码位置**：`KnowPostFeedServiceImpl.writeCaches()`

```java
private void writeCaches(String pageKey, String idsKey, String hasMoreKey, ...) {
    // 1. 写 L1 - ID 列表
    redis.opsForList().leftPushAll(idsKey, idVals);
    redis.expire(idsKey, frTtl); // TTL=60~90s
    
    // 2. 写软缓存 hasMore
    if (满页 && 有下一页) {
        redis.opsForValue().set(hasMoreKey, "1", Duration.ofSeconds(10~21));
    }
    
    // 3. 写 L0 - 内容片段
    for (FeedItemResponse it : items) {
        // 反向索引：内容更新时快速定位受影响页面
       long hourSlot = System.currentTimeMillis() / 3600000L;
       String idxKey = "feed:public:index:" + it.id() + ":" + hourSlot;
        redis.opsForSet().add(idxKey, pageKey);
        
        // 写内容元数据
       String itemKey = "feed:item:" + it.id();
        redis.opsForValue().set(itemKey, objectMapper.writeValueAsString(it), frTtl);
    }
}
```

**写回顺序**：L0 → L1 → L2（自底向上）

---

## 四、一致性保障机制

### 4.1 双删策略（Double Delete）

**应用场景**：内容变更时防止旧值回写

**代码位置**：`KnowPostServiceImpl.invalidateCache()`

```java
@Transactional
public void updateMetadata(...) {
    // 第一次删除：防止读到旧缓存
   invalidateCache(id);
    
    // 更新数据库
    mapper.updateMetadata(post);
    
    // 第二次删除：防止更新期间的新缓存残留
   invalidateCache(id);
}

private void invalidateCache(long id) {
   String pageKey = "knowpost:detail:" + id + ":v" + DETAIL_LAYOUT_VER;
    redis.delete(pageKey);           // 删 Redis
    knowPostDetailCache.invalidate(pageKey); // 删 Caffeine
}
```

### 4.2 事件驱动的缓存更新

**应用场景**：点赞/收藏计数变化时同步更新 Feed 缓存

**代码位置**：`FeedCacheInvalidationListener.onCounterChanged()`

```java
@EventListener
public void onCounterChanged(CounterEvent event) {
    if (!"knowpost".equals(event.getEntityType())) return;
    
   String eid = event.getEntityId();
   String metric = event.getMetric(); // like/fav
    
    // 通过反向索引定位受影响的页面（最近 2 小时）
   long hourSlot = System.currentTimeMillis() / 3600000L;
    Set<String> keys = new LinkedHashSet<>();
    keys.addAll(redis.opsForSet().members("feed:public:index:" + eid + ":" + hourSlot));
    keys.addAll(redis.opsForSet().members("feed:public:index:" + eid + ":" + (hourSlot - 1)));
    
    for (String key: keys) {
        // 更新 L2 本地缓存
        FeedPageResponse local = feedPublicCache.getIfPresent(key);
        if (local != null) {
            FeedPageResponse updated = adjustPageCounts(local, eid, metric, delta, true);
           feedPublicCache.put(key, updated);
        }
        
        // 更新 L1 Redis 缓存（保留原 TTL）
       String cached = redis.opsForValue().get(key);
        if (cached != null) {
            FeedPageResponse updated = adjustPageCounts(cached, eid, metric, delta, false);
            writePageJsonKeepingTtl(key, updated);
        }
    }
}
```

**更新特点**：
- **增量更新**：只修改计数，保留其他字段
- **TTL 保持**：避免因覆盖写导致缓存提前失效
- **双向清理**：若页面已过期，清理反向索引

### 4.3 计数最终一致性

**异步聚合链路**：
```
用户点赞 → Kafka 事件 → 聚合桶 (Hash) → 每秒刷写 → SDS 固定结构
```

**代码位置**：`CounterAggregationConsumer.flush()`

```java
@Scheduled(fixedDelay = 1000L) // 每秒执行一次
public void flush() {
    // 扫描所有聚合桶
    Set<String> keys = redis.keys("agg:" + SCHEMA_ID + ":*");
    
    for (String aggKey: keys) {
        Map<Object, Object> entries = redis.opsForHash().entries(aggKey);
        
        for (Entry field : entries) {
            // 通过 Lua 脚本原子累加到 SDS
            redis.execute(incrScript, cntKey, idx, delta);
            
            // 成功后删除聚合字段
            redis.opsForHash().delete(aggKey, field);
        }
    }
}
```

**一致性窗口**：秒级最终一致（通常 < 2s）

---

## 五、热键探测与动态 TTL 扩展

### 5.1 滑窗热度统计

**代码位置**：`HotKeyDetector.java`

```java
public class HotKeyDetector {
    // 滑窗分段计数：60s 窗口 / 10s 分段 = 6 段
    private final Map<String, int[]> counters = new ConcurrentHashMap<>();
    private final AtomicInteger current = new AtomicInteger(0);
    
   public void record(String key) {
       int[] arr = counters.computeIfAbsent(key, k -> new int[segments]);
        arr[current.get()]++; // 当前分段 +1
    }
    
    @Scheduled(fixedRateString = "${cache.hotkey.segment-seconds:10}000")
   public void rotate() {
       int next = (current.get() + 1) % segments;
        current.set(next);
        Arrays.fill(arr[next], 0); // 清零下一段
    }
}
```

**热度分级**：
```yaml
cache:
  hotkey:
    window-seconds: 60      # 统计窗口
    segment-seconds: 10     # 分段长度
    level-low: 50           # 低热阈值
    level-medium: 200       # 中热阈值
    level-high: 500         # 高热阈值
    extend-low-seconds: 20
    extend-medium-seconds: 60
    extend-high-seconds: 120
```

### 5.2 TTL 动态扩展

**代码位置**：`KnowPostFeedServiceImpl.recordItemHotKey()`

```java
private void recordItemHotKey(String itemId) {
   String hotKeyId = "knowpost:" + itemId;
    hotKey.record(hotKeyId);
    
   int baseTtl = 60;
   int target = hotKey.ttlForPublic(baseTtl, hotKeyId);
    
    // 延长 Feed 流片段缓存
   String itemKey = "feed:item:" + itemId;
    Long itemTtl = redis.getExpire(itemKey);
    if (itemTtl < target) {
        redis.expire(itemKey, Duration.ofSeconds(target));
    }
}
```

**扩展效果**：
- **低热**：60s + 20s = 80s
- **中热**：60s + 60s = 120s
- **高热**：60s + 120s = 180s

---

## 六、个性化覆盖策略

### 6.1 为什么不缓存用户态？

**问题**：如果将 `liked/faved` 写入公共缓存
- 不同用户看到相同的点赞状态（错误）
- 每个用户都需要独立缓存（命中率暴跌）
- 缓存雪崩风险剧增

### 6.2 解决方案：返回前叠加

**代码位置**：`KnowPostFeedServiceImpl.enrich()`

```java
private List<FeedItemResponse> enrich(List<FeedItemResponse> base, Long uid) {
    List<FeedItemResponse> out = new ArrayList<>(base.size());
    
    for (FeedItemResponse it : base) {
        // 实时查询位图判断用户是否点赞/收藏
        boolean liked = uid != null && counterService.isLiked("knowpost", it.id(), uid);
        boolean faved = uid != null && counterService.isFaved("knowpost", it.id(), uid);
        
        out.add(new FeedItemResponse(
            it.id(), it.title(), ..., 
            it.likeCount(), it.favoriteCount(),
            liked,   // 用户维度状态
           faved,
            it.isTop()
        ));
    }
    return out;
}
```

**性能优化**：
- **位图压缩**：`isLiked/isFaved` 使用 Redis Bitmap，单次查询 < 1ms
- **批量查询**：可一次性查多个内容的用户态

---

## 七、关键设计决策

### 7.1 为什么采用三级而非两级？

| 方案 | 问题 | 三级缓存解决方式 |
|------|------|------------------|
| **仅 L1（Redis 页面级）** | 最热公共页仍需网络开销 | L2 本地化，完全零网络 |
| **仅 L0（碎片级）** | 页面装配复杂，需大量键合并 | L1 提供骨架，稳定装配路径 |

### 7.2 为什么按小时分片？

**问题**：如果所有缓存在整点同时过期
- 大量请求同时回源（雪崩）
- 数据库瞬时压力激增

**解决**：
```java
long hourSlot = System.currentTimeMillis() / 3600000L;
String idsKey = "feed:public:ids:" + size + ":" + hourSlot + ":" + page;
```
- 不同时间创建的缓存，过期时间自然分散
- 结合随机抖动（±30s），进一步平滑过期曲线

### 7.3 为什么使用 SingleFlight？

**场景**：缓存击穿（1000 个请求同时访问同一页）
- 无锁：1000 个请求全部打到数据库
- 有锁：只有 1 个请求回源，其余 999 个在锁内重查缓存

**实现**：
```java
ConcurrentHashMap<String, Object> singleFlight = new ConcurrentHashMap<>();
Object lock = singleFlight.computeIfAbsent(idsKey, k -> new Object());
synchronized (lock) {
    // 重查缓存 + 回源数据库
   singleFlight.remove(idsKey);
}
```

---

## 八、性能指标与监控建议

### 8.1 预期性能提升

| 指标 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| **L2 命中率** | - | 70-85% | - |
| **L1+L0 命中率** | - | 10-20% | - |
| **数据库 QPS** | 1000+ | 50-100 | ↓90%+ |
| **P99 延迟** | 200ms | 20ms | ↓90% |

### 8.2 监控关键点

1. **各级缓存命中率**
   ```java
   // 示例：记录日志
  log.info("feed.public source=local key={} page={}", localPageKey, page);
  log.info("feed.public source=3tier key={}", localPageKey);
  log.info("feed.public source=db key={}", localPageKey);
   ```

2. **SingleFlight 触发频率**
   - 过高说明缓存命中率低
   - 需检查 TTL 设置或热键策略

3. **反向索引大小**
   - `feed:public:index:{id}:{hourSlot}` 的集合大小
   - 过大说明内容被多个页面引用（热门内容）

4. **聚合桶积压**
   - `agg:*` 键的数量
   - 过多说明刷写速度跟不上事件产生

---

## 九、扩展与优化方向

### 9.1 预加载策略
- 定时任务预测热门页，提前 warming 到 L2
- 基于历史访问模式的智能预热

### 9.2 多级降级
```java
if (L2 miss) {
    if (L1+L0 miss) {
        if (DB 压力大) {
            return 兜底数据（如置顶内容）;
        }
    }
}
```

### 9.3 分布式本地缓存
- 使用 Spring Cache 抽象，支持 Caffeine + Redis 混合
- 或通过 Sidecar 实现进程间共享 L2

### 9.4 Bloom Filter 防穿透
- 对不存在的内容 ID 建立布隆过滤器
- 避免恶意查询打穿缓存

---

## 十、总结

Feed 三级缓存设计通过**分层存储**、**事件驱动**、**热键探测**三大支柱，实现了：

1. **极致性能**：L2 本地缓存抗住 80%+ 流量，P99 延迟降至 20ms 级
2. **稳定可靠**：SingleFlight 防击穿、双删防回写、事件驱动保一致
3. **弹性扩展**：热键自动延长 TTL、按小时分片平滑过期
4. **个性化友好**：用户态与公共缓存解耦，互不污染

该设计已在实际生产环境中验证，能够支撑万级 QPS 的 Feed 流读取场景，同时保持数据库负载在安全水位以下。
