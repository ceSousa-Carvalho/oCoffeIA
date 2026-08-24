const { chromium } = require('playwright-core');
const { getJmsSession, disconnectJmsSession } = require('./jms-browser-session');
const fs = require('fs');
const path = require('path');

const root = 'C:\\oCoffe';
const configFile = path.join(root, 'config', 'gestao-kpi.json');
const config = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, ''));
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
const chrome = expand(config.jmsBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = expand(config.perfilJms) || path.join(root, 'chrome-profile');
const downloads = expand(config.downloads) || path.join(process.env.USERPROFILE, 'Downloads');
const logDir = expand(config.logDir) || path.join(root, 'logs');
const base = String(process.env.OCOFFE_EXPEDIDO_BASE || config.expedidoBaseSigla || '').trim();
const metadataFile = path.join(logDir, 'expedido-export.json');
const logFile = path.join(logDir, 'expedido.log');

fs.mkdirSync(downloads, { recursive: true });
fs.mkdirSync(logDir, { recursive: true });
const log = message => fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`, 'utf8');
const iso = date => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit'
}).format(date);

async function waitForLogin(page) {
  const cards = page.locator('.grid-content.home-card');
  if (/\/login/i.test(page.url()) || !(await cards.first().isVisible({ timeout: 5000 }).catch(() => false))) {
    log('Login ou CAPTCHA solicitado. Aguardando o líder por até 10 minutos.');
    await cards.first().waitFor({ state: 'visible', timeout: 600000 });
  }
  if (await page.evaluate(() => localStorage.getItem('lang')) !== 'PT') {
    await page.evaluate(() => localStorage.setItem('lang', 'PT'));
    await page.reload({ waitUntil: 'domcontentloaded' });
  }
  return cards;
}

async function setDateRange(page, start, end) {
  const changed = await page.locator('input').evaluateAll((inputs, values) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    const dateInputs = inputs.filter(input => /^\d{4}-\d{2}-\d{2}/.test(input.value));
    if (dateInputs.length < 2) return 0;
    [values.start, values.end].forEach((value, index) => {
      setter.call(dateInputs[index], value);
      for (const type of ['input', 'change', 'blur']) inputEvent(dateInputs[index], type);
    });
    function inputEvent(input, type) { input.dispatchEvent(new Event(type, { bubbles: true })); }
    return 2;
  }, { start, end });
  if (changed !== 2) throw new Error('Não encontrei os campos Data inicial e Data final.');
}

async function fillArrivalStation(page, value) {
  if (!value) throw new Error('Configure a sigla/base do líder antes de executar.');
  const label = page.getByText(/Esta[cç][aã]o de chegada/i).first();
  const box = label.locator('xpath=following::input[1]');
  await box.fill(value);
  await page.waitForTimeout(700);
  const option = page.getByText(new RegExp(value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i')).last();
  if (await option.isVisible().catch(() => false)) await option.click();
  else await box.press('Enter');
}

async function newestDownloadRow(page, dialog, minimumTime) {
  const query = dialog.getByText('Consulta', { exact: true }).first();
  if (await query.isVisible().catch(() => false)) await query.click();
  await page.waitForTimeout(2500);

  const candidates = [];
  const pageButtons = dialog.locator('.el-pagination .el-pager li.number:visible');
  const count = await pageButtons.count();
  const pages = count ? await pageButtons.allTextContents() : ['1'];
  for (const pageNumber of pages) {
    if (count) {
      const button = dialog.locator('.el-pagination .el-pager li.number:visible').filter({ hasText: new RegExp(`^${pageNumber.trim()}$`) }).first();
      if (await button.isVisible().catch(() => false)) { await button.click(); await page.waitForTimeout(1200); }
    }
    const rows = dialog.locator('.el-table__body-wrapper tbody tr');
    for (let index = 0; index < await rows.count(); index++) {
      const row = rows.nth(index);
      const text = (await row.innerText()).replace(/\s+/g, ' ');
      const match = text.match(/(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/);
      const taskTime = match ? new Date(match[1].replace(' ', 'T')) : null;
      if (/sucesso|success|conclu[ií]do/i.test(text) && (!taskTime || taskTime >= minimumTime)) {
        candidates.push({ row, text, time: taskTime ? taskTime.getTime() : 0 });
      }
    }
  }
  candidates.sort((a, b) => b.time - a.time);
  return candidates[0] || null;
}

(async () => {
  if (!base) throw new Error('A configuração expedidoBaseSigla está vazia.');
  const now = new Date();
  const previous = new Date(now); previous.setDate(previous.getDate() - 1);
  const start = iso(previous), end = iso(now);
  const jmsUrl = config.jmsUrl || 'https://jmsbr.jtjms-br.com/index';
  const { browser, context, page: sessionPage } = await getJmsSession({ chrome, profile, jmsUrl, log });
  let page;
  try {
    page = sessionPage;
    await page.goto(jmsUrl, { waitUntil: 'domcontentloaded' });
    const cards = await waitForLogin(page);
    await cards.nth(1).click();
    await page.getByText('Monitoramento de dados', { exact: false }).first().click();
    await page.getByText(/Monitoramento de tipagem de recebimento/i, { exact: false }).last().click();
    await setDateRange(page, start, end);
    await fillArrivalStation(page, base);
    await page.getByText('Consulta', { exact: true }).first().click();
    await page.waitForTimeout(5000);

    const row = page.locator('tbody tr').filter({ hasText: start }).first();
    if (!(await row.isVisible().catch(() => false))) throw new Error(`A linha do dia anterior (${start}) não foi encontrada no Resumo.`);
    const headers = await page.locator('thead th').allTextContents();
    const totalIndex = headers.findIndex(value => /N[uú]mero total de encomendas/i.test(value));
    if (totalIndex < 0) throw new Error('A coluna Número total de encomendas não foi encontrada.');
    const totalCell = row.locator('td').nth(totalIndex);
    const totalText = (await totalCell.innerText()).replace(/\D/g, '');
    if (!totalText || Number(totalText) === 0) {
      fs.writeFileSync(metadataFile, JSON.stringify({ noOrders: true, startDate: start, endDate: end, total: 0 }, null, 2));
      log(`Nenhuma encomenda encontrada para ${start}.`);
      return;
    }
    await totalCell.click();
    await page.getByText('Lista', { exact: true }).first().click().catch(() => {});
    await page.waitForTimeout(2500);
    const exportStarted = new Date();
    await page.getByText('Exportação', { exact: true }).first().click();
    await page.waitForTimeout(2000);
    await page.getByText('Centro de download', { exact: false }).first().click();
    const dialog = page.locator('.el-dialog__wrapper:visible').last();
    await dialog.waitFor({ state: 'visible', timeout: 30000 });

    let candidate = null;
    const deadline = Date.now() + 15 * 60 * 1000;
    while (Date.now() < deadline) {
      candidate = await newestDownloadRow(page, dialog, new Date(exportStarted.getTime() - 120000));
      if (candidate) break;
      await page.waitForTimeout(8000);
    }
    if (!candidate) throw new Error('O arquivo exportado não ficou disponível no Centro de download em 15 minutos.');
    const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
    await candidate.row.locator('button, a, [role="button"], i').last().click();
    const download = await downloadPromise;
    const stamp = new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14);
    const destination = path.join(downloads, `Monitoramento-tipagem-recebimento-${stamp}.xlsx`);
    await download.saveAs(destination);
    const metadata = { noOrders: false, file: destination, startDate: start, endDate: end, total: Number(totalText), base, downloadedAt: new Date().toISOString() };
    fs.writeFileSync(metadataFile, JSON.stringify(metadata, null, 2), 'utf8');
    log(`Exportação baixada: ${destination}`);
  } catch (error) {
    log(`ERRO EXPORTAÇÃO: ${error.stack || error.message}`);
    if (page) await page.screenshot({ path: path.join(logDir, 'erro-expedido-export.png'), fullPage: true }).catch(() => {});
    process.exitCode = 1;
  } finally { disconnectJmsSession(browser); }
})().then(() => process.exit(process.exitCode || 0), () => process.exit(1));
