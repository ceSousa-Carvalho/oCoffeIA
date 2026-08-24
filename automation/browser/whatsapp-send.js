const { chromium } = require('playwright-core');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const imagePath = process.argv[2];
const groupName = process.argv[3] || 'Entregadores J&T - THE';
const message = process.argv[4] || `@all Segue a parcial das ${new Date().getHours()}h.\n\nAtualização gerada pelo Assistente oCoffeIA`;
const dryRun = process.argv[5] === '--dry-run';
const diagnose = process.argv[5] === '--diagnose';
const diagnoseGroup = process.argv[5] === '--diagnose-group';
const diagnoseAttach = process.argv[5] === '--diagnose-attach';
const diagnosePreview = process.argv[5] === '--diagnose-preview';
const diagnoseMention = process.argv[5] === '--diagnose-mention';
const configFile = 'C:\\oCoffe\\config\\gestao-kpi.json';
let config = {};
if (fs.existsSync(configFile)) {
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8').replace(/^\uFEFF/, '')); } catch (_) {}
}
const expand = value => String(value || '').replace(/%([^%]+)%/g, (_, name) => process.env[name] || `%${name}%`);
const chrome = expand(config.whatsappBrowser || config.chrome) || 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const profile = expand(config.perfilWhatsApp) || 'C:\\oCoffe\\whatsapp-profile';
const logFile = 'C:\\oCoffe\\whatsapp.log';
const cdpEndpoint = 'http://127.0.0.1:17321';

function log(text) {
  fs.appendFileSync(logFile, `${new Date().toISOString()} ${text}\n`, 'utf8');
}

const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function connectToWhatsAppChrome() {
  try {
    return await chromium.connectOverCDP(cdpEndpoint, { timeout: 1500 });
  } catch (_) {
    return null;
  }
}

async function getWhatsAppChrome() {
  let browser = await connectToWhatsAppChrome();
  if (browser) {
    log('Janela existente do WhatsApp Web detectada e reutilizada.');
    return browser;
  }

  const child = spawn(chrome, [
    `--user-data-dir=${profile}`,
    '--remote-debugging-address=127.0.0.1',
    '--remote-debugging-port=17321',
    '--start-maximized',
    '--no-first-run',
    'https://web.whatsapp.com/'
  ], { detached: true, stdio: 'ignore', windowsHide: false });
  child.unref();

  for (let attempt = 0; attempt < 30; attempt += 1) {
    await wait(500);
    browser = await connectToWhatsAppChrome();
    if (browser) {
      log('Nova janela controlada do WhatsApp Web aberta.');
      return browser;
    }
  }
  throw new Error('Não foi possível abrir ou conectar à janela do WhatsApp Web.');
}

if (!imagePath || !fs.existsSync(imagePath)) {
  throw new Error(`Imagem não encontrada: ${imagePath || '(não informada)'}`);
}

