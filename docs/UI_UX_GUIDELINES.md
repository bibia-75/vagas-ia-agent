# Diretrizes de UX e UI

> Layout, navegação, identidade visual, responsividade e padrões de interface.
> A identidade visual final depende de [DECISIONS.md, D-17](DECISIONS.md). Até lá, vale a proposta abaixo.

## 1. Princípios de experiência

1. **Cadastre uma vez, use em todo lugar.** Nenhuma tela pede um dado que o sistema já tem.
2. **Uma decisão por tela.** Fluxos longos são divididos em passos curtos, com progresso visível.
3. **A IA trabalha, a pessoa confere.** Resultados de IA aparecem como sugestão destacada, com "Aceitar", "Editar" e "Descartar".
4. **Nada de botão enfeite.** Todo elemento clicável faz algo real; o que ainda não existe não aparece.
5. **Linguagem simples.** Português do Brasil, frases curtas, sem jargão de RH ou de tecnologia. "Vaga" e não "posição"; "Currículo" e não "CV" nas telas principais.
6. **Erros que ensinam.** Toda mensagem de erro diz o que aconteceu e o que fazer.
7. **Celular primeiro para o candidato, desktop primeiro para a empresa.** Candidatos usam muito o celular; recrutadores trabalham no computador, mas o pipeline precisa funcionar no celular.

## 2. Identidade visual (proposta inicial)

| Elemento | Proposta |
| --- | --- |
| Nome | Vagas IA |
| Personalidade | Confiável, acolhedora, eficiente; tecnologia a serviço das pessoas, sem visual "robótico" |
| Cor primária | Azul-petróleo `#0F5C6E` (confiança) |
| Cor de destaque | Coral `#F26B4F` (ação, usada com moderação em botões principais e destaques) |
| Cor de apoio IA | Violeta suave `#6D5BD0` (identifica sugestões geradas por IA) |
| Neutros | Escala de cinza quente: `#1F1D1B` (texto), `#5F5A55` (texto secundário), `#E7E2DD` (bordas), `#F7F5F2` (fundo) |
| Estados | Sucesso `#1F8A5B`, alerta `#B7791F`, erro `#C2412D`, informação `#2B6CB0` |
| Tipografia | Inter (interface) com números tabulares em tabelas; tamanho base 16 px |
| Ícones | Lucide (traço consistente, licença aberta) |
| Cantos | 8 px em campos e botões, 12 px em cartões |
| Ilustrações | Simples, com pessoas diversas, sem estereótipos |

Todas as combinações de texto e fundo precisam de contraste mínimo 4,5:1 (texto normal) e 3:1 (texto grande e ícones). As cores acima são ponto de partida; os tokens finais ficam em `frontend/app/globals.css` como variáveis CSS e no tema do Tailwind, para trocar a identidade sem mexer nos componentes.

O painel atual usa tons de marrom (`#4c3933`). Manter essa paleta ou adotar a nova é parte da decisão D-17.

## 3. Sistema de design

- Base: **Tailwind CSS** + componentes **shadcn/ui** (construídos sobre Radix, acessíveis, código copiado para o projeto e customizável) **[D-17]**.
- Componentes próprios em `frontend/components/ui/` com variações documentadas: Button, Input, Select, Textarea, Checkbox, Switch, Dialog, Sheet (painel lateral), Tabs, Toast, Badge, Avatar, Card, Table, Skeleton, EmptyState, ErrorState, FileDropzone, Stepper, KanbanBoard, AISuggestion.
- Componente **AISuggestion**: borda e ícone violeta, rótulo "Sugestão da IA", ações Aceitar, Editar e Descartar, e link "Por que esta sugestão?" quando houver explicação.
- Espaçamento em múltiplos de 4 px.
- Modo escuro: fora do MVP, mas os tokens já devem permitir.

## 4. Mapa de navegação

### 4.1 Público

```
/                       Landing: proposta de valor para candidatos e empresas
/vagas                  Busca pública de vagas
/vagas/[tipo]/[id]      Detalhe da vaga
/empresas/[slug]        Página pública da empresa
/planos                 Planos para candidatos e empresas
/entrar, /cadastrar, /recuperar-senha, /verificar-email, /convite/[token]
/termos, /privacidade, /cookies
```

