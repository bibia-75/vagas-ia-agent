import os, secrets, csv, io
from datetime import datetime, timezone
from pathlib import Path
import httpx
from fastapi import FastAPI, Depends, HTTPException, status, UploadFile, File
from fastapi.responses import HTMLResponse, Response
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, String, Text, Integer, DateTime, LargeBinary, select, inspect
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from pypdf import PdfReader
from docx import Document
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from langdetect import detect, LangDetectException

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
    resume_mime: Mapped[str] = mapped_column(String(100), default="application/pdf")
    resume_pdf: Mapped[bytes | None] = mapped_column(LargeBinary, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda:datetime.now(timezone.utc))

class Job(Base):
    __tablename__ = "jobs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    url: Mapped[str] = mapped_column(String(1500), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(500), default="")
    company: Mapped[str] = mapped_column(String(300), default="")
    location: Mapped[str] = mapped_column(String(500), default="")
    source: Mapped[str] = mapped_column(String(100), default="")
    description: Mapped[str] = mapped_column(Text, default="")
    score: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(60), default="Encontrada")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda:datetime.now(timezone.utc))

Base.metadata.create_all(engine)
# Upgrade older SQLite deployments in place when the ephemeral database survives a redeploy.
if engine.dialect.name == "sqlite":
    existing_jobs = {col["name"] for col in inspect(engine).get_columns("jobs")}
    with engine.begin() as conn:
        if "description" not in existing_jobs:
            conn.exec_driver_sql("ALTER TABLE jobs ADD COLUMN description TEXT NOT NULL DEFAULT ''")
    existing = {col["name"] for col in inspect(engine).get_columns("profile")}
    with engine.begin() as conn:
        if "resume_text" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_text TEXT NOT NULL DEFAULT ''")
        if "resume_filename" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_filename VARCHAR(255) NOT NULL DEFAULT ''")
        if "resume_mime" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_mime VARCHAR(100) NOT NULL DEFAULT 'application/pdf'")
        if "resume_pdf" not in existing:
            conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN resume_pdf BLOB")
if engine.dialect.name == "postgresql":
    with engine.begin() as conn:
        conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN IF NOT EXISTS resume_pdf BYTEA")
        conn.exec_driver_sql("ALTER TABLE profile ADD COLUMN IF NOT EXISTS resume_mime VARCHAR(100) NOT NULL DEFAULT 'application/pdf'")

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

def is_portuguese_listing(title, description):
    """Strictly accept jobs whose description language is Portuguese."""
    sample = " ".join((description or "").split())
    if len(sample) < 80:
        return False
    try:
        return detect(sample[:12000]) == "pt"
    except LangDetectException:
        return False

