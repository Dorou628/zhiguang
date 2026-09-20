package com.tongji.llm;

import com.tongji.common.exception.BusinessException;
import com.tongji.common.exception.ErrorCode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** External AI credentials are optional for starting the local community. */
@Component
public class ModelAvailability {
    @Value("${spring.ai.deepseek.api-key:}")
    private String chatKey;
    @Value("${spring.ai.openai.api-key:}")
    private String embeddingKey;

    private boolean configured(String key) {
        return key != null && !key.isBlank() && !"not-configured".equals(key);
    }

    public void requireChat() {
        if (!configured(chatKey)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "AI 功能未配置，请在 .env 中填写 DEEPSEEK_API_KEY 后重启");
        }
    }

    public boolean embeddingsConfigured() {
        return configured(embeddingKey);
    }

    public void requireRag() {
        requireChat();
        if (!embeddingsConfigured()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "RAG 未配置，请在 .env 中填写 OPENAI_API_KEY（DashScope 向量模型密钥）后重启");
        }
    }
}
