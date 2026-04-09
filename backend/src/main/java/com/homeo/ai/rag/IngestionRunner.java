package com.homeo.ai.rag;

import com.homeo.ai.medicine.MedicineEntity;
import com.homeo.ai.medicine.MedicineRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * Loads medicine_master.csv into the relational `medicine` table AND into
 * the pgvector store (one Document per medicine per field). Runs once, idempotent.
 */
@Component
public class IngestionRunner implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(IngestionRunner.class);
    private final MedicineRepository repo;
    private final VectorStore vectorStore;
    private final ResourceLoader resourceLoader;

    @Value("${app.ingest.enabled:true}")
    private boolean enabled;

    @Value("${app.ingest.csv:classpath:medicine_master.csv}")
    private String csvLocation;

    public IngestionRunner(MedicineRepository repo, VectorStore vectorStore, ResourceLoader rl) {
        this.repo = repo;
        this.vectorStore = vectorStore;
        this.resourceLoader = rl;
    }

    @Override
    public void run(String... args) throws Exception {
        if (!enabled || repo.count() > 0) {
            log.info("Ingestion skipped (enabled={}, existing rows={})", enabled, repo.count());
            return;
        }
        Resource r = resourceLoader.getResource(csvLocation);
        if (!r.exists()) { log.warn("CSV not found: {}", csvLocation); return; }

        List<Document> docs = new ArrayList<>();
        try (BufferedReader br = new BufferedReader(new InputStreamReader(r.getInputStream(), StandardCharsets.UTF_8))) {
            String headerLine = br.readLine();
            if (headerLine == null) return;
            String[] headers = splitCsv(headerLine);
            String line;
            while ((line = br.readLine()) != null) {
                String[] cols = splitCsv(line);
                Map<String,String> row = new HashMap<>();
                for (int i = 0; i < headers.length && i < cols.length; i++) row.put(headers[i], cols[i]);

                MedicineEntity m = new MedicineEntity();
                m.setCanonicalKey(row.getOrDefault("canonical_key", ""));
                if (m.getCanonicalKey().isBlank()) continue;
                m.setDisplayName(row.getOrDefault("display_name", m.getCanonicalKey()));
                m.setAllenName(row.get("allen_name"));
                m.setKentAbbrev(row.get("kent_abbrev"));
                m.setAllenDescription(row.get("allen_description"));
                m.setKentLectureDescription(row.get("kent_lecture_description"));
                m.setAggravation(row.get("aggravation"));
                m.setAmelioration(row.get("amelioration"));
                m.setRelationship(row.get("relationship"));
                try { m.setKentSymptomCount(Integer.parseInt(row.getOrDefault("kent_symptom_count", "0"))); }
                catch (NumberFormatException e) { m.setKentSymptomCount(0); }
                repo.save(m);

                addDoc(docs, m, "description", m.getAllenDescription());
                addDoc(docs, m, "aggravation", m.getAggravation());
                addDoc(docs, m, "amelioration", m.getAmelioration());
                addDoc(docs, m, "kent_lecture", truncate(m.getKentLectureDescription(), 2000));

                if (docs.size() >= 100) { vectorStore.add(docs); docs.clear(); }
            }
        }
        if (!docs.isEmpty()) vectorStore.add(docs);
        log.info("Ingestion complete. medicines={}", repo.count());
    }

    private void addDoc(List<Document> docs, MedicineEntity m, String field, String text) {
        if (text == null || text.isBlank()) return;
        Map<String,Object> meta = new HashMap<>();
        meta.put("canonical_key", m.getCanonicalKey());
        meta.put("display_name", m.getDisplayName());
        meta.put("field", field);
        docs.add(new Document(m.getDisplayName() + " — " + field + ": " + text, meta));
    }

    private static String truncate(String s, int n) { return s == null ? null : (s.length() <= n ? s : s.substring(0, n)); }

    // minimal CSV splitter respecting quoted fields
    private static String[] splitCsv(String line) {
        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean inQ = false;
        for (int i = 0; i < line.length(); i++) {
            char ch = line.charAt(i);
            if (ch == '"') {
                if (inQ && i + 1 < line.length() && line.charAt(i+1) == '"') { cur.append('"'); i++; }
                else inQ = !inQ;
            } else if (ch == ',' && !inQ) {
                out.add(cur.toString()); cur.setLength(0);
            } else cur.append(ch);
        }
        out.add(cur.toString());
        return out.toArray(new String[0]);
    }
}
