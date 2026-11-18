// Drive the installed native WebView2, not a separately launched browser.
import { chromium } from 'playwright-core';
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
const phase=process.argv[2];
try {
  let browser;
  for(let i=0;i<75&&!browser;i++) {
    try { browser=await chromium.connectOverCDP('http://127.0.0.1:19222',{timeout:1200}); }
    catch { await new Promise(r=>setTimeout(r,1000)); }
  }
  assert(browser,'Installed WebView2 did not open');
  const context=browser.contexts()[0];
  const page=context.pages()[0] || await context.waitForEvent('page');
  await page.waitForURL('http://127.0.0.1:48765/**',{timeout:60000});
  await page.evaluate(()=>{localStorage.setItem('opendirector.modelSetup.v1','dismissed');localStorage.setItem('opendirector.locale.v1','zh-CN');});
  await page.reload();
  await page.getByText('已保存到本机',{exact:true}).waitFor();
  assert.equal((await fetch('http://127.0.0.1:48765/api/health',{headers:{'X-OpenDirector-Request':'1'}})).status,403);
  const nodes=page.locator('.react-flow__node');
  if(phase==='create') {
    await page.getByRole('button',{name:'添加视频',exact:true}).click();
    await nodes.first().waitFor();
    await page.getByText('已保存到本机',{exact:true}).waitFor();
    writeFileSync('.work/item.txt',await nodes.first().getAttribute('data-id'));
  } else { await nodes.first().waitFor(); assert.equal(await nodes.first().getAttribute('data-id'),readFileSync('.work/item.txt','utf8')); }
  await page.screenshot({path:`delivery/windows-${phase}.png`});
  // Removing the host in the caller must also remove its entire service job.
  process.exit(0);
} catch(e) { console.error('::error::'+String(e).replaceAll('\n',' ')); process.exit(1); }
