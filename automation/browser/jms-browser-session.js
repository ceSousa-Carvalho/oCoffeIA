const { chromium } = require('playwright-core');
const { spawn } = require('child_process');

const cdpEndpoint = 'http://127.0.0.1:17322';
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function connect() {
  try {
    return await chromium.connectOverCDP(cdpEndpoint, { timeout: 1500 });
  } catch (_) {
    return null;
  }
}

async function getJmsSession({ chrome, profile, jmsUrl, log }) {
  let browser = await connect();
  if (browser) {
    log('Janela existente do JMS detectada; reutilizando a sessão autenticada.');
  } else {
    const child = spawn(chrome, [
      `--user-data-dir=${profile}`,
      '--remote-debugging-address=127.0.0.1',
      '--remote-debugging-port=17322',
      '--start-maximized',
      '--no-first-run',
      jmsUrl
    ], { detached: true, stdio: 'ignore', windowsHide: false });
    child.unref();

    for (let attempt = 0; attempt < 30; attempt += 1) {
      await wait(500);
      browser = await connect();
      if (browser) break;
    }
    if (!browser) throw new Error('Não foi possível abrir ou conectar à janela do JMS.');
    log('Nova janela controlada do JMS aberta; a sessão será preservada.');
  }

  const context = browser.contexts()[0];
  if (!context) throw new Error('A janela do JMS não possui um contexto de navegador disponível.');
  const page = context.pages().find(candidate => /jtjms-br\.com/i.test(candidate.url())) ||
    context.pages()[0] || await context.newPage();
  await page.bringToFront();
  return { browser, context, page };
}

async function disconnectJmsSession(browser) {
  if (!browser || !browser.isConnected()) return;
  // O perfil preserva cookies e login no disco. Encerrar o Chrome controlado
  // após cada operação libera memória sem exigir novo login na próxima abertura.
  await browser.close().catch(() => {
    if (browser.isConnected()) browser._connection.close();
  });
}

module.exports = { getJmsSession, disconnectJmsSession };
