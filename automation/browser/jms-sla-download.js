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
const historyDays = Math.max(20, Number(config.slaDiasHistorico || 27));

fs.mkdirSync(profile, { recursive: true });
fs.mkdirSync(downloads, { recursive: true });
fs.mkdirSync(logDir, { recursive: true });
const log = message => fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`, 'utf8');
const isoDate = date => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit'
}).format(date);

async function setDateRange(page, start, end) {
  const changed = await page.locator('input').evaluateAll((inputs, values) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    const dateInputs = inputs.filter(input => /^\d{4}-\d{2}-\d{2}/.test(input.value));
    if (dateInputs.length < 2) return 0;
    [values.start, values.end].forEach((value, index) => {
      setter.call(dateInputs[index], value);
      dateInputs[index].dispatchEvent(new Event('input', { bubbles: true }));
      dateInputs[index].dispatchEvent(new Event('change', { bubbles: true }));
      dateInputs[index].dispatchEvent(new Event('blur', { bubbles: true }));
    });
    return 2;
  }, { start, end });
  if (changed !== 2) throw new Error('Os campos Data início/Data final do SLA não foram encontrados.');
}

(async () => {
  const today = new Date();
  const endDate = new Date(today); endDate.setDate(endDate.getDate() - 1);
  const startDate = new Date(today); startDate.setDate(startDate.getDate() - historyDays);
  const start = isoDate(startDate);
  const end = isoDate(endDate);
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
    await page.getByText('Prazo', { exact: true }).first().click();
    await page.getByText('Entrega realizada', { exact: true }).last().click();
    await page.getByText('Por data de envio', { exact: false }).first().click();
    await setDateRange(page, start, end);
    log(`Consulta SLA configurada: ${start} até ${end}.`);

    const toolbar = page.locator('.avue-crud__left > button:visible');
    await toolbar.nth(0).click();
    await page.waitForTimeout(5000);
    await page.getByText('Centro de download', { exact: false }).first().click();
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

    const startOfToday = new Date(); startOfToday.setHours(0, 0, 0, 0);
    row = await findCompletedRow(startOfToday);
    if (row) {
      log('Reutilizando a exportação de Entrega realizada já concluída hoje.');
    } else {
      await dialog.locator('.el-dialog__headerbtn').click().catch(() => page.keyboard.press('Escape'));
      const exportStarted = new Date();
      await toolbar.nth(1).click();
      await page.waitForTimeout(2500);
      await page.getByText('Centro de download', { exact: false }).first().click();
      dialog = page.locator('.el-dialog__wrapper:visible').last();
      await dialog.waitFor({ state: 'visible', timeout: 30000 });
      const deadline = Date.now() + 15 * 60 * 1000;
      while (Date.now() < deadline) {
        row = await findCompletedRow(new Date(exportStarted.getTime() - 120000));
        if (row) break;
        await page.waitForTimeout(10000);
      }
    }
    if (!row) throw new Error('A exportação diária do SLA não ficou concluída dentro de 15 minutos.');

    const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
    await row.locator('button, [role="button"], i').last().click();
    const download = await downloadPromise;
    const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
    const destination = path.join(downloads, `Entrega realizada(Lista)-${stamp}.xlsx`);
    await download.saveAs(destination);
    const metadata = { file: destination, startDate: start, endDate: end, downloadedAt: new Date().toISOString() };
    fs.writeFileSync(path.join(logDir, 'ultimo-sla-download.json'), JSON.stringify(metadata, null, 2), 'utf8');
    log(`SLA baixado: ${destination}`);
  } catch (error) {
    log(`ERRO: ${error.stack || error.message}`);
    if (page) await page.screenshot({ path: path.join(logDir, 'erro-sla-jms.png'), fullPage: true }).catch(() => {});
    process.exitCode = 1;
  } finally {
    disconnectJmsSession(browser);
  }
})().then(() => process.exit(process.exitCode || 0), () => process.exit(1));
