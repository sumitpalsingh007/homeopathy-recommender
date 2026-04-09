package com.homeo.ai.patient;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface ConsultationRepository extends JpaRepository<ConsultationEntity, Long> {
    Optional<ConsultationEntity> findBySessionId(String sessionId);
    List<ConsultationEntity> findTop10ByPatientIdOrderByCreatedAtDesc(Long patientId);
}
