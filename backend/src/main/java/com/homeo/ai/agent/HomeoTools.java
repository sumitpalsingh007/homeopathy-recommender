package com.homeo.ai.agent;

import com.homeo.ai.medicine.MedicineRepository;
import com.homeo.ai.medicine.MedicineEntity;
import com.homeo.ai.patient.ConsultationRepository;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.stream.Collectors;

/**
 * Tools exposed to the agent via Spring AI @Tool annotation.
 * The LLM can decide to call these mid-conversation.
 */
@Component
public class HomeoTools {

    private final MedicineRepository medicineRepo;
    private final ConsultationRepository consultationRepo;

    public HomeoTools(MedicineRepository medicineRepo, ConsultationRepository consultationRepo) {
        this.medicineRepo = medicineRepo;
        this.consultationRepo = consultationRepo;
    }

    @Tool(description = "Search the medicine master table by canonical name or symptom keyword. " +
            "Returns up to 10 medicines with their key modalities.")
    public List<MedicineSummary> searchMedicines(
            @ToolParam(description = "keyword, symptom or medicine name fragment") String query) {
        return medicineRepo.searchByKeyword(query, 10).stream()
                .map(MedicineSummary::from)
                .toList();
    }

    @Tool(description = "Fetch a specific medicine's full materia medica description by canonical name.")
    public MedicineDetail getMedicine(
            @ToolParam(description = "canonical medicine name, e.g. 'pulsatilla'") String canonicalName) {
        MedicineEntity m = medicineRepo.findByCanonicalKey(canonicalName.toLowerCase()).orElse(null);
        return m == null ? null : MedicineDetail.from(m);
    }

    @Tool(description = "Retrieve the patient's prior consultation summaries for context and continuity.")
    public List<String> getPatientHistory(
            @ToolParam(description = "patient user id") Long patientId) {
        return consultationRepo.findTop10ByPatientIdOrderByCreatedAtDesc(patientId).stream()
                .map(c -> "[" + c.getCreatedAt() + "] " + c.getSummary())
                .collect(Collectors.toList());
    }

    public record MedicineSummary(String canonicalKey, String displayName, String keynotes) {
        static MedicineSummary from(MedicineEntity m) {
            return new MedicineSummary(m.getCanonicalKey(), m.getDisplayName(),
                    truncate(m.getAllenDescription(), 240));
        }
    }

    public record MedicineDetail(String canonicalKey, String displayName,
                                 String allenDescription, String kentLecture,
                                 String aggravation, String amelioration) {
        static MedicineDetail from(MedicineEntity m) {
            return new MedicineDetail(m.getCanonicalKey(), m.getDisplayName(),
                    m.getAllenDescription(), truncate(m.getKentLectureDescription(), 4000),
                    m.getAggravation(), m.getAmelioration());
        }
    }

    private static String truncate(String s, int n) {
        if (s == null) return null;
        return s.length() <= n ? s : s.substring(0, n) + "...";
    }
}
