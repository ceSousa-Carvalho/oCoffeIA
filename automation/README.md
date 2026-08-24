# oCoffeIA 1.0.1 — Gestão de KPI

Versão atual: **1.7.2**.

Aplicativo local para Windows. Não precisa de Claude, Codex, ChatGPT ou
assinatura premium para executar depois de instalado.

O arquivo `INSTALAR-oCoffeIA.cmd`, presente na raiz do pacote, realiza a
instalação e cria o atalho **oCoffeIA** na Área de Trabalho.

## Processos

- `processes/gestao-kpi`: download do JMS e atualização do Power BI.
- `processes/whatsapp`: captura, revisão humana e envio autorizado.
- `processes/sla`: atualização diária da Base_vencimentos e da tabela BD_D1.
- `processes/feishu`: revisão em duas etapas e preparação do SLA no Feishu.
- `processes/expedido`: processo manual "Expedido, mas não chegou", com filtros, Registro POD, planilha e cronômetro de seis horas.
- `ui`: interface local de configuração e operação.

## Regras do projeto

- Não versionar senhas, códigos de segurança, cookies, tokens ou links privados.
- Validar novos arquivos antes de substituir uma base usada pelo BI.
- Manter logs separados por processo.
- Só enviar mensagens externas após uma atualização bem-sucedida.
- "Expedido, mas não chegou" nunca é agendado: somente o líder pode iniciá-lo e confirmar o horário do deslacramento.
