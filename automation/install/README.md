# Instalação em outras máquinas

O oCoffeIA funciona localmente e não usa Claude, Codex, ChatGPT ou assinatura
premium de IA.

## Pré-requisitos

- Windows 10 ou 11.
- Google Chrome.
- Node.js LTS.
- Power BI Desktop.
- Arquivo `Gestão de KPI.pbix` disponível no computador.
- Computador ligado e usuário conectado durante a execução.

## Instalar sem comandos

1. Extraia todo o ZIP.
2. Dê dois cliques em `INSTALAR-oCoffeIA.cmd`.
3. Informe o link e o nome exato do grupo.
4. Informe os horários diários ou pressione Enter para executar a cada hora.
5. Use o atalho **oCoffeIA** criado na Área de Trabalho.

O aplicativo será instalado em `C:\oCoffe`. A configuração local fica em:

`C:\oCoffe\config\gestao-kpi.json`

Na interface, o usuário pode alterar:

- horários de atualização;
- link e nome do grupo;
- arquivo PBIX;
- pasta das planilhas JMS.

A mensagem padrão é:

```text
@all Segue a parcial das {horario}.

Atualização gerada pelo Assistente oCoffeIA
```

`{horario}` usa o horário real em que a planilha foi baixada.

## Segurança e autenticação

Cada computador mantém perfis locais separados para JMS e WhatsApp. Senhas,
CAPTCHA, tokens e códigos temporários não fazem parte do pacote. O usuário faz
login quando solicitado. O WhatsApp só envia depois do clique em
**Confirmar e enviar**.

## Instalação pelo PowerShell (opcional)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\automation\install\Install-oCoffe.ps1
```

## Desinstalar

Dê dois cliques em `DESINSTALAR-oCoffeIA.cmd`. A tarefa automática será
removida e os dados locais serão preservados.