### 4.2 Candidato (`/app/candidato`)

Barra lateral no desktop, barra inferior no celular (5 itens: Início, Vagas, Candidaturas, Mensagens, Perfil).

```
Início                  Dashboard: completude do perfil, próximas entrevistas, candidaturas recentes, vagas recomendadas
Vagas                   Busca com filtros, vagas salvas, recomendadas
Candidaturas            Internas (com linha do tempo) e externas (acompanhamento)
Mensagens               Conversas por candidatura
Perfil                  Dados, experiências, formação, competências, idiomas
  Cofre                 Documentos enviados, revisão pendente
  Currículos            Lista, editor, versões, ATS
  Respostas salvas
Preparação              Entrevistas (Fase 6)
Configurações           Conta, segurança, notificações, privacidade (consentimentos, exportação, exclusão), plano
```

### 4.3 Empresa (`/app/empresa/[orgSlug]`)

Seletor de contexto no topo ("Candidato" / organizações), barra lateral fixa.

```
Painel                  Vagas ativas, candidaturas novas, entrevistas da semana, alertas do plano
Vagas                   Lista com filtros por status; Nova vaga (com IA ou manual)
  [vaga]                Resumo · Pipeline (Kanban) · Candidatos (lista) · Configurações da vaga
Candidatos              Todas as candidaturas da organização, com filtros
Banco de talentos       (planos Pro e Business)
Entrevistas             Agenda
Mensagens
Relatórios
Equipe                  Membros, convites, papéis
Configurações           Perfil da empresa, verificação, plano e cobrança, auditoria
```

### 4.4 Administração (`/admin`)

```
Visão geral · Usuários · Empresas · Verificações · Vagas · Candidaturas (agregado)
Planos · Assinaturas · Pagamentos · IA (consumo e configuração) · Fontes de vagas
Filas e erros · Auditoria · Pedidos LGPD
```

## 5. Telas principais e comportamento esperado

### 5.1 Cadastro inteligente (cofre)

1. Área de arrastar e soltar grande: "Envie currículos, certificados e diplomas. Pode mandar vários de uma vez, ou um ZIP."
2. Lista de arquivos com barra de progresso individual de envio.
3. Após o envio, cada arquivo mostra o estado: "Na fila", "Lendo", "Pronto para conferir", "Não foi possível ler" (com o motivo e o que fazer).
4. Tela de revisão em lote: tabela (desktop) ou cartões (celular), um item por documento, com campos editáveis, confiança indicada por cor e "ver documento" lado a lado. Botões "Aceitar todos os de alta confiança" e "Aceitar selecionados".
5. Itens duplicados aparecem marcados, com opção de ignorar.
6. Confirmação final: "23 certificados adicionados ao seu perfil. 41 competências identificadas."

### 5.2 Candidatura simplificada (no máximo 3 passos para perfil completo)

1. **Currículo:** versão sugerida, opção "Personalizar para esta vaga" (mostra prévia das mudanças).
2. **Complete o que falta:** só os campos ausentes e as perguntas da empresa, com respostas salvas sugeridas.
3. **Revise e envie:** resumo do que a empresa vai receber, caixa de consentimento de compartilhamento, botão "Enviar candidatura".
4. Tela de sucesso com o que acontece agora e link para acompanhar.

### 5.3 Criador de vagas por IA

- Conversa guiada em formato de formulário em passos (não chat livre): uma ou duas perguntas por tela, com exemplos de resposta.
- Perguntas adaptativas aparecem quando necessário (ex.: modalidade híbrida pergunta os dias presenciais).
- Resultado em modo de edição: cada seção (título, descrição, responsabilidades, requisitos, benefícios) editável, com marcação de sugestão da IA.
- Avisos de termos discriminatórios aparecem em linha, explicando o motivo.
- Ações: "Salvar rascunho", "Visualizar como candidato", "Publicar".

### 5.4 Pipeline (Kanban)

