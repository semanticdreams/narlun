async function dispatchInstallPrompt(page, { outcome = 'accepted' } = {}) {
  await page.evaluate((promptOutcome) => {
    if (typeof window.__narlunSimulateInstallPrompt !== 'function') {
      throw new Error('Install prompt simulation hook is unavailable');
    }
    window.__narlunInstallPromptCalls = 0;
    window.__narlunSimulateInstallPrompt(promptOutcome);
  }, outcome);
}

async function installPromptCallCount(page) {
  return page.evaluate(() => window.__narlunInstallPromptCalls || 0);
}

module.exports = {
  dispatchInstallPrompt,
  installPromptCallCount,
};
