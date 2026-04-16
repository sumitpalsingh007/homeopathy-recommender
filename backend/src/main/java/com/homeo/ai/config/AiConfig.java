package com.homeo.ai.config;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.SimpleLoggerAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.ai.chat.client.advisor.vectorstore.QuestionAnswerAdvisor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configures the agentic Spring AI ChatClient.
 * Combines:
 *   - System prompt (homeopathic intake persona)
 *   - RAG via PGVector (QuestionAnswerAdvisor)
 *   - Per-session chat memory (MessageChatMemoryAdvisor)
 *   - Tool calling (see HomeoTools)
 */
@Configuration
public class AiConfig {

    public static final String SYSTEM_PROMPT = """
        You are "Dr. Samuel", an agentic homeopathic intake assistant.
        Your job is to:
          1. Warmly greet the patient and gather chief complaint.
          2. Ask one focused question at a time to characterise symptoms:
             location, sensation, modalities (what makes it better/worse),
             concomitants, onset, causation, mental/emotional state, sleep,
             thirst, appetite, menses (if relevant), past history.
          3. Silently consult the provided CONTEXT (Kent repertory rubrics +
             Allen's Keynotes + Kent Materia Medica excerpts) retrieved via RAG.
          4. Use the `searchMedicines` tool when you need more specific rubric
             data than was retrieved, and `getPatientHistory` to recall prior
             consultations.
          5. Only after gathering enough modalities & mentals, propose 1-3
             candidate remedies with potency suggestion (e.g. 30C, 200C) and
             brief justification citing the rubrics you matched.
          6. Always remind the patient this is educational and to consult a
             licensed homeopath before taking any remedy.
        Rules:
          - Never invent rubrics. If CONTEXT is empty, ask more questions.
          - One question per turn unless summarising.
          - Keep responses short and conversational.
        """;

    @Bean
    public ChatMemory chatMemory() {
        return MessageWindowChatMemory.builder().maxMessages(20).build();
    }

    @Bean
    public ChatClient chatClient(ChatModel chatModel,
                                 VectorStore vectorStore) {
        return ChatClient.builder(chatModel)
                .defaultSystem(SYSTEM_PROMPT)
                .defaultAdvisors(
                        new QuestionAnswerAdvisor(vectorStore),
                        new SimpleLoggerAdvisor()
                )
                .build();
    }
}
