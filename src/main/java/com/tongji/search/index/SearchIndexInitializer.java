package com.tongji.search.index;

import co.elastic.clients.elasticsearch.ElasticsearchClient;
import co.elastic.clients.elasticsearch._types.mapping.CompletionProperty;
import co.elastic.clients.elasticsearch._types.mapping.DateProperty;
import co.elastic.clients.elasticsearch._types.mapping.IntegerNumberProperty;
import co.elastic.clients.elasticsearch._types.mapping.KeywordProperty;
import co.elastic.clients.elasticsearch._types.mapping.LongNumberProperty;
import co.elastic.clients.elasticsearch._types.mapping.Property;
import co.elastic.clients.elasticsearch._types.mapping.TextProperty;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;

/**
 * 搜索索引初始化：应用启动时确保索引与 Mapping 存在。
 * 默认使用 IK 分词器；本地 Docker 配置使用 ES 内置 standard 分词器。
 */
@Service
@RequiredArgsConstructor
public class SearchIndexInitializer {
    private final ElasticsearchClient es;
    private static final String INDEX = "zhiguang_content_index";
    @Value("${search.index-analyzer:ik_max_word}")
    private String indexAnalyzer;
    @Value("${search.query-analyzer:ik_smart}")
    private String queryAnalyzer;

    @PostConstruct
    public void ensureIndex() {
        try {
            boolean exists = es.indices().exists(e -> e.index(INDEX)).value();
            if (exists) {
                return;
            }

            es.indices().create(c -> c.index(INDEX).mappings(m -> m
                    .properties("content_id", Property.of(p -> p.long_(LongNumberProperty.of(b -> b))))
                    .properties("content_type", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("description", Property.of(p -> p.text(TextProperty.of(b -> b.analyzer(indexAnalyzer)))))
                    .properties("title", Property.of(p -> p.text(TextProperty.of(b -> b.analyzer(indexAnalyzer).searchAnalyzer(queryAnalyzer)))))
                    .properties("body", Property.of(p -> p.text(TextProperty.of(b -> b.analyzer(indexAnalyzer)))))
                    .properties("tags", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("author_id", Property.of(p -> p.long_(LongNumberProperty.of(b -> b))))
                    .properties("author_avatar", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("author_nickname", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("author_tag_json", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("publish_time", Property.of(p -> p.date(DateProperty.of(b -> b))))
                    .properties("like_count", Property.of(p -> p.integer(IntegerNumberProperty.of(b -> b))))
                    .properties("favorite_count", Property.of(p -> p.integer(IntegerNumberProperty.of(b -> b))))
                    .properties("view_count", Property.of(p -> p.integer(IntegerNumberProperty.of(b -> b))))
                    .properties("status", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("img_urls", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("is_top", Property.of(p -> p.keyword(KeywordProperty.of(b -> b))))
                    .properties("title_suggest", Property.of(p -> p.completion(CompletionProperty.of(b -> b)))
                    )));
        } catch (Exception ignored) {
            // 忽略异常以保证应用启动；索引可能由后续写入动态创建，但 Mapping 将不完整
        }
    }
}
