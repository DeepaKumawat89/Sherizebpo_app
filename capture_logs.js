const puppeteer = require('puppeteer');

(async () => {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    
    page.on('console', msg => {
        console.log(`[PAGE LOG] ${msg.type().toUpperCase()}: ${msg.text()}`);
    });
    
    page.on('pageerror', error => {
        console.log(`[PAGE ERROR]: ${error.message}`);
    });

    page.on('requestfailed', request => {
        console.log(`[REQUEST FAILED]: ${request.url()} - ${request.failure().errorText}`);
    });

    console.log('Navigating to https://human-cold-bpo.web.app...');
    await page.goto('https://human-cold-bpo.web.app', { waitUntil: 'networkidle0', timeout: 30000 });
    
    console.log('Waiting another 5 seconds...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    console.log('Done.');
    await browser.close();
})();
