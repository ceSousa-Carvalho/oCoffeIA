# Expedido, mas não chegou

Processo operacional exclusivamente manual. Ele não possui tarefa no Agendador do Windows e só começa quando o líder clica em **Executar Expedido, mas não chegou**, informa o horário real do deslacramento e confirma.

Fluxo aplicado:

1. consulta no JMS o intervalo do dia anterior até hoje, usando a base configurada;
2. abre o número total de encomendas do dia anterior, exporta a lista e baixa o arquivo mais recente do Centro de download;
3. exclui lotes iniciados por `BR`/`br`, pedidos filhos terminados em `-número` e duplicados;
4. consulta o rastreamento em Correspondência inteligente, em lotes de até 1.000 pedidos;
5. usa somente a última linha do Registro POD para decidir se o pedido foi expedido para a base, mas ainda não chegou;
6. cria uma cópia do modelo, preenche A:E e remove conteúdo/formatação abaixo do último pedido;
7. usa o primeiro identificador `SR...` ou `SE...` encontrado para nomear a planilha.

O cronômetro de seis horas é persistente, alerta quando faltam duas horas e pode ser parado pelo líder. Ele não inicia ou agenda o processo automaticamente.
