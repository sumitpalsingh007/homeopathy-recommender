package com.homeo.ai.chat;

import com.homeo.ai.patient.ConsultationEntity;
import com.homeo.ai.patient.ConsultationRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class ConsultationService {
    private final ConsultationRepository repo;

    public ConsultationService(ConsultationRepository repo) {
        this.repo = repo;
    }

    @Transactional
    public void appendTurn(Long patientId, String sessionId, String userMsg, String aiReply) {
        ConsultationEntity c = repo.findBySessionId(sessionId).orElseGet(() -> {
            ConsultationEntity n = new ConsultationEntity();
            n.setPatientId(patientId);
            n.setSessionId(sessionId);
            n.setCreatedAt(Instant.now());
            n.setSummary("");
            return n;
        });
        String turn = "\nPatient: " + userMsg + "\nDr. Samuel: " + aiReply;
        c.setSummary((c.getSummary() == null ? "" : c.getSummary()) + turn);
        c.setUpdatedAt(Instant.now());
        repo.save(c);
    }
}
