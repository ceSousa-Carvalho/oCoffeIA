@{
    # Este arquivo é somente um modelo. A configuração ativa é gravada em:
    # C:\oCoffe\config\gestao-kpi.json
    Versao = '1.7.2'
    JmsUrl = 'https://jmsbr.jtjms-br.com/index'
    Chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
    PerfilJms = 'C:\oCoffe\chrome-profile'
    PerfilWhatsApp = 'C:\oCoffe\whatsapp-profile'
    Downloads = '%USERPROFILE%\Downloads'
    BaseDir = 'C:\Gestão de KPI_Operacional_v2\Base_Gestão_de_pedidos_'
    PowerBI = 'C:\Gestão de KPI_Operacional_v2\Gestão de KPI.pbix'
    PaginaPowerBI = 'D+0 - RESUMIDO'
    SlaBaseDir = 'C:\Gestão de KPI_Operacional_v2\Base_vencimentos'
    SlaDiasHistorico = 27
    SlaHorario = '07:00'
    SlaPaginaPowerBI = 'SLA - VENCIMENTO'
    SlaGrupoFeishu = 'MA/PI - Hub/Pdd 网点管理'
    SlaMensagemFeishu = "Segue o SLA de {dataFinalJms}.`n`nAtualização gerada pelo Assistente oCoffeIA"
    LogDir = 'C:\Gestão de KPI_Operacional_v2\Automacao'
    GrupoWhatsApp = 'https://chat.whatsapp.com/COLE_O_CODIGO_DO_GRUPO'
    NomeGrupoWhatsApp = 'NOME EXATO DO GRUPO'
    HorariosAtualizacao = @('08:00', '10:30', '13:00', '15:00')
    AutomacaoPausada = $false
    MensagemWhatsApp = "@all Segue a parcial das {horario}.`n`nAtualização gerada pelo Assistente oCoffeIA"
    WhatsAppResponsavel = '5586999999999'
    AlertaDesempenhoAtivo = $true
    AlertaPercentualMinimo = 50
    AlertaMinimoHorasRota = 6
    AlertaMinimoPedidos = 10
    # Processo manual: nunca é incluído nos horários automáticos.
    ExpedidoBaseSigla = 'THE-PI'
    ExpedidoBases = @('THE-PI', 'RSO-MA', 'SLZ-MA')
    ExpedidoModeloPlanilha = 'C:\oCoffe\templates\Modelo-Expedido-nao-chegou.xlsx'
    ExpedidoPastaSaida = '%USERPROFILE%\Downloads\oCoffe-Expedido-nao-chegou'
}