- Colunas por etapa com contagem; cartões com nome, cargo atual, compatibilidade (se gerada), tempo na etapa e ícones de entrevista e mensagens não lidas.
- Arrastar e soltar no desktop; no celular, menu "Mover para..." em cada cartão.
- Mover para "Reprovados" abre diálogo de motivo e mensagem; mover para "Contratados" pede confirmação.
- Painel lateral do candidato ao clicar no cartão: currículo enviado, respostas, resumo da IA com o aviso de apoio, avaliações, entrevistas, mensagens, histórico.
- Filtros por compatibilidade, avaliação, etiqueta e texto.

### 5.5 Painel da vaga

Indicadores da especificação no topo: total de candidaturas, em análise, pré-selecionados, entrevistas agendadas, contratados, reprovados. Abaixo, abas Pipeline e Lista.

## 6. Estados obrigatórios em toda tela com dados

| Estado | Padrão |
| --- | --- |
| Carregando | Skeleton no formato do conteúdo (nunca tela branca) |
| Vazio | Ilustração simples + frase explicando + ação principal ("Você ainda não tem vagas. Criar primeira vaga") |
| Erro | O que aconteceu + botão "Tentar de novo" + código do erro pequeno para suporte |
| Sem permissão | Explica qual papel é necessário e quem pode conceder |
| Limite do plano | Mostra uso atual, data de renovação e opção de mudar de plano |
| Processando IA | Mensagem de progresso; o usuário pode sair da tela e é notificado ao terminar |

## 7. Formulários

- Rótulo sempre visível acima do campo (nunca só placeholder).
- Validação ao sair do campo e ao enviar; mensagem abaixo do campo, em vermelho com ícone.
- Campos opcionais marcados como "(opcional)"; obrigatórios não levam asterisco quando a maioria for obrigatória.
- Máscaras para telefone, CNPJ e moeda; datas com seletor e digitação livre `dd/mm/aaaa`.
- Salvamento automático de rascunho em formulários longos (vaga, currículo).
- Botão de envio desabilitado enquanto envia, com indicação de progresso; nunca enviar duas vezes.

## 8. Responsividade

| Faixa | Largura | Comportamento |
| --- | --- | --- |
| Celular | até 639 px | Uma coluna; barra de navegação inferior (candidato); tabelas viram cartões; Kanban com rolagem horizontal por coluna e menu "Mover para" |
| Tablet | 640 a 1023 px | Navegação recolhível; duas colunas onde fizer sentido |
| Desktop | a partir de 1024 px | Barra lateral fixa; painéis laterais para detalhes; Kanban completo |

Alvos de toque com pelo menos 44 × 44 px. Testes Playwright rodam em 390 px e 1280 px de largura.

## 9. Acessibilidade (WCAG 2.2 nível AA)

- Navegação completa por teclado, foco visível, ordem lógica.
- Arrastar e soltar sempre com alternativa por botão ou menu.
- Rótulos e descrições acessíveis em todos os controles; ícones sozinhos com `aria-label`.
- Mensagens dinâmicas (toasts, progresso) anunciadas por `aria-live`.
- Não depender só de cor para indicar estado (ícone ou texto junto).
- Respeitar `prefers-reduced-motion`.
- Verificação automática com axe nos testes Playwright das telas principais.

## 10. Escrita da interface

- Tratamento por "você".
- Botões com verbo: "Enviar candidatura", "Publicar vaga", "Salvar alterações".
- Datas no formato brasileiro (`20/11/2026`, "há 2 dias"); moeda `R$ 3.500,00`.
- Evitar termos que sugiram decisão da IA: usar "compatibilidade estimada" e não "nota do candidato".
- Mensagens de reprovação ao candidato: respeitosas, padrão editável pela empresa, sem motivo interno.

## 11. Desempenho percebido

- Primeira renderização útil abaixo de 2,5 s em 4G (Core Web Vitals: LCP < 2,5 s, INP < 200 ms, CLS < 0,1).
- Páginas públicas renderizadas no servidor; áreas logadas com carregamento progressivo.
- Imagens otimizadas pelo Next.js; logos limitados a 512 px.
