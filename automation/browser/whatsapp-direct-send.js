const { chromium } = require('playwright-core');
const fs = require('fs');

const phone = String(process.argv[2] || '').replace(/\D/g, '');
const message = process.argv[3] || '';
const configFile = 'C:\\oCoffe\\config\\gestao-kpi.json';
const logFile = 'C:\\oCoffe\\desempenho.log';
let config = {};
if (fs.existsSync(configFile)) {
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, '')); } catch (_) {}
}
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, name) => process.env[name] || `%${name}%`);
const chrome = expand(config.whatsappBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = expand(config.perfilWhatsApp) || 'C:\\oCoffe\\whatsapp-profile';
const log = text => fs.appendFileSync(logFile, `${new Date().toISOString()} ${text}\n`, 'utf8');

if (!/^\d{12,13}$/.test(phone)) throw new Error('Número de WhatsApp inválido.');
if (!message.trim()) throw new Error('Mensagem vazia.');

(async () => {
  const context = await chromium.launchPersistentContext(profile, {
    executablePath: chrome,
    headless: false,
    viewport: null,
    args: ['--start-maximized']
  });
  try {
    const page = context.pages()[0] || await context.newPage();
    const url = `https://web.whatsapp.com/send?phone=${encodeURIComponent(phone)}&text=${encodeURIComponent(message)}`;
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    const composer = page.locator('footer [contenteditable="true"]:visible').last();
    await composer.waitFor({ state: 'visible', timeout: 300000 });
    const send = page.locator('[role="button"][aria-label^="Enviar" i]:visible, [role="button"][aria-label^="Send" i]:visible, [data-icon="send"]:visible, [data-icon="wds-ic-send-filled"]:visible').last();
    await send.waitFor({ state: 'visible', timeout: 30000 });
    await send.click();
    await page.waitForTimeout(2500);
    log(`Alerta de desempenho enviado ao responsável final ${phone.slice(-4)}.`);
  } catch (error) {
    log(`ERRO no alerta: ${error.stack || error.message}`);
    process.stderr.write(`${error.stack || error.message}\n`);
    process.exitCode = 1;
  } finally {
    await context.close();
  }
})();
