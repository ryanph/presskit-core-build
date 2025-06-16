#!/usr/bin/env node
const chromeLauncher = require('chrome-launcher');
const CDP = require('chrome-remote-interface');

(async function() {
  const chrome = await chromeLauncher.launch({
    chromeFlags: ['--remote-debugging-port=0']
  });
  // ensure the Chrome process is always killed when this script exits
  process.on('exit', () => {
    if (chrome && chrome.process && !chrome.process.killed) {
      chrome.process.kill();
    }
  });
  // allow SIGTERM to cleanly exit (triggering the exit handler above)
  process.on('SIGTERM', () => process.exit(0));
  const client = await CDP({port: chrome.port});
  const {Runtime, Page} = client;
  await Promise.all([Runtime.enable(), Page.enable()]);
  Page.loadEventFired(() => console.log('PAGE: load event fired'));
  await Page.navigate({url: 'http://localhost:8080/wp-admin/'});
  console.log('PAGE: navigating to http://localhost:8080/wp-admin/');
  Runtime.consoleAPICalled(({type, args}) => {
    const texts = args.map(arg => arg.value !== undefined ? arg.value : arg.description);
    console.log(`${type.toUpperCase()}: ${texts.join(' ')}`);
  });
  process.on('SIGINT', async () => {
    await client.close();
    await chrome.kill();
    process.exit();
  });
})();