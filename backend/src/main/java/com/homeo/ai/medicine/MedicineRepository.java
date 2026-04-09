package com.homeo.ai.medicine;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface MedicineRepository extends JpaRepository<MedicineEntity, String> {

    Optional<MedicineEntity> findByCanonicalKey(String canonicalKey);

    @Query(value = """
        SELECT * FROM medicine
        WHERE canonical_key ILIKE '%' || :q || '%'
           OR display_name  ILIKE '%' || :q || '%'
           OR allen_description ILIKE '%' || :q || '%'
           OR kent_lecture_description ILIKE '%' || :q || '%'
        LIMIT :lim
        """, nativeQuery = true)
    List<MedicineEntity> searchByKeyword(@Param("q") String q, @Param("lim") int limit);
}
