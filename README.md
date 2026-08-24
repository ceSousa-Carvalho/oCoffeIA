# oCoffeIA

Assistente local para Windows que automatiza o fluxo operacional JMS → XLSX → Power BI → revisão → WhatsApp.

## Recursos

- Reutiliza sessões separadas do Chrome para JMS e WhatsApp.
- Aguarda o download mais recente do Centro de Downloads.
- Atualiza e captura a página configurada do Power BI.
- Exige confirmação humana antes do envio ao WhatsApp.
- Envia o print como foto normal, acompanhado da mensagem configurada.
- Controla uma fila única e tenta novamente etapas temporariamente indisponíveis.
- Registra histórico das parciais e valida o envio na conversa.
- Acompanha rotas que precisam atingir 100% em até seis horas.
- Verifica atualizações publicadas neste repositório sem apagar configurações ou logins.

## Instalação

1. Baixe o projeto ou o pacote de instalação.
2. Execute `INSTALAR-oCoffeIA.cmd`.
3. Autorize a instalação dos componentes solicitados.
4. Informe o PBIX, o grupo do WhatsApp e os horários quando solicitado.
5. Faça login no JMS e no WhatsApp na primeira utilização.

Node.js, Chrome, Power BI e as dependências do navegador são verificados pelo instalador. Perfis, cookies, tokens, planilhas operacionais e o PBIX não são publicados no GitHub.

## Dados locais

O aplicativo é instalado em `C:\oCoffe`. Configurações permanecem em `C:\oCoffe\config`, relatórios em `C:\oCoffe\reports` e sessões do Chrome em perfis locais separados.

## Segurança

Nenhuma mensagem é enviada antes da revisão e confirmação do usuário. Não publique arquivos de configuração, perfis do navegador, logs ou relatórios empresariais.
