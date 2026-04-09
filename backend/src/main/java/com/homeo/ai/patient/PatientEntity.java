package com.homeo.ai.patient;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "patient")
@Getter @Setter
public class PatientEntity {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    private String fullName;
    private Integer age;
    private String sex;

    @Column(columnDefinition = "text")
    private String personalityNotes;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
}
