const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 1024 });
  
  const filePath = 'file://' + path.join(__dirname, 'dashboard_test.html');
  await page.goto(filePath);

  const results = await page.evaluate(() => {
    const tooltipElements = Array.from(document.querySelectorAll('[data-tooltip]'));
    const issues = [];

    tooltipElements.forEach(el => {
      const rect = el.getBoundingClientRect();
      const tooltipText = el.getAttribute('data-tooltip');
      
      // Simulate tooltip appearance (approximate position)
      // Tooltips are positioned absolute, bottom: 100%, left: 50%
      // They have transform: translateX(-50%) translateY(-12px)
      
      const tooltipHeight = 40; // Estimated height including padding
      const tooltipWidth = tooltipText.length * 8; // Very rough estimate
      
      const tooltipTop = rect.top - tooltipHeight - 12;
      const tooltipLeft = rect.left + (rect.width / 2) - (tooltipWidth / 2);
      const tooltipRight = tooltipLeft + tooltipWidth;

      // Check if it goes outside viewport
      if (tooltipTop < 0) {
        issues.push(`Tooltip "${tooltipText}" might be cut off at the TOP of viewport`);
      }
      if (tooltipLeft < 0) {
        issues.push(`Tooltip "${tooltipText}" might be cut off at the LEFT of viewport`);
      }
      if (tooltipRight > window.innerWidth) {
        issues.push(`Tooltip "${tooltipText}" might be cut off at the RIGHT of viewport`);
      }

      // Check if any parent has overflow: hidden that might clip it
      let parent = el.parentElement;
      while (parent && parent !== document.body) {
        const style = window.getComputedStyle(parent);
        if (style.overflow === 'hidden' || style.overflowX === 'hidden' || style.overflowY === 'hidden') {
          // Check if tooltip boundaries are outside parent boundaries
          const pRect = parent.getBoundingClientRect();
          if (tooltipTop < pRect.top) {
            issues.push(`Tooltip "${tooltipText}" is clipped by parent ${parent.tagName}.${parent.className} (overflow: hidden)`);
          }
        }
        parent = parent.parentElement;
      }
    });

    return issues;
  });

  if (results.length > 0) {
    console.log('Potential tooltip issues found:');
    results.forEach(msg => console.log('  ' + msg));
    process.exit(1);
  } else {
    console.log('No tooltip clipping issues detected.');
  }

  await browser.close();
})();