def score_job(title, location, roles="", skills="", resume_text="", description=""):
    t=(title or "").lower(); loc=(location or "").lower()
    desc=(description or "").lower()
    if not is_portuguese_listing(title, description): return 0
    text=(t+" "+desc)
    # Exclude clear Spanish-bilingual roles, not every job mentioning Spanish in unrelated context.
    spanish_markers=["spanish","español","espanhol","língua espanhola","lingua espanhola"]
    bilingual_markers=["bilingual","bilingüe","bilíngue","fluent","fluency","native","advanced","required","proficiency","speaking","fluente","fluência","fluencia"]
    if any(x in t for x in ["bilingual (spanish)","bilingual spanish","spanish-speaking","spanish speaking","customer support specialist, bilingual"]): return 0
    if any(x in text for x in spanish_markers) and any(x in text for x in bilingual_markers): return 0
    english_required=["fluent in english","english fluency","fluency in english","native-level english","advanced english required","english is required","english required","professional english proficiency","inglês fluente","ingles fluente","fluência em inglês","fluencia en inglés"]
    if any(term in text for term in english_required): return 0
    if any(x in t for x in EXCLUDE): return 0
    role_tokens=[x.strip().lower() for x in (roles or "").split(";") if x.strip()]
    skill_tokens=[x.strip().lower() for x in (skills or "").split(";") if len(x.strip())>=4]
    relevant_terms=["marketplace","e-commerce","ecommerce","social media","customer support","customer service","virtual assistant","content","marketing assistant","assistente","atendimento","suporte","catalog","product listing","community manager","digital marketing","marketing coordinator","administrative assistant","customer experience","product catalog","e-commerce assistant","ecommerce assistant","marketplace analyst","marketplace assistant","seller support","operations assistant","sales support","customer success","support specialist","content creator","social media assistant","marketing assistant","product data","listing specialist"]
    cv=(resume_text or "").lower()
    cv_terms=["shopee","mercado livre","tiktok shop","shein","temu","amazon","marketplace","e-commerce","ecommerce","social media","instagram","tiktok","canva","excel","catalog","product listing","ads","anúncios","atendimento","customer support","customer service","content","marketing"]
    role_match=any(x in text for x in role_tokens)
    skill_match=any(x in text for x in skill_tokens)
    relevant_match=any(x in text for x in relevant_terms)
    cv_match=any(x in cv and x in text for x in cv_terms)
    if not (role_match or skill_match or relevant_match or cv_match): return 0
    score=15
    for token in role_tokens:
        if token in text: score=min(100,score+20)
    for token in skill_tokens:
        if token in text: score=min(100,score+8)
    for token in relevant_terms:
        if token in text: score=min(100,score+8)
    for token in cv_terms:
        if token in cv and token in text: score=min(100,score+5)
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
        p=db.get(Profile,1); p.resume_text=text[:60000]; p.resume_filename=file.filename[:255]; p.resume_mime="application/pdf"; p.resume_pdf=data; p.updated_at=datetime.now(timezone.utc); db.commit()
    return {"ok":True,"filename":file.filename,"characters_extracted":len(text),"message":"Currículo lido e salvo no banco configurado."}


class TailorRequest(BaseModel):
    job_id: int
    format: str = Field(default="docx", pattern="^(docx|txt)$")

def resume_sections(text):
    lines=[line.strip() for line in (text or "").replace("\\r","").splitlines() if line.strip()]
    headings={"experiência profissional","experiencia profissional","experiência","experiencia","formação acadêmica","formacao academica","educação","educacao","competências","competencias","habilidades","cursos","idiomas","resumo profissional","objetivo"}
    sections=[]; current="Resumo do currículo"; buf=[]
    for line in lines:
        norm=line.lower().strip(" :")
        if norm in headings:
            if buf: sections.append((current,buf)); buf=[]
            current=line
        else: buf.append(line)
    if buf: sections.append((current,buf))
    return sections

def tailor_resume_text(profile, job):
    original=(profile.resume_text or "").strip()
    if len(original)<100:
        raise HTTPException(400,"Envie primeiro seu currículo em PDF com texto selecionável.")
    title=job.title or "Vaga"
    description=(job.description or "")
    tokens=["marketplace","e-commerce","ecommerce","social media","instagram","tiktok","shopee","mercado livre","catalog","catálogo","anúncios","ads","atendimento","customer support","excel","canva","conteúdo","content","logística","estoque","produto","product listing","gestão","gestao"]
    original_lower=original.lower()
    desc_lower=description.lower()
    title_lower=title.lower()
    matched=[x for x in tokens if x in original_lower and (x in desc_lower or x in title_lower)]
    # Rearrange only existing, verifiable text. Do not fabricate achievements, skills, education, or languages.
    sections=resume_sections(original)
    ordered=[]
    for name,lines in sections:
        joined=" ".join(lines).lower()
        points=sum(1 for x in matched if x in joined)
        ordered.append((points,name,lines))
    ordered.sort(key=lambda x:x[0],reverse=True)
    out=[profile.full_name or "Currículo profissional",f"Versão direcionada: {title}",f"Empresa: {job.company or 'Não informada'}","", "Resumo de direcionamento",f"Esta versão reorganiza o conteúdo existente para destacar termos presentes no anúncio: {', '.join(matched[:12]) if matched else 'nenhum termo em comum identificado'}.",""]
    for _,name,lines in ordered:
        out.append(name)
        out.extend(lines)
        out.append("")
    out += ["Nota de integridade","Documento reorganizado a partir do currículo original. Revise o conteúdo antes de enviar; nenhuma experiência ou qualificação nova foi criada."]
    return "\n".join(out)

