const {chromium}=require('C:/Users/PC/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try{
  const context=await browser.newContext({viewport:{width:1440,height:1100},acceptDownloads:true});const page=await context.newPage();let errors=[];page.on('pageerror',e=>errors.push(String(e)));let requests=[];page.on('request',r=>requests.push(r.url()));
  await page.goto('file:///'+path.join(__dirname,'bec-binding.html').replaceAll('\\','/'));assert.equal(await page.locator('.slot').count(),16);
  const uuid=n=>`${n.toString(16).padStart(8,'0')}-1234-4567-89ab-123456789abc`;
  await page.locator('[data-slot="3"]').click();await page.locator('#nodeAddress').fill(uuid(100));await page.locator('#redstoneAddress').fill(uuid(101));await page.locator('#pauseSide').selectOption('0');
  assert.match(await page.locator('[data-slot="2"]').innerText(),/空位/);
  await page.locator('#role-mainInterface').fill(uuid(1));await page.locator('#role-subInterface').fill(uuid(2));await page.locator('#role-storage').fill(uuid(3));await page.locator('#role-gate').fill(uuid(4));await page.locator('#role-transposer').fill(uuid(5));await page.locator('#role-generator1').fill(uuid(6));
  await page.locator('#check').click();assert.match(await page.locator('#status').innerText(),/格式检查通过/);
  let data=await page.evaluate(()=>BECBinding.toV2(BECBinding.getState()));assert.equal(data.nodes.length,1);assert.equal(data.nodes[0].slot,3);assert.equal(data.nodes[0].name,'节点3');assert.equal(data.nodes[0].pauseSide,0);assert.equal(data.groups[0].nanites.enabled,false);
  await page.reload();assert.equal(await page.locator('#count').innerText(),'1 / 16 组已填写');await page.locator('[data-slot="3"]').click();assert.equal(await page.locator('#nodeAddress').inputValue(),uuid(100));
  await page.locator('[data-slot="7"]').click();await page.locator('#nodeAddress').fill(uuid(100));await page.locator('#redstoneAddress').fill(uuid(102));await page.locator('#check').click();assert.match(await page.locator('#status').innerText(),/地址重复/);await page.locator('#clearSlot').click();
  await page.locator('#naniteMode').selectOption('me-interface');await page.locator('#role-naniteSupply').fill(uuid(8));await page.locator('#check').click();assert.match(await page.locator('#status').innerText(),/须一起填写/);await page.locator('#role-naniteSupply').fill('');
  await page.locator('#bulkToggle').click();await page.locator('#bulk').fill(`${uuid(100)},${uuid(101)},0\n-\n${uuid(102)},${uuid(103)},5`);await page.locator('#bulkApply').click();data=await page.evaluate(()=>BECBinding.toV2(BECBinding.getState()));assert.deepEqual(data.nodes.map(n=>n.slot),[1,3]);
  for(let i=1;i<=5;i++)await page.locator('#role-bulk'+i).fill(uuid(200+i));
  data=await page.evaluate(()=>BECBinding.toV2(BECBinding.getState()));assert.deepEqual(data.groups[0].bulkTransposers,[1,2,3,4,5].map(i=>uuid(200+i)));
  await page.reload();assert.equal(await page.locator('#role-bulk5').inputValue(),uuid(205));await page.locator('#bulkToggle').click();
  await page.locator('#naniteMode').selectOption('cell-io');await page.locator('#role-naniteTransposer').fill(uuid(300));await page.locator('#role-naniteLoadRedstone').fill(uuid(301));await page.locator('#check').click();assert.match(await page.locator('#status').innerText(),/须一起填写/);await page.locator('#role-naniteReturnRedstone').fill(uuid(302));
  data=await page.evaluate(()=>BECBinding.toV2(BECBinding.getState()));assert.equal(data.groups[0].nanites.mode,'cell-io');assert.equal(data.groups[0].nanites.loadRedstone,uuid(301));assert.equal(data.groups[0].nanites.returnOutputSide,0);assert(!data.groups[0].nanites.supplyInterface);
  const before=await page.evaluate(()=>BECBinding.getState());await page.locator('#bulk').fill('incomplete');await page.locator('#bulkApply').click();assert.deepEqual(await page.evaluate(()=>BECBinding.getState()),before);
  const jsonEvent=page.waitForEvent('download');await page.locator('#save').click();const jsonDownload=await jsonEvent;const saved=JSON.parse(fs.readFileSync(await jsonDownload.path(),'utf8'));assert.equal(saved.nodes.length,16);assert.equal(saved.nodes[1].address,'');assert.equal(saved.roles.bulk5,uuid(205));
  const luaEvent=page.waitForEvent('download');await page.locator('#export').click();const luaDownload=await luaEvent;const luaText=fs.readFileSync(await luaDownload.path(),'utf8');assert(luaText.includes('["slot"]=3'));assert(luaText.includes('["pauseSide"]=0'));
  fs.mkdirSync(path.join(__dirname,'../work'),{recursive:true});fs.writeFileSync(path.join(__dirname,'../work/binding-test.generated.dat'),luaText);
  const badFile={name:'broken.json',mimeType:'application/json',buffer:Buffer.from('{"version":7}')};await page.locator('#importFile').setInputFiles(badFile);await page.waitForTimeout(100);assert.match(await page.locator('#status').innerText(),/原草稿保持/);assert.deepEqual(await page.evaluate(()=>BECBinding.getState()),before);
  await page.locator('#importFile').setInputFiles({name:'draft.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(saved))});await page.waitForTimeout(100);assert.match(await page.locator('#status').innerText(),/草稿已打开/);assert.equal(await page.locator('#role-bulk5').inputValue(),uuid(205));
  await page.locator('#bulkToggle').click();await page.locator('#check').click();await page.screenshot({path:path.join(__dirname,'../work/bec-binding-preview.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth));
  assert.deepEqual(errors,[]);assert(requests.every(r=>r.startsWith('file:')),'Tool must not send network requests');
  console.log('Browser mouse editing, holes/order, direction0, duplicates, optional roles, autosave, JSON roundtrip, invalid import, bulk atomicity, Lua download, responsive layout and offline operation: PASS');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
