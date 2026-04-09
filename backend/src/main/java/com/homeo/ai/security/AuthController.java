package com.homeo.ai.security;

import com.homeo.ai.patient.PatientEntity;
import com.homeo.ai.patient.PatientRepository;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final PatientRepository repo;
    private final PasswordEncoder encoder;
    private final JwtService jwt;

    public AuthController(PatientRepository repo, PasswordEncoder encoder, JwtService jwt) {
        this.repo = repo;
        this.encoder = encoder;
        this.jwt = jwt;
    }

    public record SignupReq(@Email String email, @NotBlank String password, String fullName, Integer age, String sex) {}
    public record LoginReq(@Email String email, @NotBlank String password) {}

    @PostMapping("/signup")
    public ResponseEntity<?> signup(@RequestBody SignupReq r) {
        if (repo.findByEmail(r.email()).isPresent())
            return ResponseEntity.badRequest().body(Map.of("error", "email exists"));
        PatientEntity p = new PatientEntity();
        p.setEmail(r.email());
        p.setPasswordHash(encoder.encode(r.password()));
        p.setFullName(r.fullName());
        p.setAge(r.age());
        p.setSex(r.sex());
        p.setCreatedAt(Instant.now());
        repo.save(p);
        return ResponseEntity.ok(Map.of("token", jwt.issue(p.getId(), p.getEmail())));
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginReq r) {
        var p = repo.findByEmail(r.email()).orElse(null);
        if (p == null || !encoder.matches(r.password(), p.getPasswordHash()))
            return ResponseEntity.status(401).body(Map.of("error", "invalid credentials"));
        return ResponseEntity.ok(Map.of("token", jwt.issue(p.getId(), p.getEmail())));
    }
}
