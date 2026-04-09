-- Bulk load from the CSVs produced by the scraper pipeline.
-- Run from psql on the server: \i 03_load_csv.sql
\copy medicine(canonical_key, display_name, allen_name, kent_abbrev, allen_description, kent_lecture_description, aggravation, amelioration, relationship, kent_symptom_count) FROM '/tmp/medicine_master.csv' WITH (FORMAT csv, HEADER true);

\copy kent_rubric(chapter, rubric_path, rubric_text, medicine_abbrev, grade) FROM '/tmp/kent_repertory_rubrics.csv' WITH (FORMAT csv, HEADER true);
