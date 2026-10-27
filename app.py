import os, secrets, csv, io
from datetime import datetime, timezone
from pathlib import Path
import httpx
from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File
from fastapi.responses import HTMLResponse, Response
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, String, Text, Integer, DateTime, select, inspect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from pypdf import PdfReader

app = FastAPI(title="Vagas IA")
security = HTTPBasic()
APP_USER = os.getenv("APP_USER", "")
APP_PASSWORD = os.getenv("APP_PASSWORD", "")
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql+psycopg://", 1)
elif DATABASE_URL.startswith("postgresql://"):
    DATABASE_URL = DATABASE_URL.replace("postgresql://", "postgresql+psycopg://", 1)
if DATABASE_URL:
    engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args={"sslmode":"require"})
else:
    engine = create_engine("sqlite:////tmp/vagas_ia.db", connect_args={"check_same_thread":False})
Session = sessionmaker(bind=engine, expire_on_commit=False)
BASE = Path(__file__).parent

class Base(DeclarativeBase): pass

class Profile(Base):
    __tablename__ = "profile"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    full_name: Mapped[str] = mapped_column(String(120), default="")
    target_roles: Mapped[str] = mapped_column(String(500), default="Marketplace; E-commerce; Social Media; Customer Support; Assistente Virtual")
    target_salary: Mapped[str] = mapped_column(String(100), default="R$ 2.500+")
    locations: Mapped[str] = mapped_column(String(300), default="Remoto; Brasil")
    skills: Mapped[str] = mapped_column(Text, default="Shopee; Mercado Livre; TikTok Shop; SHEIN; Temu; Amazon; anúncios; catálogo; Instagram; TikTok; Canva; Excel; atendimento")
    resume_text: Mapped[str] = mapped_column(Text, default="")
    resume_filename: Mapped[str] = mapped_column(String(255), default="")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda:datetime.now(timezone.utc))

class Job(Base):
    __tablename__ = "jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    url: Mapped[str] = mapped_column(String(1500), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(500), default="")
    company: Mapped[str] = mapped_column(String(300), default="")
    location: Mapped[str] = mapped_column(String(500), default="")
    source: Mapped[str] = mapped_column(String(100), default="")
    score: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(60), default="Encontrada")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda:datetime.now(timezone.utc))

Base.metadata.create_all(engine)
# Upgrade older SQLite deployments in place when the ephemeral database survives a redeploy.
if engine.dialect.name == "sqlite":
    existing = {col["name"] for col in inspect(engine).get_columns("profile")}
    with engine.begin() as conn:
        if "resume_text" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_text TEXT NOT NULL DEFAULT ''")
        if "resume_filename" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_filename VARCHAR(255) NOT NULL DEFAULT ''")
with Session() as db:
    if db.get(Profile, 1) is None:
        db.add(Profile(id=1))
        db.commit()

def require_auth(credentials: HTTPBasicCredentials = Depends(security)):
    if not APP_USER or not APP_PASSWORD:
        raise HTTPException(status_code=503, detail="Configure APP_USER e APP_PASSWORD no Render.")
    ok = secrets.compare_digest(credentials.username, APP_USER) and secrets.compare_digest(credentials.password, APP_PASSWORD)
    if not ok:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Acesso não autorizado", headers={"WWW-Authenticate":"Basic"})
    return credentials.username

def profile_dict(p):
    return {"full_name":p.full_name,"target_roles":p.target_roles,"target_salary":p.target_salary,"locations":p.locations,"skills":p.skills,"resume_filename":p.resume_filename,"resume_text_length":len(p.resume_text or ""),"updated_at":p.updated_at.isoformat() if p.updated_at else None}

EXCLUDE = ["senior data analyst","data analyst","data scientist","software engineer","senior developer","principal engineer","account executive","financial analyst","accountant","nurse","medical doctor"]
def score_job(title, location, roles="", skills="", resume_text=""):
    t=(title or "").lower(); loc=(location or "").lower()
    if any(x in t for x in EXCLUDE): return 0
    score=15
    for token in [x.strip().lower() for x in (roles or "").split(";") if x.strip()]:
        if token in t: score=min(100,score+20)
    for token in [x.strip().lower() for x in (skills or "").split(";") if len(x.strip())>=4]:
        if token in t: score=min(100,score+8)
    for token in ["marketplace","e-commerce","ecommerce","social media","customer support","customer service","virtual assistant","content","marketing assistant","assistente","atendimento","suporte","catalog","product listing"]:
        if token in t: score=min(100,score+12)
    if any(x in loc for x in ["brazil","brasil","latin america","south america","worldwide","anywhere","global","all countries"]): score=min(100,score+10)
    return min(100,score)

class StatusUpdate(BaseModel):
    status: str
class ProfileUpdate(BaseModel):
    full_name: str = Field(default="", max_length=120)
    target_roles: str = Field(default="", max_length=500)
    target_salary: str = Field(default="R$ 2.500+", max_length=100)
    locations: str = Field(default="Remoto; Brasil", max_length=300)
    skills: str = Field(default="", max_length=4000)

@app.get("/", response_class=HTMLResponse)
def home(user: str = Depends(require_auth)):
    return (BASE / "static" / "index.html").read_text(encoding="utf-8")

@app.get("/api/health")
def health():
    return {"ok":True,"service":"vagas-ia-agent","persistent_database":bool(DATABASE_URL)}

@app.get("/api/profile")
def get_profile(user: str = Depends(require_auth)):
    with Session() as db: return profile_dict(db.get(Profile,1))

