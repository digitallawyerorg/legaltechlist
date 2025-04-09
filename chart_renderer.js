const puppeteer = require('puppeteer');

async function renderChart(htmlContent) {
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    try {
        const page = await browser.newPage();
        await page.setViewport({ width: 800, height: 400 });
        await page.setContent(htmlContent);

        // Wait for the chart to be rendered
        await page.waitForSelector('canvas');

        // Take a screenshot of the chart
        const element = await page.$('canvas');
        await element.screenshot({
            path: 'chart.png'
        });

        console.log('Chart rendered successfully');
    } catch (error) {
        console.error('Error rendering chart:', error);
        process.exit(1);
    } finally {
        await browser.close();
    }
}

// Get HTML content from stdin
let htmlContent = '';
process.stdin.on('data', chunk => {
    htmlContent += chunk;
});

process.stdin.on('end', () => {
    renderChart(htmlContent);
});
