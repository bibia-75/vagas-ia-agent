import os, secrets, sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
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
    rows = con.execute("SELECT * FROM jobs ORDER BY score DESC, id DESC").fetchall()
    con.close()
    return [dict(r) for r in rows]

@app.post("/api/search")
async def search_jobs(user: str = Depends(require_auth), limit: int = 30):
    limit = max(1, min(limit, 100))
    found = []
    errors = []
    async with httpx.AsyncClient(timeout=18, follow_redirects=True, headers={"User-Agent":"VagasIA/1.0 (job search assistant)"}) as client:
        # Jobicy public feed
        try:
            r = await client.get("https://jobicy.com/api/v2/remote-jobs", params={"count":limit, "geo":"brazil"})
            r.raise_for_status()
            for j in r.json().get("jobs", []):
                found.append({"url":j.get("url"),"title":j.get("jobTitle") or "Vaga sem título","company":j.get("companyName") or "Empresa não informada","location":j.get("jobGeo") or "Remoto","source":"Jobicy"})
        except Exception as e: errors.append("Jobicy: "+str(e)[:140])
        # Remotive public feed
        try:
            r = await client.get("https://remotive.com/api/remote-jobs", params={"limit":limit})
            r.raise_for_status()
            for j in r.json().get("jobs", []):
                loc = j.get("candidate_required_location") or "Remote"
                if any(x in loc.lower() for x in ["worldwide","anywhere","brazil","south america","latin america","all countries","remote"]):
                    found.append({"url":j.get("url"),"title":j.get("title") or "Vaga sem título","company":j.get("company_name") or "Empresa não informada","location":loc,"source":"Remotive"})
        except Exception as e: errors.append("Remotive: "+str(e)[:140])
    keywords = ["marketplace","e-commerce","ecommerce","social media","customer support","customer service","assistant","assistente","marketing","content","suporte","mídias sociais","mídias sociais"]
    con = db()
    inserted = 0
    for j in found:
        url = j.get("url")
        if not url: continue
        text = (j["title"]+" "+j["company"]+" "+j["location"]).lower()
        score = min(100, 35 + sum(12 for k in keywords if k in text))
        try:
            con.execute("INSERT INTO jobs(url,title,company,location,source,score,status,created_at) VALUES(?,?,?,?,?,?,?,?)",
                (url,j["title"],j["company"],j["location"],j["source"],score,"Encontrada",datetime.now(timezone.utc).isoformat()))
            inserted += 1
        except sqlite3.IntegrityError:
            pass
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]
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
    total = con.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]
    priority = con.execute("SELECT COUNT(*) FROM jobs WHERE score>=65").fetchone()[0]
    applied = con.execute("SELECT COUNT(*) FROM jobs WHERE status='Candidatura confirmada'").fetchone()[0]
    con.close()
    return {"total":total,"priority":priority,"applied":applied}
