const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {chromium} = require('playwright');
const {default: AxeBuilder} = require('@axe-core/playwright');

// Tests launch their own local server; no production writes or downloads.
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'test-results');
const port = 18765;
const url = `http://127.0.0.1:${port}`;
const results = [];
const problems = [];
fs.mkdirSync(output, {recursive:true});
const server = spawn('python3', ['-m','http.server',String(port),'--bind','127.0.0.1'], {cwd:root,stdio:'ignore'});

async function test(name, fn) {
  try {await fn();results.push({name,status:'pass'});}
  catch(error) {problems.push({name,error:error.message});results.push({name,status:'fail'});}
}
async function layout(page) {
  const state=await page.evaluate(()=>({
    overflow:document.documentElement.scrollWidth > innerWidth,
    broken:[...document.images].filter(x=>x.complete&&!x.naturalWidth).map(x=>x.getAttribute('src')),
    missing:[...document.querySelectorAll('[data-i18n]')].filter(x=>!x.textContent.trim()).map(x=>x.dataset.i18n),
    duplicates:[...document.querySelectorAll('[id]')].map(x=>x.id).filter((id,i,ids)=>ids.indexOf(id)!==i)
  }));
  assert.equal(state.overflow,false,JSON.stringify(state));assert.deepEqual(state.broken,[]);assert.deepEqual(state.missing,[]);assert.deepEqual(state.duplicates,[]);
}
async function capture(page,name,full=false) {
  await page.evaluate(async()=>{for(let y=0;y<document.body.scrollHeight;y+=700){scrollTo(0,y);await new Promise(r=>setTimeout(r,15));}scrollTo(0,0);await document.fonts.ready;});
  await page.screenshot({path:path.join(output,name+'.png'),fullPage:full});
}
(async()=>{
 let browser;
 try {
  let ready=false;
  for(let i=0;i<60;i++) {try {const response=await fetch(url);if(response.ok){ready=true;break;}}catch{} await new Promise(r=>setTimeout(r,100));}
  assert.ok(ready,'Local test server did not start');
  const executablePath=process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  browser=await chromium.launch({executablePath,headless:true});
  for(const lang of ['en','ko','ja']) {
   for(const width of [320,375,414,768,1024,1440,1920]) {
    await test(`layout / ${lang} / ${width}px`,async()=>{
     const p=await browser.newPage({viewport:{width,height:900},reducedMotion:'reduce'});
     const errors=[];p.on('pageerror',e=>errors.push(e.message));
     try {
      await p.addInitScript(lang=>localStorage.setItem('ptb-lang',lang),lang);
      await p.goto(url);await p.evaluate(()=>document.fonts.ready);
      assert.equal(await p.locator('html').getAttribute('lang'),lang);
      assert.ok((await p.locator('html').getAttribute('class')).includes('js'));
      await layout(p);
      if([375,1440].includes(width)) {await capture(p,`${lang}-${width}-light`);await capture(p,`${lang}-${width}-full`,true);}
      assert.equal(await p.locator('#gtab-growth').isVisible(),true);
      await p.locator('#gPace').selectOption('120');
      assert.match(await p.locator('#gTimeline .tl-when').last().innerText(),/7/);
      await p.locator('#gRarity').selectOption('legendary');
      assert.match(await p.locator('#gTimeline .tl-when').last().innerText(),/51/);
      await layout(p);
      await p.locator('.all-features > summary').click();
      await p.locator('.install-more > summary').click();
      await layout(p);
      await p.locator('#themeBtn').click();
      assert.equal(await p.locator('html').getAttribute('data-theme'),'dark');
      await layout(p);
      if([375,1440].includes(width)) {
       await capture(p,`${lang}-${width}-dark`);
       await p.locator('#themeBtn').click();
       await capture(p,`${lang}-${width}-expanded`,true);
       const native = await p.locator('[data-i18n-image]').evaluateAll(images => images.map(i=>({src:i.getAttribute('src'),loaded:i.complete&&i.naturalWidth>0,width:i.naturalWidth,height:i.naturalHeight,caption:i.closest('figure').querySelector('figcaption').textContent})));
       assert.equal(native.length,9);
       const suffix=lang==='en'?'':'-'+lang;
       for(const i of native) {assert.ok(i.loaded,JSON.stringify(i));assert.ok(i.src.endsWith(suffix+'.png'),JSON.stringify(i));assert.equal(i.width,720);assert.ok(i.caption.trim());}
       await layout(p);
      }
      assert.deepEqual(errors,[]);
     }finally{await p.close();}
    });
   }
  }
  for(const lang of ['en','ko','ja']) for(const theme of ['light','dark']) await test(`axe WCAG 2.2 AA / ${lang} / ${theme}`,async()=>{
   const context=await browser.newContext({viewport:{width:1440,height:960},reducedMotion:'reduce'});
   const p=await context.newPage();
   try {
    await p.addInitScript(({lang,theme})=>{localStorage.setItem('ptb-lang',lang);localStorage.setItem('ptb-theme',theme);},{lang,theme});
    await p.goto(url);await p.evaluate(()=>{document.querySelectorAll('details').forEach(x=>x.open=true);});
    for(const tab of ['growth','daily','collect']) {
     await p.locator(`#tab-${tab}`).click();
     const report=await new AxeBuilder({page:p}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();
     if(report.violations.length)fs.writeFileSync(path.join(output,`axe-${lang}-${theme}-${tab}.json`),JSON.stringify(report.violations,null,2));
     assert.deepEqual(report.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)})),[]);
    }
   }finally{await context.close();}
  });
  await test('clipboard success, rejection, unsupported; translated feedback',async()=>{
   const p=await browser.newPage();
   try {
    await p.goto(url);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{window.copiedText=text;}}}));
    await p.locator('[data-copy]').click();
    await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='success');
    assert.equal(await p.evaluate(()=>window.copiedText),'brew install --cask chattymin/tap/poke-token-bar');
    await p.locator('#language').selectOption('ko');assert.match(await p.locator('#copy-status').innerText(),/복사했어요/);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async()=>{throw Error('denied');}}}));
    await p.locator('[data-copy]').click();await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='error');
    assert.match(await p.locator('#copy-status').innerText(),/직접 선택/);
    assert.match(await p.evaluate(()=>getSelection().toString()),/brew install/);
    await p.evaluate(()=>Object.defineProperty(navigator,'clipboard',{configurable:true,value:undefined}));
    await p.locator('[data-copy]').click();await p.waitForFunction(()=>document.querySelector('#copy-status').dataset.state==='error');
    assert.equal(await p.locator('[data-copy]').isEnabled(),true);
   }finally{await p.close();}
  });
  await test('mobile menu, Escape, anchors, guide tab keyboard',async()=>{
   const p=await browser.newPage({viewport:{width:375,height:812},reducedMotion:'reduce'});
   try {
    await p.goto(url);await p.locator('#menuBtn').click();assert.equal(await p.locator('#site-nav').isVisible(),true);
    await p.keyboard.press('Escape');assert.equal(await p.locator('#site-nav').isVisible(),false);
    assert.equal(await p.locator('#menuBtn').evaluate(x=>x===document.activeElement),true);
    await p.locator('#menuBtn').click();await p.locator('#site-nav a[href="#install"]').click();
    assert.equal(await p.locator('#site-nav').isVisible(),false);
    await p.waitForFunction(()=>location.hash==='#install');
    const offset=await p.locator('#install').evaluate(x=>x.getBoundingClientRect().top);
    assert.ok(offset>=72,`Install hidden behind header: ${offset}`);
    assert.equal(await p.locator('#gtab-growth').isVisible(),true);await p.locator('#tab-growth').focus();
    await p.keyboard.press('ArrowRight');assert.equal(await p.locator('#tab-daily').getAttribute('aria-selected'),'true');
    assert.equal(await p.locator('#gtab-daily').isVisible(),true);assert.equal(await p.locator('#gtab-growth').isVisible(),false);
    await p.keyboard.press('End');assert.equal(await p.locator('#tab-collect').getAttribute('aria-selected'),'true');
    await p.keyboard.press('Home');assert.equal(await p.locator('#tab-growth').getAttribute('aria-selected'),'true');
   }finally{await p.close();}
  });
  await test('JavaScript disabled: install, navigation and every guide section work',async()=>{
   const p=await browser.newPage({javaScriptEnabled:false,viewport:{width:375,height:812}});
   try {
    await p.goto(url);assert.equal(await p.locator('#site-nav').isVisible(),true);
    assert.equal(await p.locator('[data-copy]').isVisible(),false);
    assert.match(await p.locator('#install-command').innerText(),/brew install/);
    assert.equal(await p.locator('#gtab-growth').isVisible(),true);
    for(const k of ['growth','daily','collect'])assert.equal(await p.locator('#gtab-'+k).isVisible(),true);
    await layout(p);
   }finally{await p.close();}
  });
  await test('blocked localStorage and missing image fallback do not block installation',async()=>{
   const p=await browser.newPage();
   try {
    await p.addInitScript(()=>Object.defineProperty(window,'localStorage',{get(){throw Error('blocked');}}));
    await p.route('**/assets/screenshot-home.png',route=>route.abort());
    await p.goto(url);assert.equal(await p.locator('#install-command').isVisible(),true);
    await p.locator('#language').selectOption('ja');assert.equal(await p.locator('html').getAttribute('lang'),'ja');
   }finally{await p.close();}
  });
  await test('reduced-motion uses still image; language and theme survive reload',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    await p.goto(url);await p.locator('.pet-story').scrollIntoViewIfNeeded();
    await p.waitForFunction(()=>document.querySelector('.pet-story img').complete && document.querySelector('.pet-story img').naturalWidth>0);
    assert.match(await p.locator('.pet-story img').evaluate(x=>x.currentSrc),/floating-pet-still/);
    await p.locator('#demoBtn').click();assert.match(await p.locator('#pet-demo').getAttribute('src'),/floating-pet.gif/);
    await p.locator('#demoBtn').click();assert.match(await p.locator('#pet-demo').getAttribute('src'),/floating-pet-still/);
    await p.locator('#language').selectOption('ja');await p.locator('#themeBtn').click();await p.reload();
    assert.equal(await p.locator('html').getAttribute('lang'),'ja');assert.equal(await p.locator('html').getAttribute('data-theme'),'dark');
   }finally{await p.close();}
  });
  await test('growth guide is expanded; 16 linked tools follow it in both themes',async()=>{
   const p=await browser.newPage({viewport:{width:375,height:812}});
   try {
    await p.goto(url);
    assert.equal(await p.locator('details.guide-body').count(),0);
    assert.equal(await p.locator('#gtab-growth').isVisible(),true);
    assert.equal(await p.locator('#providers').evaluate(x=>x.previousElementSibling.id),'guide');
    const links=p.locator('.provider-link');assert.equal(await links.count(),16);
    for(const theme of ['light','dark']) {
     if(theme==='dark')await p.locator('#themeBtn').click();
     await p.locator('#providers').scrollIntoViewIfNeeded();
     await p.waitForFunction(()=>[...document.querySelectorAll('.provider-icon img')].every(i=>i.complete&&i.naturalWidth));
     for(const link of await links.all()) {assert.equal(await link.isVisible(),true);assert.match(await link.getAttribute('href'),/^https:\/\//);}
     await layout(p);await p.locator('#providers').screenshot({path:path.join(output,'providers-'+theme+'.png')});
    }
    await p.route('https://claude.com/**',r=>r.fulfill({status:200,body:'Official destination intercepted for navigation test'}));
    await links.first().click();await p.waitForURL('https://claude.com/product/claude-code');
   }finally{await p.close();}
  });
  await test('language switching swaps native samples; fallback and translation keys agree',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    await p.goto(url);
    assert.deepEqual(await p.evaluate(()=>Object.keys(I18N.en).filter(k=>!(k in I18N.ko)||!(k in I18N.ja))),[]);
    for(const lang of ['ko','ja','en']) {
     await p.locator('#language').selectOption(lang);
     assert.deepEqual(await p.locator('[data-i18n-alt]').evaluateAll(es=>es.filter(e=>e.alt!==I18N[document.documentElement.lang][e.dataset.i18nAlt]).map(e=>e.dataset.i18nAlt)),[]);
     assert.deepEqual(await p.locator('[data-i18n]').evaluateAll(es=>es.filter(e=>e.textContent.replace(/\n/g,'')!==I18N[document.documentElement.lang][e.dataset.i18n].replace(/\n/g,'')).map(e=>e.dataset.i18n)),[]);
     const suffix=lang==='en'?'':'-'+lang;
     for(const src of await p.locator('[data-i18n-image]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.ok(src.endsWith(suffix+'.png'));
     assert.equal(await p.locator('.product-image img').getAttribute('src'),'assets/screenshot-home.png');
    }
    assert.equal(await p.locator('.provider-link').filter({hasText:'Kimi Code'}).getAttribute('href'),'https://www.kimi.com/code');
   }finally{await p.close();}
  });
  await test('growth animation play, pause and reduced motion remain available',async()=>{
   const p=await browser.newPage({reducedMotion:'reduce'});
   try {
    await p.goto(url);
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'false');
    await p.locator('#growth-motion').click();
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'true');
    for(const src of await p.locator('[data-growth-sprite]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.match(src,/\.gif$/);
    await p.locator('#growth-motion').click();
    assert.equal(await p.locator('#growth-motion').getAttribute('aria-pressed'),'false');
    for(const src of await p.locator('[data-growth-sprite]').evaluateAll(es=>es.map(e=>e.getAttribute('src'))))assert.match(src,/\.png$/);
   }finally{await p.close();}
  });
  await test('every same-page link has a target and ZIP uses latest release',async()=>{
   const p=await browser.newPage();
   try {
    await p.goto(url);
    assert.deepEqual(await p.locator('a[href^="#"]').evaluateAll(as=>as.filter(a=>!document.getElementById(a.hash.slice(1))).map(a=>a.hash)),[]);
    assert.equal(await p.locator('a[href$="PokeTokenBar.zip"]').getAttribute('href'),'https://github.com/chattymin/PokeTokenBar/releases/latest/download/PokeTokenBar.zip');
   }finally{await p.close();}
  });
 }catch(error){problems.push({name:'harness',error:error.stack});}
 finally {
  if(browser)await browser.close();server.kill();
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify({results,problems},null,2));
  console.log(`${results.filter(r=>r.status==='pass').length}/${results.length} checks passed`);
  if(problems.length){console.error(JSON.stringify(problems,null,2));process.exitCode=1;}
 }
})();
