const { chromium } = require('playwright-core');
const { getJmsSession, disconnectJmsSession } = require('./jms-browser-session');
const fs = require('fs');
const path = require('path');

const configFile = 'C:\\oCoffe\\config\\gestao-kpi.json';
const config = fs.existsSync(configFile)
  ? JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, '')) : {};
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
const chrome = expand(config.jmsBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = expand(config.perfilJms) || 'C:\\oCoffe\\chrome-profile';
const downloads = expand(config.downloads) || path.join(process.env.USERPROFILE, 'Downloads');
const logDir = expand(config.logDir) || 'C:\\Gestão de KPI_Operacional_v2\\Automacao';
const logFile = path.join(logDir, 'sla-navegador.log');
const jmsUrl = config.jmsUrl || 'https://jmsbr.jtjms-br.com/index';
const historyDays = 21;

fs.mkdirSync(profile, { recursive: true });
fs.mkdirSync(downloads, { recursive: true });
fs.mkdirSync(logDir, { recursive: true });
const log = message => fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`, 'utf8');
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const isoDate = date => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit'
}).format(date);

async function firstVisible(locator, description, timeout = 60000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    for (const candidate of await locator.all()) {
      if (await candidate.isVisible().catch(() => false)) return candidate;
    }
    await wait(500);
  }
  throw new Error(`${description} não foi encontrado ou não está visível.`);
}

async function clickVisibleText(page, text, exact = true) {
  const target = await firstVisible(page.getByText(text, { exact }), `O item ${text}`);
  await target.click();
}

async function setDateRange(page, start, end) {
  async function setLabeledDate(labelText, value) {
    const label = await firstVisible(page.getByText(labelText, { exact: true }), `O campo ${labelText}`);
    const input = label.locator('xpath=following::input[1]');
    await input.waitFor({ state: 'visible', timeout: 30000 });
    await input.evaluate(element => element.removeAttribute('readonly'));
    await input.click();
    await input.fill(value);
    await input.press('Enter');
    await input.blur();
    await page.waitForTimeout(500);
    const actualValue = (await input.inputValue()).slice(0, 10);
    if (actualValue !== value) throw new Error(`${labelText} deveria ser ${value}, mas ficou ${actualValue}.`);
  }

  await setLabeledDate('Data início', start);
  await setLabeledDate('data final', end);
}

(async () => {
  const today = new Date();
  // O SLA deve incluir o dia da execução. Antes, a data final era fixada em D-1,
  // fazendo uma execução no dia 27 consultar somente até o dia 26.
  const endDate = new Date(today);
  const startDate = new Date(endDate); startDate.setDate(startDate.getDate() - historyDays);
  const powerBiDate = new Date(endDate); powerBiDate.setDate(powerBiDate.getDate() - 1);
  const start = isoDate(startDate);
  const end = isoDate(endDate);
  const powerBiEnd = isoDate(powerBiDate);
  const { browser, context, page: sessionPage } = await getJmsSession({ chrome, profile, jmsUrl, log });
  let page;
  try {
    page = sessionPage;
    await page.goto(jmsUrl, { waitUntil: 'domcontentloaded' });
    const homeCards = page.locator('.grid-content.home-card');
    if (/\/login/i.test(page.url()) || !(await homeCards.first().isVisible({ timeout: 5000 }).catch(() => false))) {
      log('Aguardando login/CAPTCHA do usuário por até 10 minutos.');
      await homeCards.first().waitFor({ state: 'visible', timeout: 600000 });
    }
    if (await page.evaluate(() => localStorage.getItem('lang')) !== 'PT') {
      await page.evaluate(() => localStorage.setItem('lang', 'PT'));
      await page.reload({ waitUntil: 'domcontentloaded' });
    }

    const businessCard = homeCards.nth(7);
    await businessCard.waitFor({ state: 'visible', timeout: 60000 });
    await businessCard.click();
    await clickVisibleText(page, 'Prazo');
    await clickVisibleText(page, 'Entrega realizada');
    await clickVisibleText(page, 'Lista');
    const shippingDateOption = await firstVisible(
      page.getByText('Por data de envio', { exact: true }),
      'A opção Por data de envio'
    );
    await shippingDateOption.click();
    await setDateRange(page, start, end);
    log(`Consulta SLA Lista configurada: ${start} até ${end}; sem filtro de Base de entrega.`);

    const toolbar = page.locator('.avue-crud__left > button:visible');
    const consultButton = await firstVisible(
      toolbar.getByText('Consulta', { exact: true }),
      'O botão Consulta do SLA'
    );
    await consultButton.click();
    await page.waitForTimeout(5000);
    await page.locator('.el-loading-mask:visible').waitFor({ state: 'hidden', timeout: 60000 }).catch(() => {});
    log(`SLA consultado no JMS: ${start} até ${end}; sem filtro de Base de entrega.`);
    await clickVisibleText(page, 'Centro de download', false);
    let dialog = page.locator('.el-dialog__wrapper:visible').last();
    await dialog.waitFor({ state: 'visible', timeout: 30000 });
    let row = null;

    async function findCompletedRow(minimumTime) {
      const queryButton = dialog.getByText('Consulta', { exact: true }).first();
      if (await queryButton.isVisible().catch(() => false)) await queryButton.click();
      await page.waitForTimeout(4000);
      const rows = dialog.locator('tbody tr');
      for (let index = 0; index < await rows.count(); index++) {
        const candidate = rows.nth(index);
        const text = (await candidate.innerText()).replace(/\s+/g, ' ');
        const timeMatch = text.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/);
        const taskTime = timeMatch ? new Date(timeMatch[1].replace(' ', 'T')) : null;
        if (/Entrega realizada/i.test(text) && /Concluído|sucesso|success/i.test(text) &&
            (!taskTime || taskTime >= minimumTime)) return candidate;
      }
      return null;
    }

    await dialog.locator('.el-dialog__headerbtn').click().catch(() => page.keyboard.press('Escape'));
    const exportStarted = new Date();
    await toolbar.nth(1).click();
    await page.waitForTimeout(2500);
    await clickVisibleText(page, 'Centro de download', false);
    dialog = page.locator('.el-dialog__wrapper:visible').last();
    await dialog.waitFor({ state: 'visible', timeout: 30000 });
    const deadline = Date.now() + 15 * 60 * 1000;
    while (Date.now() < deadline) {
      row = await findCompletedRow(new Date(exportStarted.getTime() - 5000));
      if (row) break;
      await page.waitForTimeout(10000);
    }
    if (!row) throw new Error('A exportação diária do SLA não ficou concluída dentro de 15 minutos.');

    const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
    await row.locator('button, [role="button"], i').last().click();
    const download = await downloadPromise;
    const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
    const destination = path.join(downloads, `Entrega realizada(Lista)-${stamp}.xlsx`);
    await download.saveAs(destination);
    const metadata = { file: destination, startDate: start, endDate: end, powerBiDate: powerBiEnd, downloadedAt: new Date().toISOString() };
    fs.writeFileSync(path.join(logDir, 'ultimo-sla-download.json'), JSON.stringify(metadata, null, 2), 'utf8');
    log(`SLA baixado: ${destination}`);
  } catch (error) {
    log(`ERRO: ${error.stack || error.message}`);
    if (page) await page.screenshot({ path: path.join(logDir, 'erro-sla-jms.png'), fullPage: true }).catch(() => {});
    process.exitCode = 1;
  } finally {
    await disconnectJmsSession(browser);
  }
})().then(() => process.exit(process.exitCode || 0), () => process.exit(1));
