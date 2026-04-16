package com.homeo.ai.chat;

import com.homeo.ai.agent.HomeoTools;
import com.homeo.ai.security.AuthUser;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.http.MediaType;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

import jakarta.validation.constraints.NotBlank;

@RestController
@RequestMapping("/api/chat")
public class ChatController {

    private final ChatClient chatClient;
    private final HomeoTools tools;
    private final ConsultationService consultationService;
    private final ChatMemory chatMemory;

    public ChatController(ChatClient chatClient, HomeoTools tools,
                          ConsultationService consultationService, ChatMemory chatMemory) {
        this.chatClient = chatClient;
        this.tools = tools;
        this.consultationService = consultationService;
        this.chatMemory = chatMemory;
    }

    public record ChatRequest(@NotBlank String message, String sessionId) {}
    public record ChatResponse(String reply, String sessionId) {}

    @PostMapping
    public ChatResponse chat(@AuthenticationPrincipal AuthUser user, @RequestBody ChatRequest req) {
        String sessionId = req.sessionId() == null ? java.util.UUID.randomUUID().toString() : req.sessionId();
        String reply = chatClient.prompt()
                .user(req.message())
                .tools(tools)
                .advisors(MessageChatMemoryAdvisor.builder(chatMemory).conversationId(sessionId).build())
                .call()
                .content();
        consultationService.appendTurn(user.getId(), sessionId, req.message(), reply);
        return new ChatResponse(reply, sessionId);
    }

    @PostMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<String> stream(@AuthenticationPrincipal AuthUser user, @RequestBody ChatRequest req) {
        String sessionId = req.sessionId() == null ? java.util.UUID.randomUUID().toString() : req.sessionId();
        return chatClient.prompt()
                .user(req.message())
                .tools(tools)
                .advisors(MessageChatMemoryAdvisor.builder(chatMemory).conversationId(sessionId).build())
                .stream()
                .content();
    }
}
