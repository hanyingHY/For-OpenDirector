// Offline DOM harness for release selection. No network or GitHub privileges.
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const code=await readFile(new URL('../delivery/landing.js',import.meta.url),'utf8');
const base='https://github.com/hanyingHY/For-OpenDirector/releases';
function row(n,overrides={}) {
  const tag_name=`windows-x64-0.1.4-desktop.${n}`, name=`OpenDirector-0.1.4-desktop.${n}-x64-Setup.exe`;
  return {tag_name,draft:false,prerelease:false,assets:[{name,state:'uploaded',size:100,browser_download_url:`${base}/download/${tag_name}/${name}`}],...overrides};
}
async function run(rows, platform, ua) {
  const nodes=new Map();
  const document={documentElement:{},querySelectorAll:()=>[],querySelector(sel){if(!nodes.has(sel)) nodes.set(sel,{});return nodes.get(sel)}};
  await vm.runInNewContext(`(async()=>{${code}})()`,{document,AbortSignal,navigator:{language:'en-US',platform,userAgent:ua},fetch:async()=>({ok:rows!==null,json:async()=>rows})});
  return Object.fromEntries(nodes);
}
const bad=row(100);bad.assets[0].browser_download_url='https://example.org';
let n=await run([row(2),row(20,{draft:true}),row(19,{prerelease:true}),row(12,{assets:[]}),row('0999'),row(25,{draft:undefined}),bad,row(10)],'Win32','Win64; x64');
assert.equal(n['#platform'].value,'windows');assert.equal(n['#download'].href,row(10).assets[0].browser_download_url);assert(!n['#download'].hidden);
n['#platform'].value='mac';n['#platform'].onchange();assert(n['#download'].hidden);n['#language'].onclick();assert.match(n['#status'].textContent,/未提供/);
for(const rows of [[],null]){n=await run(rows,'Win32','unknown');assert.equal(n['#platform'].value,'unknown');n['#platform'].value='windows';n['#platform'].onchange();assert(n['#download'].hidden);assert.match(n['#status'].textContent,rows?/No public/:/unavailable/)}
console.log('PASS: public installer identity, version ordering, language, detection fallback and unavailable states');
