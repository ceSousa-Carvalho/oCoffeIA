const { chromium } = require('playwright-core');
const { getJmsSession, disconnectJmsSession } = require('./jms-browser-session');
const fs = require('fs');
const path = require('path');

const root = 'C:\\oCoffe';
const config = JSON.parse(fs.readFileSync(path.join(root, 'config', 'gestao-kpi.json'), 'utf8').replace(/^\uFEFF/, ''));
const inputFile = process.argv[2];
if (!inputFile || !fs.existsSync(inputFile)) throw new Error('Arquivo JSON com pedidos não informado.');
const input = JSON.parse(fs.readFileSync(inputFile, 'utf8').replace(/^\uFEFF/, ''));
const orders = [...new Set((input.orders || []).map(String).map(value => value.trim()).filter(Boolean))];
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, key) => process.env[key] || `%${key}%`);
const profile = expand(config.perfilJms) || path.join(root, 'chrome-profile');
const chrome = expand(config.jmsBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const logDir = expand(config.logDir) || path.join(root, 'logs');
const resultFile = path.join(logDir, 'expedido-rastreamento.json');
const logFile = path.join(logDir, 'expedido.log');
const configuredBase = String(process.env.OCOFFE_EXPEDIDO_BASE || config.expedidoBaseSigla || '').trim();
const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Z0-9]/gi, '').toUpperCase();
const baseKey = normalize(configuredBase);
const log = message => fs.appendFileSync(logFile, `${new Date().toISOString()} ${message}\n`, 'utf8');
const escapeRegex = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

async function waitForLogin(page) {
  const cards = page.locator('.grid-content.home-card');
  if (/\/login/i.test(page.url()) || !(await cards.first().isVisible({ timeout: 5000 }).catch(() => false))) {
    log('Login ou CAPTCHA solicitado durante rastreamento.');
    await cards.first().waitFor({ state: 'visible', timeout: 600000 });
  }
  if (await page.evaluate(() => localStorage.getItem('lang')) !== 'PT') {
    await page.evaluate(() => localStorage.setItem('lang', 'PT'));
    await page.reload({ waitUntil: 'domcontentloaded' });
  }
  return cards;
}

async function putOrders(page, batch) {
  await page.getByText(/Correspond[eê]ncia inteligente/i, { exact: false }).first().click();
  const option = page.getByText(/Correspond[eê]ncia inteligente/i, { exact: true }).last();
  if (await option.isVisible().catch(() => false)) await option.click();
  const target = page.locator('textarea:visible, [contenteditable="true"]:visible, input:visible').filter({ hasNot: page.locator('[type="date"]') }).first();
  await target.click();
  await target.fill(batch.join('\n')).catch(async () => {
    await page.keyboard.press('Control+A');
    await page.keyboard.type(batch.join('\n'));
  });
  await page.getByText('Consulta', { exact: true }).first().click();
  await page.waitForTimeout(5000);
}

async function getLastPodRow(page, order) {
  const item = page.getByText(new RegExp(`^${escapeRegex(order)}$`)).last();
  if (await item.isVisible().catch(() => false)) { await item.click(); await page.waitForTimeout(800); }
  const podTitle = page.getByText(/Registro POD/i, { exact: false }).last();
  await podTitle.waitFor({ state: 'visible', timeout: 20000 });
  const section = podTitle.locator('xpath=ancestor::*[contains(@class,"el-collapse-item") or contains(@class,"panel")][1]');
  let rows = section.locator('tbody tr');
  if (await rows.count() === 0) {
    await podTitle.click();
    await page.waitForTimeout(700);
    rows = section.locator('tbody tr');
  }
  if (await rows.count() === 0) rows = podTitle.locator('xpath=following::table[1]//tbody/tr');
  if (await rows.count() === 0) {
    const allRows = page.locator('tbody tr');
    const trackingRows = [];
    for (let i = 0; i < await allRows.count(); i++) {
      const text = await allRows.nth(i).innerText();
      if (/\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}/.test(text)) trackingRows.push(allRows.nth(i));
    }
    if (!trackingRows.length) return '';
    return (await trackingRows[trackingRows.length - 1].innerText()).replace(/\s+/g, ' ').trim();
  }
  return (await rows.last().innerText()).replace(/\s+/g, ' ').trim();
}

function classify(order, lastRow) {
  const normalized = normalize(lastRow);
  const problematic = /problem|anomali|avaria|extravio|nao.chegou|não.chegou/i.test(lastRow);
  const received = /chegou|recebid|recepc|armazen|instalad/i.test(lastRow);
  const dispatched = /sendo enviada|enviada,?\s*para|carregad/i.test(lastRow);
  const targetsBase = baseKey && normalized.includes(baseKey);
  const trip = (lastRow.match(/\b(?:SR|SE)[A-Z0-9-]{5,}\b/i) || [])[0] || '';
  const eligible = Boolean(dispatched && targetsBase && !received && !problematic);
  return { order, eligible, tripId: trip.toUpperCase(), lastRow, reason: eligible ? 'expedido_para_base' : problematic ? 'problematico' : received ? 'recebido' : 'ultimo_evento_nao_elegivel' };
}

(async () => {
  if (!baseKey) throw new Error('Configure a sigla da base do líder.');
  const jmsUrl = config.jmsUrl || 'https://jmsbr.jtjms-br.com/index';
  const { browser, context, page: sessionPage } = await getJmsSession({ chrome, profile, jmsUrl, log });
  let page;
  const inspected = [];
  try {
    page = sessionPage;
    await page.goto(jmsUrl, { waitUntil: 'domcontentloaded' });
    const cards = await waitForLogin(page);
    await cards.nth(1).click();
    await page.getByText('Consulta do pacote', { exact: false }).first().click();
    await page.getByText('Rastreamento do pacote', { exact: false }).last().click();

    for (let offset = 0; offset < orders.length; offset += 1000) {
      const batch = orders.slice(offset, offset + 1000);
      await putOrders(page, batch);
      for (const order of batch) {
        try { inspected.push(classify(order, await getLastPodRow(page, order))); }
        catch (error) { inspected.push({ order, eligible: false, tripId: '', lastRow: '', reason: `falha_consulta: ${error.message}` }); }
      }
      const clear = page.getByText('Limpar', { exact: true }).first();
      if (await clear.isVisible().catch(() => false)) await clear.click();
    }
    const valid = inspected.filter(item => item.eligible);
    const firstTripId = valid.map(item => item.tripId).find(Boolean) || 'SEM_ID_VIAGEM';
    fs.writeFileSync(resultFile, JSON.stringify({ generatedAt: new Date().toISOString(), base: configuredBase, firstTripId, validOrders: valid.map(item => item.order), inspected }, null, 2), 'utf8');
    log(`Rastreamento concluído: ${valid.length}/${orders.length} pedidos elegíveis; viagem ${firstTripId}.`);
  } catch (error) {
    log(`ERRO RASTREAMENTO: ${error.stack || error.message}`);
    if (page) await page.screenshot({ path: path.join(logDir, 'erro-expedido-rastreamento.png'), fullPage: true }).catch(() => {});
    process.exitCode = 1;
  } finally { disconnectJmsSession(browser); }
})().then(() => process.exit(process.exitCode || 0), () => process.exit(1));
