# Gestão de KPI

Primeiro processo do **oCoffe**.

## Fluxo previsto

1. O usuário conclui login e CAPTCHA do JMS quando necessário.
2. A exportação de Gestão de Pedidos de Entrega é baixada.
3. O Excel é validado e substitui a base anterior com segurança.
4. O Power BI Gestão de KPI é aberto, atualizado e salvo.
5. Após sucesso, um print pode ser enviado ao grupo autorizado no WhatsApp Web.

## Execução local

O Windows executa o fluxo nos horários configurados pelo usuário ou, por
padrão, a cada hora. A tarefa chama `Executar-oCoffe.ps1`, que baixa o JMS,
atualiza o Power BI e abre a revisão da parcial.

O log operacional fica em:

`C:\Gestão de KPI_Operacional_v2\Automacao\atualizacao.log`

## Segurança

O processo não deve armazenar senhas, códigos temporários, cookies ou tokens.
A sessão autenticada permanece no perfil protegido do navegador.
