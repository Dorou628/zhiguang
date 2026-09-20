package com.tongji.llm;

import com.tongji.common.exception.BusinessException;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class ModelAvailabilityTest {
    @Test
    void anUnconfiguredContainerRejectsAiWithoutCallingAnExternalProvider() {
        ModelAvailability availability = new ModelAvailability();
        ReflectionTestUtils.setField(availability, "chatKey", "not-configured");
        ReflectionTestUtils.setField(availability, "embeddingKey", "");
        assertThatThrownBy(availability::requireChat).isInstanceOf(BusinessException.class)
                .hasMessageContaining("DEEPSEEK_API_KEY");
        assertThat(availability.embeddingsConfigured()).isFalse();
    }

    @Test
    void ragRequiresBothProvidersButSummariesOnlyRequireChat() {
        ModelAvailability availability = new ModelAvailability();
        ReflectionTestUtils.setField(availability, "chatKey", "test-provider-configuration");
        ReflectionTestUtils.setField(availability, "embeddingKey", "not-configured");
        assertThatCode(availability::requireChat).doesNotThrowAnyException();
        assertThatThrownBy(availability::requireRag).isInstanceOf(BusinessException.class)
                .hasMessageContaining("OPENAI_API_KEY");
        ReflectionTestUtils.setField(availability, "embeddingKey", "test-embedding-configuration");
        assertThatCode(availability::requireRag).doesNotThrowAnyException();
    }
}
