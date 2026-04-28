---

## Feedback contínuo — após início do desenvolvimento

### 2026-04-28 — Atalho com botão físico

**Origem:** conversa informal com mulheres usuárias
**Contexto:** discussão sobre formas de acionar o SOS sem precisar abrir o app

**Pedido textual:**
> "Seria bom ter um atalho — caso ela aperte 3 vezes o botão de bloqueio de tela, ou aperte 4 vezes o botão de volume baixo, também pode ativar o SOS. Ela que pode configurar do jeito dela."

**Razão dada:**
- Em situação real de violência, abrir o app não é viável
- Celular pode estar no bolso, na mão do agressor, ou ela não pode olhar pra tela
- Botão físico é a única coisa acionável sem olhar e sem pegar o celular
- Personalização importante: cada mulher tem rotina e contexto diferente

**Análise técnica:**
- **Android:** totalmente possível via plugin nativo (3-5 cliques no botão de volume aciona SOS)
- **iOS:** restrições da Apple impedem interceptar botão lateral nativo (já reservado para Emergency SOS do iPhone). Workarounds:
  - Back Tap (toque nas costas do iPhone) — configurável em Settings, app só precisa estar instalado
  - Action Button (iPhone 15 Pro+) — usuária mapeia para abrir SafeCircle
  - Atalhos do iOS (Shortcut app) com automação de volume
  - NFC tag externa colada em bolsa/carteira

**Status:** registrado. Implementação prevista para Fase 3 (Diferencial), após Fase 1 (Bloqueadores) e Fase 2 (LGPD/SLA) estarem completas.

**Prioridade:** **alta** dentro da Fase 3. Validado por feedback direto de usuárias = problema real de usabilidade, não capricho técnico.

**Decisões pendentes (quando chegar a hora de implementar):**
- Quantos cliques de volume ativam? (sugestão padrão: 4 cliques em até 3 segundos, configurável)
- Combinação ou só botão único? (volume baixo + lock = mais difícil de acionar acidentalmente)
- Confirmação visual/háptica ou ativação silenciosa?
- Modo "discreto" — ativa SOS sem notificação visível na tela?

---

## Como adicionar novo feedback

Sempre que receber feedback de usuária:

1. Adicionar nova entrada nesta seção com data
2. Registrar **textualmente** o pedido (sem reformular)
3. Documentar a razão dada pela usuária
4. Anotar análise técnica (viável? complexo? plataforma específica?)
5. Atribuir Fase do roadmap (1, 2 ou 3) e prioridade dentro da fase
6. Listar decisões pendentes para quando for implementar

**Não filtrar feedback "óbvio" ou "já sabido".** Repetição de pedido por múltiplas usuárias é sinal forte de prioridade — se 5 mulheres pedem a mesma coisa, isso vai pro topo da lista mesmo que pareça simples.

---

## Estatísticas de feedback (atualizar periodicamente)

| Categoria | Quantidade | Fase prevista |
|-----------|------------|---------------|
| Pesquisa inicial (20+ mulheres) | _a preencher_ | múltiplas fases |
| Feedback contínuo registrado | 1 entrada (atalho físico) | Fase 3 |

---

## Aproveitamento estratégico do feedback

Este documento serve a três audiências além do desenvolvimento:

1. **Apresentação institucional (Polícia Federal, governo, ONGs):** prova que o SafeCircle é construído com base em escuta sistemática, não em suposição. Diferencial competitivo enorme em apresentação para licitação ou parceria.

2. **Pitch para investidores:** mostra metodologia de produto séria e ancoragem em mercado real. Investidor que já viu 100 pitches fica atento quando vê pesquisa de campo documentada.

3. **Validação acadêmica/social:** se um dia o app for objeto de estudo (pesquisa em segurança pública, dissertação, artigo), este documento é fonte primária citável.

**Cuidado de privacidade:** nunca incluir nomes, contatos, ou qualquer informação que identifique as mulheres que deram feedback. Manter o material anonimizado.