(async () => {
  const browser = await getWhatsAppChrome();
  const context = browser.contexts()[0];
  if (!context) throw new Error('A janela do WhatsApp Web não possui um contexto de navegador disponível.');
  let page;
  try {
    const whatsappPages = context.pages().filter(candidate => candidate.url().startsWith('https://web.whatsapp.com/'));
    page = whatsappPages[0] || context.pages()[0] || await context.newPage();
    for (const duplicate of whatsappPages.slice(1)) {
      await duplicate.close().catch(() => {});
    }
    if (whatsappPages.length > 1) {
      log(`${whatsappPages.length - 1} aba(s) duplicada(s) do WhatsApp fechada(s).`);
    }
    if (!page.url().startsWith('https://web.whatsapp.com/')) {
      await page.goto('https://web.whatsapp.com/', { waitUntil: 'domcontentloaded' });
    } else {
      await page.bringToFront();
    }
    log('WhatsApp Web aberto; aguardando a sessão do usuário.');

    const continueButton = page.getByRole('button', { name: /^(Continuar|Continue)$/i }).first();
    if (await continueButton.isVisible({ timeout: 5000 }).catch(() => false)) {
      await continueButton.click();
    }

    const staleMediaEditor = page.locator('button[aria-label="Contorno"]:visible, button[aria-label="Outline"]:visible, [data-icon="scissors"]:visible').first();
    if (await staleMediaEditor.isVisible().catch(() => false)) {
      const stalePreviewClose = page.getByRole('button', { name: /^(Fechar|Close)$/i }).first();
      if (await stalePreviewClose.isVisible().catch(() => false)) {
        await stalePreviewClose.evaluate(element => element.click());
      }
      await page.waitForTimeout(500);
    }
    await page.keyboard.press('Escape').catch(() => {});

    if (diagnose) {
      await page.waitForTimeout(15000);
      const controls = await page.locator('input, textarea, [contenteditable="true"]').evaluateAll(elements =>
        elements.map(element => ({
          tag: element.tagName,
          ariaLabel: element.getAttribute('aria-label'),
          placeholder: element.getAttribute('placeholder'),
          dataTab: element.getAttribute('data-tab'),
          role: element.getAttribute('role'),
          contenteditable: element.getAttribute('contenteditable'),
          visible: Boolean(element.offsetWidth || element.offsetHeight || element.getClientRects().length)
        }))
      );
      process.stdout.write(`${JSON.stringify(controls, null, 2)}\n`);
      return;
    }

    const searchPreferred = page.locator('input[data-tab="3"]:visible').first();
    const searchByLabel = page.locator('input[aria-label*="Pesquisar" i], input[aria-label*="Search" i]').first();
    const anyEditable = page.locator('#side input[role="textbox"]:visible').first();
    await anyEditable.waitFor({ state: 'visible', timeout: 300000 });
    const search = await searchPreferred.isVisible().catch(() => false)
      ? searchPreferred
      : (await searchByLabel.isVisible().catch(() => false) ? searchByLabel : anyEditable);
    await search.click();
    await search.press('Control+A');
    await search.fill(groupName);

    const group = page.locator('#pane-side').getByText(groupName, { exact: true }).first();
    await group.waitFor({ state: 'visible', timeout: 30000 });
    await group.click();
    await page.waitForTimeout(1500);

    const conversationTitle = page.locator('header').getByText(groupName, { exact: true }).first();
    if (!(await conversationTitle.isVisible({ timeout: 10000 }).catch(() => false))) {
      throw new Error(`Não foi possível confirmar o grupo selecionado: ${groupName}`);
    }

    if (diagnoseAttach) {
      await page.getByRole('button', { name: /^(Anexar|Attach)$/i }).click();
      await page.waitForTimeout(1000);
    }

    if (diagnoseGroup || diagnoseAttach) {
      const controls = await page.locator('button, [role="button"], input[type="file"]').evaluateAll(elements =>
        elements.map(element => ({
          tag: element.tagName,
          text: (element.textContent || '').trim().slice(0, 80),
          ariaLabel: element.getAttribute('aria-label'),
          title: element.getAttribute('title'),
          dataIcon: element.getAttribute('data-icon') || element.querySelector('[data-icon]')?.getAttribute('data-icon'),
          type: element.getAttribute('type'),
          accept: element.getAttribute('accept'),
          visible: Boolean(element.offsetWidth || element.offsetHeight || element.getClientRects().length)
        })).filter(item => item.visible || item.type === 'file')
      );
      process.stdout.write(`${JSON.stringify(controls, null, 2)}\n`);
      return;
    }

    await page.getByRole('button', { name: /^(Anexar|Attach)$/i }).click();
    const photosAndVideos = page.getByRole('menuitem', { name: /^(Fotos e vídeos|Photos & videos)$/i });
    await photosAndVideos.waitFor({ state: 'visible', timeout: 10000 });
    const fileChooserPromise = page.waitForEvent('filechooser', { timeout: 10000 });
    await photosAndVideos.click();
    const fileChooser = await fileChooserPromise;
    await fileChooser.setFiles(imagePath);

    if (diagnoseMention) {
      const mentionBox = page.locator('[contenteditable="true"][aria-label="Digite uma mensagem"]').last();
      await mentionBox.waitFor({ state: 'visible', timeout: 30000 });
      await mentionBox.fill('@');
      await page.waitForTimeout(1500);
      const suggestions = await page.locator('[role="listbox"], [role="option"], [role="button"], [aria-label]').evaluateAll(elements =>
        elements.map(element => ({
          text: (element.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 120),
          role: element.getAttribute('role'),
          ariaLabel: element.getAttribute('aria-label'),
          visible: Boolean(element.offsetWidth || element.offsetHeight || element.getClientRects().length)
        })).filter(item => item.visible && (item.text || item.ariaLabel))
      );
      process.stdout.write(`${JSON.stringify(suggestions.slice(-40), null, 2)}\n`);
      await page.screenshot({ path: 'C:\\oCoffe\\whatsapp-mencao-teste.png', fullPage: true });
      return;
    }

    if (diagnosePreview) {
      await page.waitForTimeout(2000);
      const controls = await page.locator('button, [role="button"], input, textarea, [contenteditable="true"]').evaluateAll(elements =>
        elements.map(element => ({
          tag: element.tagName,
          text: (element.textContent || '').trim().slice(0, 80),
          ariaLabel: element.getAttribute('aria-label'),
          placeholder: element.getAttribute('placeholder'),
          dataIcon: element.getAttribute('data-icon') || element.querySelector('[data-icon]')?.getAttribute('data-icon'),
          role: element.getAttribute('role'),
          visible: Boolean(element.offsetWidth || element.offsetHeight || element.getClientRects().length)
        })).filter(item => item.visible)
      );
      process.stdout.write(`${JSON.stringify(controls, null, 2)}\n`);
      return;
    }

    const sendIcon = page.locator('[role="button"][aria-label^="Enviar "][aria-label*="item selecionado" i]:visible, [role="button"][aria-label^="Send "][aria-label*="item selected" i]:visible').last();
    await sendIcon.waitFor({ state: 'visible', timeout: 30000 });
    const captionPreferred = page.locator('[contenteditable="true"][role="textbox"][aria-label="Digite uma mensagem"], [contenteditable="true"][role="textbox"][aria-label="Type a message" i], [contenteditable="true"][aria-label*="legenda" i], [contenteditable="true"][aria-label*="caption" i]').first();
    const caption = await captionPreferred.isVisible().catch(() => false)
      ? captionPreferred
      : page.locator('div[contenteditable="true"]:visible').last();
    await caption.click();
    await caption.fill(message);
    if (dryRun) {
      await page.screenshot({ path: 'C:\\oCoffe\\whatsapp-preparo-teste.png', fullPage: true });
      log(`Teste de preparação concluído sem envio: ${path.basename(imagePath)}`);
      const closePreview = page.getByRole('button', { name: /^(Fechar|Close)$/i }).first();
      if (await closePreview.isVisible().catch(() => false)) {
        await closePreview.evaluate(element => element.click());
      }
      return;
    }
    await sendIcon.click();
    await page.waitForTimeout(3000);
    log(`Parcial enviada ao grupo ${groupName}: ${path.basename(imagePath)}`);
  } catch (error) {
    log(`ERRO: ${error.stack || error.message}`);
    process.stderr.write(`${error.stack || error.message}\n`);
    if (page) {
      await page.screenshot({ path: 'C:\\oCoffe\\whatsapp-erro.png', fullPage: true }).catch(() => {});
    }
    process.exitCode = 1;
  } finally {
    if (browser.isConnected()) browser._connection.close();
  }
})().then(() => process.exit(process.exitCode || 0));
