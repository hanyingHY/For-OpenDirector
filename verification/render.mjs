// Runs on the production bundle through an installed WebView. No Vite imports,
// fake export handlers, test HTTP routes, provider accounts or paid API calls.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import assert from 'node:assert/strict';
export async function renderCheck(page, app) {
  await page.getByRole('button',{name:'Add Timeline',exact:true}).click();
  const node=page.locator('.react-flow__node.selected');
  // desktop.8 regression (RFC #362): an empty timeline can still reach the toolbar
  // export; the failed card must be closable, not only retryable, and must vanish
  // without leaving an orphan video behind.
  await page.locator('.cw-selection-toolbar button[data-action="output"]').click();
  const stuck=page.locator('.cw-timeline-pending');
  await stuck.locator('[role="alert"]').waitFor();
  assert.match(await stuck.locator('[role="alert"]').innerText(),/Add media to the timeline first/);
  await page.screenshot({path:'delivery/windows-timeline-failed.png'});
  await stuck.getByRole('button',{name:'Dismiss',exact:true}).click();
  await stuck.waitFor({state:'detached'});
  if (!(await node.count())) await page.locator('.react-flow__node').last().click();
  await node.locator('.cw-node-title').click({button:'right'});
  await page.getByRole('menuitem',{name:'Open editor',exact:true}).click();
  const src='data:image/jpeg;base64,'+readFileSync('examples/01-orbit.jpg').toString('base64');
  const resource={id:'reference',kind:'image',title:'Orbit',src,mimeType:'image/jpeg',width:960,height:600};
  const timeline={fps:24,width:640,height:400,importedAssets:[],tracks:[{id:'visual',kind:'visual',title:'Orbit',muted:false,clips:[{id:'dawn',resource,inPoint:0,outPoint:1.5,speed:1,volume:1,muted:false}]}]};
  await page.getByLabel('Import timeline JSON',{exact:true}).setInputFiles({name:'orbit.timeline.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify({format:'opendirector-editable-timeline',version:1,timeUnit:'seconds',timeline}))});
  await page.locator('.cw-timeline-clip').first().waitFor();
  await page.getByRole('button',{name:'Render MP4',exact:true}).click();
  const button=page.getByRole('button',{name:'Download MP4',exact:true});
  try { await button.waitFor({timeout:75000}); }
  catch(e) { throw Error(`No MP4: ${(await page.locator('.cw-timeline-dialog').innerText()).slice(-1600)} (${e.name})`); }
  await page.screenshot({path:'delivery/windows-timeline.png'});
  const [download]=await Promise.all([page.waitForEvent('download'),button.click()]);
  await download.saveAs('delivery/timeline-export.mp4');
  const info=JSON.parse(execFileSync(join(app,'media','ffprobe.exe'),['-v','error','-show_streams','-show_format','-of','json','delivery/timeline-export.mp4']));
  const video=info.streams.find(s=>s.codec_type==='video');
  assert.equal(video.codec_name,'h264'); assert.equal(video.width,640); assert.equal(video.height,400); assert(Math.abs(Number(info.format.duration)-1.5)<0.2);
}