@app.post("/api/jobs/{job_id}/tailor")
def tailor_resume(job_id:int, user:str=Depends(require_auth), format:str="docx"):
    if format not in {"docx","pdf","txt"}: raise HTTPException(400,"Formato deve ser docx, pdf ou txt.")
    with Session() as db:
        job=db.get(Job,job_id); profile=db.get(Profile,1)
        if not job: raise HTTPException(404,"Vaga não encontrada")
        text=tailor_resume_text(profile,job)
    filename=f"curriculo_personalizado_vaga_{job_id}"
    if format=="txt":
        return Response(content=text,media_type="text/plain; charset=utf-8",headers={"Content-Disposition":f'attachment; filename="{filename}.txt"'})
    if format=="pdf":
        stream=io.BytesIO()
        styles=getSampleStyleSheet()
        styles.add(ParagraphStyle(name="CVName",parent=styles["Title"],fontName="Helvetica-Bold",fontSize=17,leading=21,textColor=colors.HexColor("#4C3933"),alignment=TA_CENTER,spaceAfter=8))
        styles.add(ParagraphStyle(name="CVHeading",parent=styles["Heading2"],fontName="Helvetica-Bold",fontSize=11,leading=14,textColor=colors.HexColor("#4C3933"),spaceBefore=8,spaceAfter=4))
        styles.add(ParagraphStyle(name="CVBody",parent=styles["BodyText"],fontName="Helvetica",fontSize=9,leading=12,spaceAfter=3))
        pdf=SimpleDocTemplate(stream,pagesize=A4,rightMargin=48,leftMargin=48,topMargin=42,bottomMargin=42,title=f"Currículo direcionado - {job.title}")
        story=[]
        heading_names={"resumo do currículo","experiência profissional","experiencia profissional","experiência","experiencia","formação acadêmica","formacao academica","educação","educacao","competências","competencias","habilidades","cursos","idiomas","resumo profissional","objetivo","nota de integridade"}
        for idx,line in enumerate(text.splitlines()):
            line=line.strip()
            if not line:
                story.append(Spacer(1,4)); continue
            safe=line.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
            if idx==0: story.append(Paragraph(safe,styles["CVName"]))
            elif line.lower().strip(" :") in heading_names: story.append(Paragraph(safe,styles["CVHeading"]))
            else: story.append(Paragraph(safe,styles["CVBody"]))
        pdf.build(story)
        return Response(content=stream.getvalue(),media_type="application/pdf",headers={"Content-Disposition":f'attachment; filename="{filename}.pdf"'})
    doc=Document()
    for line in text.splitlines():
        if line.strip() and line.strip().lower().strip(" :") in {"resumo do currículo","experiência profissional","experiencia profissional","experiência","experiencia","formação acadêmica","formacao academica","educação","educacao","competências","competencias","habilidades","cursos","idiomas","resumo profissional","objetivo","nota de integridade"}:
            doc.add_heading(line.strip(),level=2)
        elif line.strip():
            doc.add_paragraph(line.strip())
    stream=io.BytesIO(); doc.save(stream)
    return Response(content=stream.getvalue(),media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",headers={"Content-Disposition":f'attachment; filename="{filename}.docx"'})

@app.get("/api/jobs/{job_id}/analysis")
def analyze_job(job_id:int,user:str=Depends(require_auth)):
    with Session() as db:
        job=db.get(Job,job_id); profile=db.get(Profile,1)
        if not job: raise HTTPException(404,"Vaga não encontrada")
        cv=(profile.resume_text or "").lower(); desc=(job.description or "").lower(); title=(job.title or "").lower()
        skill_terms=["marketplace","e-commerce","ecommerce","social media","instagram","tiktok","shopee","mercado livre","catalog","catálogo","ads","anúncios","atendimento","customer support","excel","canva","content","conteúdo","estoque","logística","product listing","gestão","gestao"]
        present=[term for term in skill_terms if term in cv and (term in desc or term in title)]
        missing=[term for term in skill_terms if term in desc and term not in cv]
        lang_required=[term for term in ["fluent in spanish","spanish fluency","fluency in spanish","advanced spanish","spanish required","fluent in english","english fluency","advanced english required","english required","espanhol fluente","inglês fluente","ingles fluente"] if term in desc]
        return {"job_id":job.id,"title":job.title,"company":job.company,"score":job.score,"matched_terms":present,"possible_gaps":missing,"language_warnings":lang_required,"description_available":bool(job.description),"note":"Análise heurística baseada no texto disponível; requisitos ausentes no currículo não provam falta de competência."}

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
                found.append({"url":j.get("url"),"title":j.get("jobTitle") or "Vaga sem título","company":j.get("companyName") or "Empresa não informada","location":j.get("jobGeo") or "Remoto","source":"Jobicy","description":j.get("jobDescription") or j.get("jobExcerpt") or ""})
        except Exception as e: errors.append("Jobicy: "+str(e)[:120])
        try:
            r=await client.get("https://remotive.com/api/remote-jobs",params={"limit":limit}); r.raise_for_status()
            for j in r.json().get("jobs",[]):
                loc=j.get("candidate_required_location") or ""
                if any(x in loc.lower() for x in ["worldwide","anywhere","brazil","brasil","south america","latin america","all countries","global"]):
                    found.append({"url":j.get("url"),"title":j.get("title") or "Vaga sem título","company":j.get("company_name") or "Empresa não informada","location":loc or "Remoto","source":"Remotive","description":j.get("description") or ""})
        except Exception as e: errors.append("Remotive: "+str(e)[:120])
    inserted=0
    filtered_existing=0
    with Session() as db:
        p=db.get(Profile,1)
        # Re-score existing records too, so previously saved jobs that now fail filters disappear.
        for saved in db.scalars(select(Job)).all():
            new_score=score_job(saved.title,saved.location,p.target_roles,p.skills,p.resume_text,saved.description)
            if new_score <= 0 and saved.score > 0:
                saved.score=0
                filtered_existing += 1
            elif new_score > 0:
                saved.score=new_score
        for j in found:
            if not j.get("url"): continue
            score=score_job(j["title"],j["location"],p.target_roles,p.skills,p.resume_text,j.get("description",""))
            old=db.scalar(select(Job).where(Job.url==j["url"]))
            if score<=0:
                if old and old.score>0:
                    old.score=0
                    filtered_existing += 1
                continue
            old=db.scalar(select(Job).where(Job.url==j["url"]))
            if old:
                old.title=j["title"]; old.company=j["company"]; old.location=j["location"]; old.source=j["source"]; old.description=j.get("description",""); old.score=score
            else:
                db.add(Job(url=j["url"],title=j["title"],company=j["company"],location=j["location"],source=j["source"],description=j.get("description",""),score=score,status="Encontrada")); inserted+=1
        db.commit()
        total=db.scalar(select(Job).where(Job.score>0).with_only_columns(Job.id).order_by(None).subquery().select()) if False else len(db.scalars(select(Job.id).where(Job.score>0)).all())
    return {"new":inserted,"total":total,"checked":len(found),"filtered_existing":filtered_existing,"errors":errors}

@app.patch("/api/jobs/{job_id}")
def update_job(job_id:int,payload:StatusUpdate,user:str=Depends(require_auth)):
    allowed={"Encontrada","Prioritária","Pronta para candidatura","Candidatura em andamento","Candidatura confirmada","Entrevista","Recusada","Encerrada","Erro de envio"}
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
