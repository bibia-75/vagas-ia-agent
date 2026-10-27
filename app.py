import os, secrets, sqlite3, re
from datetime import datetime, timezone
from pathlib import Path
import httpx
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel

app = FastAPI(title="Vagas IA")
security = HTTPBasic()
APP_USER = os.getenv("APP_USER", "")
APP_PASSWORD = os.getenv("APP_PASSWORD", "")
DB_PATH = os.getenv("DATABASE_PATH", "/tmp/vagas_ia.db")
BASE = Path(__file__).parent

TARGETS = [
    ("marketplace", 35), ("e-commerce", 35), ("ecommerce", 35),
    ("e commerce", 35), ("social media", 30), ("social media assistant", 30),
    ("social media manager", 30), ("community manager", 25), ("content creator", 25),
    ("content assistant", 25), ("virtual assistant", 25), ("administrative assistant", 15),
    ("customer support", 20), ("customer service", 20), ("customer experience", 15),
    ("marketing assistant", 25), ("digital marketing", 25), ("marketing coordinator", 20),
    ("product listing", 30), ("catalog", 15), ("e-commerce assistant", 35),
    ("assistente", 15), ("atendimento", 15), ("suporte", 15), ("conteúdo", 15),
    ("content", 10), ("marketing", 10), ("assistant", 8)
]
EXCLUDE = ["senior data analyst", "data analyst", "data scientist", "software engineer",
           "senior developer", "principal engineer", "salesforce developer", "account executive",
           "financial analyst", "accountant", "nurse", "medical doctor"]

def require_auth(credentials: HTTPBasicCredentials = Depends(security)):
    if not APP_USER or not APP_PASSWORD:
        raise HTTPException(status_code=503, detail="Configure APP_USER e APP_PASSWORD no Render.")
    ok = secrets.compare_digest(credentials.username, APP_USER) and secrets.compare_digest(credentials.password, APP_PASSWORD)
    if not ok:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Acesso não autorizado", headers={"WWW-Authenticate":"Basic"})
    return credentials.username

def db():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    con.execute("""CREATE TABLE IF NOT EXISTS jobs(
      id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT UNIQUE, title TEXT, company TEXT,
      location TEXT, source TEXT, score INTEGER, status TEXT DEFAULT 'Encontrada',
      created_at TEXT NOT NULL)""")
    con.commit()
    return con

def score_job(title, location):
    t = (title or "").lower()
    loc = (location or "").lower()
    if any(x in t for x in EXCLUDE):
        return 0
    score = 15
    for word, points in TARGETS:
        if word in t:
            score = min(100, score + points)
    if any(x in loc for x in ["brazil", "brasil", "latin america", "south america", "worldwide", "anywhere", "global", "all countries"]):
        score = min(100, score + 10)
    return min(score, 100)

class StatusUpdate(BaseModel):
    status: str

@app.get("/", response_class=HTMLResponse)
def home(user: str = Depends(require_auth)):
    return (BASE / "static" / "index.html").read_text(encoding="utf-8")

@app.get("/api/health")
def health():
    return {"ok": True, "service": "vagas-ia-agent"}

@app.get("/api/jobs")
def list_jobs(user: str = Depends(require_auth)):
    con = db()
    rows = con.execute("SELECT * FROM jobs WHERE score > 0 ORDER BY score DESC, id DESC").fetchall()
    con.close()
    return [dict(r) for r in rows]

@app.post("/api/search")
async def search_jobs(user: str = Depends(require_auth), limit: int = 50):
    limit = max(1, min(limit, 100))
    found, errors = [], []
    async with httpx.AsyncClient(timeout=20, follow_redirects=True, headers={"User-Agent":"VagasIA/1.0 job search assistant"}) as client:
        try:
            r = await client.get("https://jobicy.com/api/v2/remote-jobs", params={"count":limit, "geo":"brazil"})
            r.raise_for_status()
            for j in r.json().get("jobs", []):
                found.append({"url":j.get("url"),"title":j.get("jobTitle") or "Vaga sem título","company":j.get("companyName") or "Empresa não informada","location":j.get("jobGeo") or "Remoto","source":"Jobicy"})
        except Exception as e:
            errors.append("Jobicy: "+str(e)[:140])
        try:
            r = await client.get("https://remotive.com/api/remote-jobs", params={"limit":limit})
            r.raise_for_status()
            for j in r.json().get("jobs", []):
                loc = j.get("candidate_required_location") or ""
                # Do not treat every generic "remote" role as available in Brazil.
                if any(x in loc.lower() for x in ["worldwide","anywhere","brazil","brasil","south america","latin america","all countries","global"]):
                    found.append({"url":j.get("url"),"title":j.get("title") or "Vaga sem título","company":j.get("company_name") or "Empresa não informada","location":loc or "Remoto","source":"Remotive"})
        except Exception as e:
            errors.append("Remotive: "+str(e)[:140])
    con = db()
    inserted = 0
    for j in found:
        url = j.get("url")
        if not url: continue
        score = score_job(j["title"], j["location"])
        if score == 0: continue
        try:
            con.execute("INSERT INTO jobs(url,title,company,location,source,score,status,created_at) VALUES(?,?,?,?,?,?,?,?)",
                (url,j["title"],j["company"],j["location"],j["source"],score,"Encontrada",datetime.now(timezone.utc).isoformat()))
            inserted += 1
        except sqlite3.IntegrityError:
            con.execute("UPDATE jobs SET title=?,company=?,location=?,source=?,score=? WHERE url=?",
                (j["title"],j["company"],j["location"],j["source"],score,url))
    # Re-score existing records and keep low-fit roles out of the dashboard.
    rows = con.execute("SELECT id,title,location FROM jobs").fetchall()
    for row in rows:
        con.execute("UPDATE jobs SET score=? WHERE id=?", (score_job(row["title"],row["location"]),row["id"]))
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM jobs WHERE score>0").fetchone()[0]
    con.close()
    return {"new":inserted,"total":total,"checked":len(found),"errors":errors}

@app.patch("/api/jobs/{job_id}")
def update_job(job_id: int, payload: StatusUpdate, user: str = Depends(require_auth)):
    allowed = {"Encontrada","Prioritária","Pronta para candidatura","Candidatura confirmada","Entrevista","Recusada","Encerrada","Erro de envio"}
    if payload.status not in allowed:
        raise HTTPException(400, "Status inválido")
    con = db()
    cur = con.execute("UPDATE jobs SET status=? WHERE id=?", (payload.status,job_id))
    con.commit()
    con.close()
    if not cur.rowcount: raise HTTPException(404,"Vaga não encontrada")
    return {"ok":True}

@app.get("/api/stats")
def stats(user: str = Depends(require_auth)):
    con = db()
    total = con.execute("SELECT COUNT(*) FROM jobs WHERE score>0").fetchone()[0]
    priority = con.execute("SELECT COUNT(*) FROM jobs WHERE score>=50").fetchone()[0]
    applied = con.execute("SELECT COUNT(*) FROM jobs WHERE status='Candidatura confirmada'").fetchone()[0]
    con.close()
    return {"total":total,"priority":priority,"applied":applied}
