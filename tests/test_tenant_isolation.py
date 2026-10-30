import unittest
from fastapi.testclient import TestClient
from sqlalchemy import select

import app as service


class TenantIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ann = TestClient(service.app)
        cls.caio = TestClient(service.app)

        response = cls.ann.post("/api/auth/register", json={
            "username": "annynha-ci",
            "email": "annynha-ci@example.test",
            "password": "senha-segura-annynha"
        })
        if response.status_code not in (200, 409):
            raise AssertionError(response.text)
        if response.status_code == 409:
            cls.ann.post("/api/auth/login", json={
                "identifier": "annynha-ci",
                "password": "senha-segura-annynha"
            })

        response = cls.caio.post("/api/auth/register", json={
            "username": "caio-ci",
            "email": "caio-ci@example.test",
            "password": "senha-segura-caio"
        })
        if response.status_code not in (200, 409):
            raise AssertionError(response.text)
        if response.status_code == 409:
            cls.caio.post("/api/auth/login", json={
                "identifier": "caio-ci",
                "password": "senha-segura-caio"
            })

    def test_profiles_and_answers_are_private(self):
        saved = self.ann.put("/api/profile", json={
            "full_name": "Perfil da Anny",
            "target_roles": "Marketplace",
            "target_salary": "A partir de R$ 3.500",
            "locations": "Remoto; híbrido",
            "skills": "Shopee; Excel",
            "email": "anny@example.test",
            "phone": "000000000",
            "city": "Goiânia",
            "education": "Engenharia de Software",
            "experience_summary": "Experiência privada",
            "linkedin_url": "",
            "portfolio_url": "",
            "contract_type": "CLT",
            "english_level": "Básico",
            "application_policy": "Manual"
        })
        self.assertEqual(saved.status_code, 200)

        answer = self.ann.post("/api/answers", json={
            "question": "Qual sua experiência?",
            "answer": "Resposta privada da conta Anny."
        })
        self.assertEqual(answer.status_code, 200)

        caio_profile = self.caio.get("/api/profile").json()
        self.assertNotEqual(caio_profile.get("full_name"), "Perfil da Anny")
        self.assertNotEqual(caio_profile.get("target_salary"), "A partir de R$ 3.500")
        self.assertEqual(self.caio.get("/api/answers").json(), [])

    def test_job_records_are_private(self):
        with service.Session() as db:
            ann_user = db.scalar(select(service.User).where(service.User.username == "annynha-ci"))
            job = service.Job(
                user_id=ann_user.id,
                url="https://example.test/private-job",
                title="Vaga privada de teste",
                company="Empresa teste",
                location="Remoto",
                source="Teste",
                score=90
            )
            db.add(job)
            db.commit()
            job_id = job.id

        with service.Session() as db:
            caio_user = db.scalar(select(service.User).where(service.User.username == "caio-ci"))
            db.add(service.Job(
                user_id=caio_user.id,
                url="https://example.test/private-job",
                title="Mesma vaga salva pela outra conta",
                company="Outra conta",
                location="Remoto",
                source="Teste",
                score=75
            ))
            db.commit()

        self.assertEqual(self.ann.get("/api/jobs").status_code, 200)
        ann_jobs = self.ann.get("/api/jobs").json()
        caio_jobs = self.caio.get("/api/jobs").json()
        self.assertTrue(any(x["id"] == job_id and x["title"] == "Vaga privada de teste" for x in ann_jobs))
        self.assertFalse(any(x["id"] == job_id for x in caio_jobs))
        self.assertTrue(any(x["title"] == "Mesma vaga salva pela outra conta" for x in caio_jobs))
        self.assertEqual(self.caio.get(f"/api/jobs/{job_id}/analysis").status_code, 404)
        self.assertEqual(self.caio.patch(f"/api/jobs/{job_id}", json={"status": "Prioritária"}).status_code, 404)


if __name__ == "__main__":
    unittest.main()
