const { chromium } = require('playwright-core');
const { getJmsSession, disconnectJmsSession } = require('./jms-browser-session');
const fs = require('fs');
const path = require('path');

const configFile = 'C:\\oCoffe\\config\\gestao-kpi.json';
let config = {};
if (fs.existsSync(configFile)) {
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, '')); } catch (_) {}
}
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, name) => process.env[name] || `%${name}%`);
const chrome = expand(config.jmsBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = expand(config.perfilJms) || 'C:\\oCoffe\\chrome-profile';
const downloads = expand(config.downloads) || path.join(process.env.USERPROFILE, 'Downloads');
const logDir = expand(config.logDir) || 'C:\\Gestão de KPI_Operacional_v2\\Automacao';
const logFile = path.join(logDir, 'navegador.log');
const jmsUrl = config.jmsUrl || 'https://jmsbr.jtjms-br.com/index';

fs.mkdirSync(profile, { recursive: true });
fs.mkdirSync(logDir, { recursive: true });

function log(message) {
  fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`, 'utf8');
}

async function clickText(page, text, timeout = 30000) {
  const locator = page.getByText(text, { exact: false }).last();
  await locator.waitFor({ state: 'visible', timeout });
  await locator.click();
}

async function setToday(page) {
  const day = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit'
  }).format(new Date());

  const changed = await page.locator('input').evaluateAll((inputs, values) => {
    let count = 0;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    for (const input of inputs) {
      if (/^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}$/.test(input.value)) {
        const suffix = count === 0 ? '00:00:00' : '23:59:59';
        setter.call(input, `${values.day} ${suffix}`);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        count += 1;
        if (count === 2) break;
      }
    }
    return count;
  }, { day });

  if (changed < 2) throw new Error('Não foi possível identificar os dois campos de data.');
  log(`Período configurado para ${day}.`);
}

(async () => {
  const { browser, context, page: sessionPage } = await getJmsSession({ chrome, profile, jmsUrl, log });

  let page;
  try {
    page = sessionPage;
    page.on('response', response => {
      const headers = response.headers();
      const disposition = headers['content-disposition'] || '';
      const type = headers['content-type'] || '';
      if (disposition || /excel|spreadsheet|octet-stream/i.test(type)) {
        log(`ARQUIVO HTTP ${response.status()} ${type} ${disposition} ${response.url()}`);
      }
    });
    await page.goto(jmsUrl, { waitUntil: 'domcontentloaded' });

    const homeCards = page.locator('.grid-content.home-card');
    if (/\/login/i.test(page.url()) || !(await homeCards.first().isVisible({ timeout: 5000 }).catch(() => false))) {
      log('Login/CAPTCHA solicitado; aguardando o usuário por até 10 minutos.');
      await homeCards.first().waitFor({ state: 'visible', timeout: 600000 });
    }

    const language = await page.evaluate(() => localStorage.getItem('lang'));
    if (language !== 'PT') {
      await page.evaluate(() => localStorage.setItem('lang', 'PT'));
      await page.reload({ waitUntil: 'domcontentloaded' });
      log('Idioma do JMS alterado para português antes da exportação.');
    }

    // O quinto cartão é o módulo Gestão de Bases em todos os idiomas do JMS.
    const baseCard = homeCards.nth(4);
    await baseCard.waitFor({ state: 'visible', timeout: 60000 });
    await baseCard.click();
    const orderManagement = page.locator('.sidebar .text-tooltips').first();
    await orderManagement.waitFor({ state: 'visible', timeout: 60000 });
    await orderManagement.click();
    // Quarto item do grupo é Gestão de pedido JMS de entrega.
    const deliveryOrders = page.locator('.sidebar-body ul .text-tooltips').nth(4);
    await deliveryOrders.waitFor({ state: 'visible', timeout: 60000 });
    await deliveryOrders.click();
    await page.waitForLoadState('domcontentloaded');

    const deliveryTime = page.locator('.search-time-range .el-radio').nth(1);
    await deliveryTime.click();
    await setToday(page);
    const toolbarButtons = page.locator('.avue-crud__left > button');
    await toolbarButtons.nth(0).click();
    await page.waitForTimeout(5000);
    const exportStarted = new Date();
    await toolbarButtons.nth(1).click();
    await page.waitForTimeout(3000);
    await toolbarButtons.nth(5).click();

    const dialog = page.locator('.el-dialog__wrapper:visible').last();
    await dialog.waitFor({ state: 'visible', timeout: 30000 });
    let downloadLink = null;
    let latestExport = null;
    const deadline = Date.now() + 5 * 60 * 1000;
    while (Date.now() < deadline) {
      const queryButton = dialog.getByText('Consulta', { exact: true }).first();
      if (await queryButton.isVisible().catch(() => false)) await queryButton.click();
      await page.waitForTimeout(2500);

      // O JMS ordena esta lista do registro mais antigo para o mais novo.
      // Quando há várias páginas, o arquivo mais recente está na última.
      const pageNumbers = dialog.locator('.el-pagination .el-pager li.number:visible');
      const pageCount = await pageNumbers.count();
      if (pageCount > 1) {
        const lastPage = pageNumbers.last();
        const lastPageNumber = (await lastPage.innerText()).trim();
        if (!(await lastPage.evaluate(node => node.classList.contains('active')))) {
          await lastPage.click();
          await page.waitForTimeout(2000);
        }
        log(`Centro de Download: última página selecionada (${lastPageNumber}).`);
      } else {
        log('Centro de Download: somente uma página disponível.');
      }

      latestExport = dialog.locator('.el-table__body-wrapper tbody tr').last();
      if (await latestExport.isVisible().catch(() => false)) {
        const rowText = (await latestExport.innerText()).replace(/\s+/g, ' ');
        const timeMatch = rowText.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/);
        const taskTime = timeMatch ? new Date(timeMatch[1].replace(' ', 'T')) : null;
        const completed = /\b(sucesso|success)\b/i.test(rowText);
        const candidateLink = dialog.locator('.el-table__fixed-right button[title="Download"], .el-table__fixed-right button[title="Baixar"]').last();
        if (completed && (!taskTime || taskTime >= new Date(exportStarted.getTime() - 120000)) &&
            await candidateLink.isVisible().catch(() => false)) {
          downloadLink = candidateLink;
          log(`Arquivo mais recente localizado: ${rowText.slice(0, 240)}`);
          break;
        }
        if (!completed) log(`Exportação ainda em andamento; aguardando conclusão: ${rowText.slice(0, 180)}`);
      }
      await page.waitForTimeout(7000);
    }
    if (!downloadLink) throw new Error('A exportação mais recente não ficou disponível no Centro de Download em 5 minutos.');
    log(`BOTAO DOWNLOAD: ${await downloadLink.evaluate(node => node.outerHTML)}`);
    const downloadPromise = page.waitForEvent('download', { timeout: 120000 }).catch(() => null);
    await downloadLink.click();
    await page.waitForTimeout(3000);
    log(`PAGINAS APOS DOWNLOAD: ${context.pages().map(item => item.url()).join(' | ')}`);
    const download = await downloadPromise;
    if (!download) throw new Error('O JMS não iniciou o download após clicar no arquivo mais recente.');
    const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
    const destination = path.join(downloads, `Exportar carta de porte de entrega-${stamp}.xlsx`);
    await download.saveAs(destination);
    log(`Relatório baixado: ${destination}`);
  } catch (error) {
    try {
      if (!page) throw new Error('Página do JMS não foi criada.');
      await page.screenshot({ path: path.join(logDir, 'erro-navegador.png'), fullPage: true });
      fs.writeFileSync(path.join(logDir, 'erro-pagina.html'), await page.content(), 'utf8');
      const elements = await page.locator('a, button, [role="button"], [class*="menu"], [class*="module"]').evaluateAll(nodes =>
        nodes.map((node, index) => ({
          index,
          tag: node.tagName,
          text: (node.innerText || node.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 180),
          href: node.getAttribute('href'),
          role: node.getAttribute('role'),
          className: typeof node.className === 'string' ? node.className : '',
          data: { ...node.dataset }
        })).filter(item => item.text || item.href)
      );
      fs.writeFileSync(path.join(logDir, 'elementos-pagina.json'), JSON.stringify(elements, null, 2), 'utf8');
      const visibleTexts = await page.locator('body *').evaluateAll(nodes => nodes.filter(node => {
        const text = (node.innerText || '').trim();
        if (!text || text.length > 100) return false;
        const style = getComputedStyle(node);
        if (style.display === 'none' || style.visibility === 'hidden') return false;
        return !Array.from(node.children).some(child => (child.innerText || '').trim() === text);
      }).map((node, index) => ({
        index,
        tag: node.tagName,
        text: node.innerText.trim().replace(/\s+/g, ' '),
        className: typeof node.className === 'string' ? node.className : '',
        parentClass: typeof node.parentElement?.className === 'string' ? node.parentElement.className : '',
        grandParentClass: typeof node.parentElement?.parentElement?.className === 'string' ? node.parentElement.parentElement.className : ''
      })));
      fs.writeFileSync(path.join(logDir, 'textos-visiveis.json'), JSON.stringify(visibleTexts, null, 2), 'utf8');
      log(`URL da falha: ${page.url()}`);
    } catch (diagnosticError) {
      log(`Falha ao registrar diagnóstico: ${diagnosticError.message}`);
    }
    log(`ERRO: ${error.stack || error.message}`);
    process.exitCode = 1;
  } finally {
    disconnectJmsSession(browser);
  }
})().then(() => process.exit(process.exitCode || 0), error => {
  log(`ERRO FATAL: ${error.stack || error.message}`);
  process.exit(1);
});
