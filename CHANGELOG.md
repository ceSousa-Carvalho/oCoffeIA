# Histórico de versões

Este projeto usa versionamento semântico: `MAIOR.MENOR.CORREÇÃO`.

## [1.8.6] - 2026-08-26

- Ajustado o SLA para selecionar Lista e Por data de envio antes de preencher o período.
- Mantida a data final em ontem e a data inicial exatamente 21 dias antes.
- Removido o filtro obrigatório de Base de entrega da consulta do SLA.
- Tornado explícito o clique em Consulta antes da exportação.

## [1.8.5] - 2026-08-26

- Ajustado o SLA diário para abrir Entrega realizada > Lista, selecionar Por data de envio e filtrar a Base de entrega configurada.
- Fixado o período do SLA entre ontem e exatamente 21 dias antes da data final.
- Corrigida a abertura do Centro de download do SLA quando o JMS mantém elementos duplicados ocultos.
- Adicionada espera pelo carregamento da página SLA - VENCIMENTO antes de atualizar filtros e salvar o Power BI.
- Corrigida a permissão do arquivo de configuração para salvar grupos, bases, horários e caminhos em outras máquinas.
- Adicionado o fluxo manual do SLA por planilha XLSX com atualização da BD_D1 e revisão.
- Removido integralmente o mascote, suas animações, temporizador, configurações e imagens para reduzir consumo e tamanho do pacote.

## [1.8.2] - 2026-08-25

- Adicionado modo manual para escolher uma planilha JMS e atualizar somente o Power BI.
- Adicionada compatibilidade com o PBIX legado e normalização automática do nome da aba exportada.
- Corrigido o reconhecimento de páginas ocultas em português no Power BI.
- Corrigida a medida de pedidos não entregues no SLA.
- Incluído o PBIX compatível no instalador completo para novas máquinas.

## [1.8.1] - 2026-08-24

- Adicionada a aba fixa **Relatório final** na interface.
- Exibidas todas as rotas com saída, horas em rota, entregas, percentual e status.
- Mantido o último relatório válido na tela até a próxima atualização terminar com sucesso.
- Integrada a renovação do relatório ao ciclo horário de JMS e Power BI.
- Mantido o limite mínimo de pedidos somente para o disparo de alertas.

## [1.8.0] - 2026-08-24

- Adicionada fila única com espera controlada para atualizações simultâneas.
- Adicionadas retentativas automáticas no JMS, Power BI, captura e WhatsApp.
- Adicionado estado estruturado do fluxo para acompanhamento em tempo real.
- Adicionada validação do envio na conversa e histórico JSONL das parciais.
- Corrigido o cálculo de entregas pela marca de assinatura.
- Adicionado acompanhamento de rotas concluídas, em andamento e atrasadas no prazo de seis horas.
- Adicionado atualizador pelo GitHub com preservação de configurações e logins.
- Removidas dependências restauráveis do pacote para reduzir seu tamanho.

## [1.7.2] - 2026-08-23

- Corrigido o aviso de arquivo não encontrado ao manter o modelo Excel já configurado.
- O cadastro de novas bases não obriga mais o administrador a selecionar novamente o modelo e a pasta de saída.
- O instalador agora inclui um modelo Excel limpo e o mantém em `C:\oCoffe\templates`, sem depender da pasta Downloads.

## [1.7.1] - 2026-08-23

- Adicionado cadastro de múltiplas bases administradas.
- Adicionada seleção da base antes de cada execução manual de "Expedido, mas não chegou".
- Mantida compatibilidade com a configuração de base única da versão anterior.

## [1.7.0] - 2026-08-23

- Adicionado o processo manual **Expedido, mas não chegou**, iniciado exclusivamente pelo líder.
- Adicionado cronômetro persistente de seis horas, aviso com duas horas restantes e parada manual.
- Automatizadas consulta do dia anterior, exportação e seleção do arquivo mais recente no Centro de download.
- Adicionados filtros para lotes `BR/br`, pedidos filhos e duplicados, com consultas em lotes de até 1.000.
- Adicionada validação pela última linha do Registro POD e identificação da primeira viagem `SR/SE`.
- Adicionada geração segura da planilha pelo modelo, sem alterar o original e sem amarelo abaixo do último pedido.

## [1.6.1] - 2026-08-23

- Corrigida a abertura visível do PowerShell nas execuções agendadas.
- Removida a execução automática a cada hora quando nenhum horário foi configurado.
- Adicionado botão único e persistente para pausar ou continuar todas as automações.
- Adicionada configuração do WhatsApp do responsável por alertas operacionais.
- Adicionada análise configurável de entregadores abaixo do ritmo esperado.
- Mantida a confirmação humana antes de enviar qualquer alerta pelo WhatsApp.

## [1.6.0] - 2026-08-22

- Adicionada interação por clique com o mascote oCoffe.
- Melhorado o aproveitamento do espaço e o comportamento responsivo do painel.
- Mantidas as rotinas de atualização da parcial, SLA diário e revisão antes do envio.
- Preparada distribuição local para Windows, sem dependência de Claude ou Codex.

## [1.5.0] - 2026-08-22

- Reorganizado o painel principal para diferentes resoluções de tela.
- Melhoradas as áreas de status, ações rápidas e fluxo da automação.

## [1.4.0] - 2026-08-22

- Adicionados movimentos, poses, mensagens de erro e dicas úteis do mascote.

## [1.3.0] - 2026-08-22

- Introduzido o mascote oCoffe e a proteção contra múltiplas instâncias.

## [1.2.0] - 2026-08-22

- Adicionado o processo diário de SLA e a preparação de reporte pelo Feishu.

## [1.1.0] - 2026-08-22

- Adicionadas automação programada, atualização do Power BI e revisão do reporte.

## [1.0.0] - 2026-08-22

- Primeira versão instalável do oCoffeIA para Windows.
