# Vagas IA

Painel privado para buscar vagas remotas, pontuar compatibilidade, guardar status e exportar histórico.

## O que está implementado
- Cadastro e login por usuário, com senha armazenada por hash e sessão protegida por cookie HttpOnly.
- Dados isolados por conta: perfil, currículo, vagas, status, respostas salvas e exportações são consultados pelo identificador do usuário autenticado.
- Migração da conta antiga: APP_USER e APP_PASSWORD identificam o proprietário dos dados existentes; a busca agendada do GitHub Actions continua autorizada apenas no endpoint de busca.
- Configure APP_SECRET no Render com um valor aleatório longo para assinar sessões. Mantenha DATABASE_URL apontando para PostgreSQL persistente.
- Busca sob demanda em feeds públicos Jobicy e Remotive; cobertura e resultados dependem dessas fontes.
- Deduplicação por URL e pontuação aproximada por cargo, competências e texto extraído do currículo.
- O salário mínimo é uma preferência configurável no perfil (R$ 3.500 no perfil inicial desta instalação): anúncios com faixa salarial mensal explicitamente em reais e totalmente abaixo do limite informado são filtrados; salários não divulgados permanecem visíveis para conferência. Não há conversão de moedas nem comparação de faixas anuais/por hora com salário mensal.
- Vagas remotas e híbridas são aceitas; anúncios explicitamente presenciais e restrições geográficas claramente incompatíveis são descartados. Quando a fonte não deixa claro se aceita profissionais no Brasil, o painel exibe um aviso para conferência manual.
- Salário e vínculo informados pela fonte são exibidos nos resultados e exportados no CSV.
- Perfil profissional editável, preferências de candidatura (modalidade remota/híbrida, localidade, salário mínimo configurável, vínculo e inglês) e upload de currículo PDF com texto selecionável (até 8 MB).
- Onboarding com checklist de informações básicas pendentes.
- Respostas livres salvas por pergunta normalizada para reutilização futura quando a pergunta for equivalente.
- Controle manual de status das vagas e exportação CSV.
- Workflow agendado pelo GitHub Actions, uma vez por hora entre 08:00 e 17:00 de Brasília, todos os dias, após configurar os secrets.

## Publicação no Render
- Build: `pip install -r requirements.txt`
- Start: `uvicorn app:app --host 0.0.0.0 --port $PORT`
- Health: `/api/health`

## Configurar busca programada
No GitHub, abra Settings → Secrets and variables → Actions → New repository secret e crie:
- `VAGAS_APP_USER`: o mesmo valor configurado em Render como `APP_USER`
- `VAGAS_APP_PASSWORD`: o mesmo valor configurado em Render como `APP_PASSWORD`
- `VAGAS_SERVICE_URL`: `https://vagas-ia-agent.onrender.com`

Depois, abra Actions → “Vagas IA - busca programada” e execute Run workflow para testar. O workflow roda automaticamente entre 08h e 17h (horário de Brasília), todos os dias. O serviço gratuito do Render pode dormir; a primeira requisição pode demorar.

## Persistência: obrigatório antes de confiar nos dados
Por padrão, sem `DATABASE_URL`, o app usa SQLite em `/tmp/vagas_ia.db`, que é temporário no Render Free. Para manter perfil, currículo e histórico após reinicializações, crie um banco PostgreSQL gerenciado e defina a variável `DATABASE_URL` no Render com a URL de conexão fornecida pelo provedor. A aplicação aceita URLs `postgresql://` e `postgres://` e usa TLS. O `render.yaml` declara `DATABASE_URL` como variável opcional (`sync: false`): configure nela a URL do PostgreSQL no painel do Render. Faça isso antes de carregar o currículo real ou acumular candidaturas. O banco não é provisionado automaticamente por este repositório.

## Limitações importantes
- A busca programada só fica ativa depois de configurar os três secrets do GitHub Actions.
- O currículo PDF é extraído para texto; PDFs escaneados sem texto selecionável não são processados.
- A pontuação é uma heurística, não uma garantia de adequação. Confira localização permitida, idioma, senioridade, salário e data de publicação no anúncio.
- O onboarding e o armazenamento de respostas estão implementados no código, mas a publicação no Render precisa ser verificada após o deploy.
- **Não existe envio automático de candidatura nesta versão.** O sistema ainda não tem conectores de candidatura por plataforma nem confirmação automática de envio. Não contorna CAPTCHAs, login, filas ou proteções anti-bot.
- Para automatizar candidaturas de verdade, implementar integrações específicas autorizadas para cada plataforma, testar uma a uma e manter registro somente após confirmação verificável.
- Nunca publique currículo, senha, tokens ou banco de dados em repositório público.

## Análise de compatibilidade e currículo personalizado
- Cada vaga listada tem uma ação para analisar termos em comum, possíveis lacunas e alertas literais de idioma a partir da descrição armazenada.
- A análise é heurística e não prova que a pessoa tem ou não tem uma competência. Pode ser limitada se a fonte não fornecer a descrição integral.
- O botão de currículo gera um arquivo DOCX reorganizando apenas texto já presente no currículo original e informa os termos do anúncio usados como direcionamento. Revise o arquivo antes de enviar.
- O documento personalizado não inventa experiência, formação, idiomas ou resultados. Ele não substitui uma revisão humana.
- Ainda não existe envio automático de candidaturas. O próximo estágio exige selecionar uma plataforma de recrutamento com API/fluxo de candidatura autorizado e testar com credenciais permitidas, sem contornar CAPTCHA ou outras proteções.
