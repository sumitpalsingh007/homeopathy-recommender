package com.homeo.ai.medicine;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

@Entity
@Table(name = "medicine")
@Getter
@Setter
public class MedicineEntity {
    @Id
    @Column(name = "canonical_key", length = 128)
    private String canonicalKey;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    @Column(name = "allen_name")    private String allenName;
    @Column(name = "kent_abbrev")   private String kentAbbrev;

    @Column(name = "allen_description", columnDefinition = "text")
    private String allenDescription;

    @Column(name = "kent_lecture_description", columnDefinition = "text")
    private String kentLectureDescription;

    @Column(name = "aggravation", columnDefinition = "text")
    private String aggravation;

    @Column(name = "amelioration", columnDefinition = "text")
    private String amelioration;

    @Column(name = "relationship", columnDefinition = "text")
    private String relationship;

    @Column(name = "kent_symptom_count")
    private Integer kentSymptomCount;
}
