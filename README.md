# Vagas IA

Aplicação privada para pesquisar e organizar vagas remotas, com execução sob demanda.

## Publicar no Render Free
1. No Render, selecione **New → Web Service** e conecte este repositório privado.
2. Selecione o plano **Free** e confirme os comandos definidos em `render.yaml`.
3. Defina `APP_USER` e `APP_PASSWORD` como variáveis de ambiente fortes e exclusivas.
4. Publique e teste `/api/health`.

## Importante
- O Render Free pode suspender o serviço após inatividade e tem limites mensais.
- Este MVP usa SQLite em `/tmp`, que é temporário. Não use para guardar dados importantes até configurarmos um banco persistente.
- A busca consulta feeds públicos Jobicy e Remotive. Resultados, cobertura geográfica e pontuação são aproximados.
- **Não há envio automático de candidaturas nesta versão.** O agente pesquisa e organiza vagas; a integração de envio será implementada por plataforma, respeitando as regras e os métodos de acesso autorizados. Não contorna CAPTCHAs nem controles antibot.
- A senha protege as rotas da aplicação por autenticação HTTP Basic.
