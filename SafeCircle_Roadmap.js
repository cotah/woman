const fs = require("fs");
const { Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
        Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
        ShadingType, PageNumber, PageBreak, LevelFormat } = require("docx");

const border = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 80, bottom: 80, left: 120, right: 120 };

function headerCell(text, width) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: "1A1A2E", type: ShadingType.CLEAR },
    margins: cellMargins,
    verticalAlign: "center",
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", font: "Arial", size: 20 })] })],
  });
}

function cell(text, width, opts = {}) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: opts.fill ? { fill: opts.fill, type: ShadingType.CLEAR } : undefined,
    margins: cellMargins,
    children: [new Paragraph({ children: [new TextRun({ text, font: "Arial", size: 20, bold: opts.bold, color: opts.color })] })],
  });
}

function statusCell(status, width) {
  const colors = {
    "DONE": { fill: "D4EDDA", color: "155724" },
    "IN PROGRESS": { fill: "FFF3CD", color: "856404" },
    "PLANNED": { fill: "D6E9F8", color: "0C5460" },
    "FUTURE": { fill: "E2E3E5", color: "383D41" },
  };
  const c = colors[status] || colors["FUTURE"];
  return cell(status, width, { fill: c.fill, color: c.color, bold: true });
}

const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 36, bold: true, font: "Arial", color: "1A1A2E" },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial", color: "6C47FF" },
        paragraph: { spacing: { before: 240, after: 160 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 24, bold: true, font: "Arial", color: "333333" },
        paragraph: { spacing: { before: 200, after: 120 }, outlineLevel: 2 } },
    ]
  },
  numbering: {
    config: [
      { reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets2", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets3", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets4", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "bullets5", levels: [{ level: 0, format: LevelFormat.BULLET, text: "\u2022", alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    headers: {
      default: new Header({ children: [new Paragraph({
        alignment: AlignmentType.RIGHT,
        children: [new TextRun({ text: "SafeCircle \u2014 Product Roadmap", font: "Arial", size: 18, color: "999999", italics: true })]
      })] })
    },
    footers: {
      default: new Footer({ children: [new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [new TextRun({ text: "Page ", font: "Arial", size: 18, color: "999999" }), new TextRun({ children: [PageNumber.CURRENT], font: "Arial", size: 18, color: "999999" })]
      })] })
    },
    children: [
      // TITLE
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [
        new TextRun({ text: "SafeCircle", size: 52, bold: true, font: "Arial", color: "6C47FF" }),
      ]}),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 100 }, children: [
        new TextRun({ text: "Product Roadmap & Status", size: 32, font: "Arial", color: "1A1A2E" }),
      ]}),
      new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 400 }, children: [
        new TextRun({ text: "Atualizado em: 11 de Abril de 2026", size: 22, font: "Arial", color: "666666" }),
      ]}),

      // ONDE ESTAMOS
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Onde Estamos Agora")] }),
      new Paragraph({ spacing: { after: 200 }, children: [
        new TextRun({ text: "O SafeCircle tem o backend (NestJS) e frontend (Flutter Web) deployados no Railway. A infraestrutura base funciona: autentica\u00E7\u00E3o, dashboard, contatos de confian\u00E7a, jornadas, alerta de emerg\u00EAncia, e grava\u00E7\u00E3o de \u00E1udio. O app mobile (Flutter) est\u00E1 em est\u00E1gio de configura\u00E7\u00E3o de features avan\u00E7adas.", font: "Arial", size: 22 }),
      ]}),

      // STATUS TABLE
      new Table({
        width: { size: 9360, type: WidthType.DXA },
        columnWidths: [3500, 3500, 2360],
        rows: [
          new TableRow({ children: [headerCell("Componente", 3500), headerCell("Detalhe", 3500), headerCell("Status", 2360)] }),
          new TableRow({ children: [cell("Backend API", 3500), cell("NestJS no Railway, Postgres, Redis", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Frontend Web", 3500), cell("Flutter Web com CanvasKit, nginx", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Autentica\u00E7\u00E3o", 3500), cell("JWT + refresh token + auto-login", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Dashboard", 3500), cell("Bot\u00E3o SOS + status + a\u00E7\u00F5es r\u00E1pidas", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Contatos de Confian\u00E7a", 3500), cell("CRUD + permiss\u00F5es granulares", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Safe Journey", 3500), cell("Iniciar jornada + destinos + timer", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Alerta de Emerg\u00EAncia", 3500), cell("Long-press SOS + notifica\u00E7\u00E3o", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Dark Mode", 3500), cell("Toggle de tema no Settings", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Telefone Internacional", 3500), cell("Bandeira + c\u00F3digo pa\u00EDs (registro + contatos)", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Onboarding Autom\u00E1tico", 3500), cell("Fluxo 6 steps no primeiro login", 3500), statusCell("IN PROGRESS", 2360)] }),
          new TableRow({ children: [cell("Grava\u00E7\u00E3o Palavra Ativa\u00E7\u00E3o", 3500), cell("Escolher palavra + gravar 3x a voz", 3500), statusCell("IN PROGRESS", 2360)] }),
          new TableRow({ children: [cell("Build Mobile (iOS/Android)", 3500), cell("Compilar app nativo", 3500), statusCell("PLANNED", 2360)] }),
        ]
      }),

      new Paragraph({ children: [] }),

      // FASES
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Roadmap por Fases")] }),

      // FASE 1
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("Fase 1 \u2014 Fundamentos + Onboarding (AGORA)")] }),
      new Paragraph({ spacing: { after: 100 }, children: [
        new TextRun({ text: "Objetivo: Deixar o app funcional, com onboarding completo e grava\u00E7\u00E3o da palavra de ativa\u00E7\u00E3o por voz.", font: "Arial", size: 22, italics: true, color: "555555" }),
      ]}),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Onboarding autom\u00E1tico no primeiro login (6 steps com cards explicativos)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Escolha da palavra de ativa\u00E7\u00E3o personalizada", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Grava\u00E7\u00E3o de 3 amostras de voz para calibra\u00E7\u00E3o", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Permiss\u00F5es (localiza\u00E7\u00E3o, microfone, notifica\u00E7\u00F5es)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Adicionar primeiro contato de confian\u00E7a", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Definir mensagem de emerg\u00EAncia", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Telefone internacional com bandeira e c\u00F3digo do pa\u00EDs", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets", level: 0 }, children: [new TextRun({ text: "Corre\u00E7\u00F5es: MIME types nginx, bot\u00E3o journey cortado, QuickDestinationCard", font: "Arial", size: 22 })] }),

      new Paragraph({ children: [] }),

      // FASE 2
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("Fase 2 \u2014 Reconhecimento de Voz Inteligente")] }),
      new Paragraph({ spacing: { after: 100 }, children: [
        new TextRun({ text: "Objetivo: O app ouve a palavra de ativa\u00E7\u00E3o e verifica se \u00E9 a dona do telefone falando (voice biometrics).", font: "Arial", size: 22, italics: true, color: "555555" }),
      ]}),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Reconhecimento da Palavra (Speech-to-Text)")] }),
      new Paragraph({ numbering: { reference: "bullets2", level: 0 }, children: [new TextRun({ text: "Escuta cont\u00EDnua em background usando speech_to_text (on-device, sem internet)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets2", level: 0 }, children: [new TextRun({ text: "Detectar a palavra de ativa\u00E7\u00E3o escolhida pela usu\u00E1ria", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets2", level: 0 }, children: [new TextRun({ text: "Matching fuzzy (tolera pron\u00FAncia levemente diferente, sotaque, press\u00E3o)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets2", level: 0 }, children: [new TextRun({ text: "Funcionar offline (cr\u00EDtico para seguran\u00E7a)", font: "Arial", size: 22 })] }),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Verifica\u00E7\u00E3o de Identidade por Voz")] }),
      new Paragraph({ numbering: { reference: "bullets3", level: 0 }, children: [new TextRun({ text: "Comparar a voz capturada com as 3 grava\u00E7\u00F5es do onboarding", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets3", level: 0 }, children: [new TextRun({ text: "Gerar voiceprint (embedding) usando modelo on-device (TensorFlow Lite ou ONNX)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets3", level: 0 }, children: [new TextRun({ text: "Score de confian\u00E7a: s\u00F3 ativar alerta se a voz bate com a dona (>80% similaridade)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets3", level: 0 }, children: [new TextRun({ text: "Evitar ativa\u00E7\u00F5es acidentais (crian\u00E7as, TV, outras pessoas)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets3", level: 0 }, children: [new TextRun({ text: "Tudo roda no celular (privacidade total, sem enviar \u00E1udio pro servidor)", font: "Arial", size: 22 })] }),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Tecnologias Recomendadas")] }),
      new Paragraph({ numbering: { reference: "bullets4", level: 0 }, children: [new TextRun({ text: "speech_to_text (Flutter) \u2014 reconhecimento de fala on-device", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets4", level: 0 }, children: [new TextRun({ text: "tflite_flutter \u2014 rodar modelo de speaker verification no celular", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets4", level: 0 }, children: [new TextRun({ text: "Resemblyzer ou SpeechBrain (Python backend) \u2014 treinar/exportar modelo de voiceprint", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets4", level: 0 }, children: [new TextRun({ text: "MFCC (Mel-Frequency Cepstral Coefficients) \u2014 extrair caracter\u00EDsticas da voz", font: "Arial", size: 22 })] }),

      new Paragraph({ children: [] }),

      // FASE 3
      new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun("Fase 3 \u2014 Aprendizado Cont\u00EDnuo de Voz + IA")] }),
      new Paragraph({ spacing: { after: 100 }, children: [
        new TextRun({ text: "Objetivo: A IA melhora com o tempo, entendendo cada vez melhor a voz da usu\u00E1ria e detectando situa\u00E7\u00F5es de perigo pelo tom.", font: "Arial", size: 22, italics: true, color: "555555" }),
      ]}),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Refinamento do Modelo de Voz")] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "A cada uso do app, atualizar o voiceprint da usu\u00E1ria (com consentimento)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Adaptar a mudan\u00E7as naturais de voz (resfriado, estresse, idade)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Federated Learning: treinar no dispositivo sem enviar dados pro servidor", font: "Arial", size: 22 })] }),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Detec\u00E7\u00E3o de Tom de Perigo")] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Analisar tom de voz: medo, pap\u00E2nico, coer\u00E7\u00E3o, choro", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Modelo de emotion detection (SER \u2014 Speech Emotion Recognition)", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Alertas proativos: se detectar p\u00E2nico mesmo sem a palavra de ativa\u00E7\u00E3o", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Confirma\u00E7\u00E3o silenciosa antes de disparar (vibra\u00E7\u00E3o sutil + contagem regressiva)", font: "Arial", size: 22 })] }),

      new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun("Intelig\u00EAncia Contextual")] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Combinar voz + localiza\u00E7\u00E3o + hor\u00E1rio para avaliar risco", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Se a usu\u00E1ria est\u00E1 em \u00E1rea de risco + tom de medo = alerta autom\u00E1tico", font: "Arial", size: 22 })] }),
      new Paragraph({ numbering: { reference: "bullets5", level: 0 }, children: [new TextRun({ text: "Machine Learning on-device pra classificar n\u00EDvel de urg\u00EAncia", font: "Arial", size: 22 })] }),

      new Paragraph({ children: [new PageBreak()] }),

      // TIMELINE
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Timeline Estimada")] }),
      new Table({
        width: { size: 9360, type: WidthType.DXA },
        columnWidths: [2000, 4000, 1680, 1680],
        rows: [
          new TableRow({ children: [headerCell("Fase", 2000), headerCell("Entregáveis", 4000), headerCell("Prazo", 1680), headerCell("Status", 1680)] }),
          new TableRow({ children: [cell("Fase 1", 2000, { bold: true }), cell("Onboarding + Grava\u00E7\u00E3o Voz + Corre\u00E7\u00F5es", 4000), cell("Abril 2026", 1680), statusCell("IN PROGRESS", 1680)] }),
          new TableRow({ children: [cell("Fase 2", 2000, { bold: true }), cell("Speech-to-Text + Voice Biometrics", 4000), cell("Maio-Jun 2026", 1680), statusCell("PLANNED", 1680)] }),
          new TableRow({ children: [cell("Fase 3", 2000, { bold: true }), cell("Aprendizado Cont\u00EDnuo + Emotion Detection", 4000), cell("Jul-Ago 2026", 1680), statusCell("FUTURE", 1680)] }),
          new TableRow({ children: [cell("Beta", 2000, { bold: true }), cell("Teste com usu\u00E1rias reais + ajustes", 4000), cell("Set 2026", 1680), statusCell("FUTURE", 1680)] }),
          new TableRow({ children: [cell("Launch", 2000, { bold: true }), cell("App Store + Google Play", 4000), cell("Out 2026", 1680), statusCell("FUTURE", 1680)] }),
        ]
      }),

      new Paragraph({ children: [] }),

      // BUGS CORRIGIDOS
      new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun("Corre\u00E7\u00F5es Recentes")] }),
      new Table({
        width: { size: 9360, type: WidthType.DXA },
        columnWidths: [3500, 3500, 2360],
        rows: [
          new TableRow({ children: [headerCell("Problema", 3500), headerCell("Causa", 3500), headerCell("Status", 2360)] }),
          new TableRow({ children: [cell("App n\u00E3o carregava no browser/celular", 3500), cell("MIME types errados no nginx (tudo application/octet-stream)", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("502 Bad Gateway no Railway", 3500), cell("Vari\u00E1vel PORT faltando + config nginx", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Bot\u00E3o Start Journey cortado", 3500), cell("Column sem scroll, Spacer empurrava bot\u00E3o pra fora", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("QuickDestinationCard incompleto", 3500), cell("Arquivo truncado, classe sem build()", 3500), statusCell("DONE", 2360)] }),
          new TableRow({ children: [cell("Telefone sem c\u00F3digo de pa\u00EDs", 3500), cell("TextFormField b\u00E1sico sem formata\u00E7\u00E3o", 3500), statusCell("DONE", 2360)] }),
        ]
      }),

      new Paragraph({ children: [] }),
      new Paragraph({ spacing: { before: 400 }, alignment: AlignmentType.CENTER, children: [
        new TextRun({ text: "SafeCircle \u2014 Prote\u00E7\u00E3o pessoal inteligente", font: "Arial", size: 20, italics: true, color: "6C47FF" }),
      ]}),
    ]
  }]
});

Packer.toBuffer(doc).then(buffer => {
  fs.writeFileSync("/sessions/zen-serene-mendel/mnt/woman/SafeCircle_Roadmap.docx", buffer);
  console.log("Roadmap created successfully!");
});
