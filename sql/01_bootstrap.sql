-- Run once as a superuser on a fresh RDS Postgres 16 instance.
CREATE DATABASE homeo;
\c homeo
CREATE USER homeo_app WITH ENCRYPTED PASSWORD 'CHANGE_ME';
GRANT ALL PRIVILEGES ON DATABASE homeo TO homeo_app;
GRANT ALL ON SCHEMA public TO homeo_app;

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
