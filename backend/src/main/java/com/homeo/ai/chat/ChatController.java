package com.homeo.ai.chat;

import com.homeo.ai.agent.HomeoTools;
import com.homeo.ai.security.AuthUser;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.AbstractChatMemoryAdvisor;
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

    public ChatController(ChatClient chatClient, HomeoTools tools, ConsultationService consultationService) {
        this.chatClient = chatClient;
        this.tools = tools;
        this.consultationService = consultationService;
    }

    public record ChatRequest(@NotBlank String message, String sessionId) {}
    public record ChatResponse(String reply, String sessionId) {}

    @PostMapping
    public ChatResponse chat(@AuthenticationPrincipal AuthUser user, @RequestBody ChatRequest req) {
        String sessionId = req.sessionId() == null ? java.util.UUID.randomUUID().toString() : req.sessionId();
        String reply = chatClient.prompt()
                .user(req.message())
                .tools(tools)
                .advisors(a -> a
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_CONVERSATION_ID_KEY, sessionId)
                        .param(AbstractChatMemoryAdvisor.CHAT_MEMORY_RETRIEVE_SIZE_KEY, 20))
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
                .advisors(a -> a.param(AbstractChatMemoryAdvisor.CHAT_MEMORY_CONVERSATION_ID_KEY, sessionId))
                .stream()
                .content();
    }
}
