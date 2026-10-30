import os
import sqlite3
import sys

DB_PATH = "/tmp/vagas_ia.db"
try:
    os.remove(DB_PATH)
except FileNotFoundError:
    pass

conn = sqlite3.connect(DB_PATH)
conn.executescript("""
CREATE TABLE profile (
    id INTEGER PRIMARY KEY,
    full_name VARCHAR(120) NOT NULL DEFAULT '',
    target_roles VARCHAR(500) NOT NULL DEFAULT '',
    target_salary VARCHAR(100) NOT NULL DEFAULT '',
    locations VARCHAR(300) NOT NULL DEFAULT '',
    skills TEXT NOT NULL DEFAULT '',
    resume_text TEXT NOT NULL DEFAULT '',
    resume_filename VARCHAR(255) NOT NULL DEFAULT '',
    resume_mime VARCHAR(100) NOT NULL DEFAULT 'application/pdf',
    resume_pdf BLOB,
    email VARCHAR(255) NOT NULL DEFAULT '',
    phone VARCHAR(80) NOT NULL DEFAULT '',
    city VARCHAR(120) NOT NULL DEFAULT '',
    education VARCHAR(300) NOT NULL DEFAULT '',
    experience_summary TEXT NOT NULL DEFAULT '',
    linkedin_url VARCHAR(500) NOT NULL DEFAULT '',
    portfolio_url VARCHAR(500) NOT NULL DEFAULT '',
    contract_type VARCHAR(80) NOT NULL DEFAULT 'CLT ou PJ',
    english_level VARCHAR(80) NOT NULL DEFAULT 'Básico',
    application_policy VARCHAR(100) NOT NULL DEFAULT '',
    updated_at DATETIME
);
CREATE TABLE jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url VARCHAR(1500) NOT NULL,
    title VARCHAR(500) NOT NULL DEFAULT '',
    company VARCHAR(300) NOT NULL DEFAULT '',
    location VARCHAR(500) NOT NULL DEFAULT '',
    source VARCHAR(100) NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    salary VARCHAR(200) NOT NULL DEFAULT '',
    contract_type VARCHAR(120) NOT NULL DEFAULT '',
    score INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(60) NOT NULL DEFAULT 'Encontrada',
    created_at DATETIME
);
CREATE UNIQUE INDEX ix_jobs_url ON jobs(url);
CREATE TABLE saved_answers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_key VARCHAR(500) NOT NULL,
    question_text VARCHAR(1000) NOT NULL DEFAULT '',
    answer TEXT NOT NULL DEFAULT '',
    updated_at DATETIME
);
CREATE UNIQUE INDEX ix_saved_answers_question_key ON saved_answers(question_key);
INSERT INTO profile (id, full_name, target_salary, resume_text) VALUES (1, 'Perfil antigo preservado', 'A partir de R$ 3.500', 'Texto de currículo privado');
INSERT INTO jobs (url, title, company, location, source, description, score) VALUES ('https://example.test/old-job', 'Vaga antiga', 'Empresa antiga', 'Remoto', 'Teste', 'Descrição antiga', 88);
INSERT INTO saved_answers (question_key, question_text, answer) VALUES ('pergunta antiga', 'Pergunta antiga', 'Resposta antiga');
""")
conn.commit()
conn.close()

os.environ["APP_USER"] = "legacy-owner"
os.environ["APP_PASSWORD"] = "legacy-owner-password"
os.environ["APP_SECRET"] = "legacy-session-secret"
os.environ.pop("DATABASE_URL", None)

import app as service
from sqlalchemy import select
from fastapi.testclient import TestClient

with service.Session() as db:
    owner = db.scalar(select(service.User).where(service.User.username == "legacy-owner"))
    assert owner is not None
    profile = db.scalar(select(service.Profile).where(service.Profile.user_id == owner.id))
    job = db.scalar(select(service.Job).where(service.Job.user_id == owner.id))
    answer = db.scalar(select(service.SavedAnswer).where(service.SavedAnswer.user_id == owner.id))
    assert profile and profile.full_name == "Perfil antigo preservado"
    assert job and job.title == "Vaga antiga"
    assert answer and answer.answer == "Resposta antiga"

client = TestClient(service.app)
login = client.post("/api/auth/login", json={
    "identifier": "legacy-owner",
    "password": "legacy-owner-password"
})
assert login.status_code == 200, login.text
assert client.get("/api/profile").json()["full_name"] == "Perfil antigo preservado"
assert client.get("/api/jobs").json()[0]["title"] == "Vaga antiga"
assert client.get("/api/answers").json()[0]["answer"] == "Resposta antiga"
print("Legacy account migration preserved profile, job and saved answer.")