@app.put("/api/profile")
def save_profile(payload: ProfileUpdate, user: str = Depends(require_auth)):
    with Session() as db:
        p=db.get(Profile,1)
        for key,value in payload.model_dump().items(): setattr(p,key,value.strip())
        p.updated_at=datetime.now(timezone.utc); db.commit()
        return {"ok":True,"message":"Perfil salvo"}

@app.post("/api/profile/resume")
async def upload_resume(file: UploadFile = File(...), user: str = Depends(require_auth)):
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400,"Envie seu currículo em PDF.")
    data=await file.read()
    if len(data)>8*1024*1024: raise HTTPException(413,"O PDF deve ter até 8 MB.")
    try:
        reader=PdfReader(io.BytesIO(data))
        text="\n".join(page.extract_text() or "" for page in reader.pages).strip()
    except Exception: raise HTTPException(400,"Não consegui ler esse PDF. Tente exportar o currículo novamente em PDF.")
    if not text: raise HTTPException(400,"O PDF parece ser uma imagem sem texto selecionável. Envie um PDF com texto.")
    with Session() as db:
        p=db.get(Profile,1); p.resume_text=text[:60000]; p.resume_filename=file.filename[:255]; p.updated_at=datetime.now(timezone.utc); db.commit()
    return {"ok":True,"filename":file.filename,"characters_extracted":len(text),"message":"Currículo lido e salvo no banco configurado."}

@app.get("/api/jobs")
def list_jobs(user: str = Depends(require_auth)):
    with Session() as db:
        jobs=db.scalars(select(Job).where(Job.score>0).order_by(Job.score.desc(),Job.id.desc())).all()
        return [dict(id=j.id,url=j.url,title=j.title,company=j.company,location=j.location,source=j.source,score=j.score,status=j.status,created_at=j.created_at.isoformat()) for j in jobs]

@app.post("/api/search")
async def search_jobs(user: str = Depends(require_auth), limit: int = 50):
    limit=max(1,min(limit,100)); found=[]; errors=[]
    async with httpx.AsyncClient(timeout=20,follow_redirects=True,headers={"User-Agent":"VagasIA/1.0 job search assistant"}) as client:
        try:
            r=await client.get("https://jobicy.com/api/v2/remote-jobs",params={"count":limit,"geo":"brazil"}); r.raise_for_status()
            for j in r.json().get("jobs",[]):
                found.append({"url":j.get("url"),"title":j.get("jobTitle") or "Vaga sem título","company":j.get("companyName") or "Empresa não informada","location":j.get("jobGeo") or "Remoto","source":"Jobicy"})
        except Exception as e: errors.append("Jobicy: "+str(e)[:120])
        try:
            r=await client.get("https://remotive.com/api/remote-jobs",params={"limit":limit}); r.raise_for_status()
            for j in r.json().get("jobs",[]):
                loc=j.get("candidate_required_location") or ""
                if any(x in loc.lower() for x in ["worldwide","anywhere","brazil","brasil","south america","latin america","all countries","global"]):
                    found.append({"url":j.get("url"),"title":j.get("title") or "Vaga sem título","company":j.get("company_name") or "Empresa não informada","location":loc or "Remoto","source":"Remotive"})
        except Exception as e: errors.append("Remotive: "+str(e)[:120])
    inserted=0
    with Session() as db:
        p=db.get(Profile,1)
        for j in found:
            if not j.get("url"): continue
            score=score_job(j["title"],j["location"],p.target_roles,p.skills,p.resume_text)
            if score<=0: continue
            old=db.scalar(select(Job).where(Job.url==j["url"]))
            if old:
                old.title=j["title"]; old.company=j["company"]; old.location=j["location"]; old.source=j["source"]; old.score=score
            else:
                db.add(Job(url=j["url"],title=j["title"],company=j["company"],location=j["location"],source=j["source"],score=score,status="Encontrada")); inserted+=1
        db.commit()
        total=db.scalar(select(Job).where(Job.score>0).with_only_columns(Job.id).order_by(None).subquery().select()) if False else len(db.scalars(select(Job.id).where(Job.score>0)).all())
    return {"new":inserted,"total":total,"checked":len(found),"errors":errors}

@app.patch("/api/jobs/{job_id}")
def update_job(job_id:int,payload:StatusUpdate,user:str=Depends(require_auth)):
    allowed={"Encontrada","Prioritária","Pronta para candidatura","Candidatura confirmada","Entrevista","Recusada","Encerrada","Erro de envio"}
    if payload.status not in allowed: raise HTTPException(400,"Status inválido")
    with Session() as db:
        j=db.get(Job,job_id)
        if not j: raise HTTPException(404,"Vaga não encontrada")
        j.status=payload.status; db.commit()
    return {"ok":True}

@app.get("/api/stats")
def stats(user:str=Depends(require_auth)):
    with Session() as db:
        jobs=db.scalars(select(Job)).all()
        return {"total":sum(1 for j in jobs if j.score>0),"priority":sum(1 for j in jobs if j.score>=50),"applied":sum(1 for j in jobs if j.status=="Candidatura confirmada")}

@app.get("/api/export.csv")
def export_csv(user:str=Depends(require_auth)):
    output=io.StringIO(); writer=csv.writer(output)
    writer.writerow(["Vaga","Empresa","Localização","Fonte","Link","Compatibilidade","Status","Encontrada em"])
    with Session() as db:
        for j in db.scalars(select(Job).order_by(Job.score.desc())).all():
            writer.writerow([j.title,j.company,j.location,j.source,j.url,j.score,j.status,j.created_at.isoformat() if j.created_at else ""])
    return Response(content="\ufeff"+output.getvalue(),media_type="text/csv; charset=utf-8",headers={"Content-Disposition":"attachment; filename=vagas_ia.csv"})
