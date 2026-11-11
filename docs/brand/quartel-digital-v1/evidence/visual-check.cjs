const {chromium}=require('playwright');
const fs=require('fs');const assert=require('assert');
(async()=>{const b=await chromium.launch({executablePath:'/usr/bin/chromium',args:['--no-sandbox']});const results=[];
for(const [name,width,height] of [['desktop',1440,1000],['tablet',768,1024],['mobile',390,844],['small-mobile',320,720]]) {
const p=await b.newPage({viewport:{width,height}});const errors=[];p.on('pageerror',e=>errors.push(e.message));await p.goto('http://localhost:3001',{waitUntil:'networkidle'});await p.waitForTimeout(800);
await p.screenshot({path:`/workspace/work/evidence/after-${name}-top.png`});
const accent=await p.locator('.gold-gradient').first().evaluate(e=>getComputedStyle(e).backgroundColor);assert.equal(accent,'rgb(184, 155, 94)');
for(const section of await p.locator('main section').all()){await section.scrollIntoViewIfNeeded();await p.waitForTimeout(200);}
await p.locator('footer').scrollIntoViewIfNeeded();await p.waitForTimeout(600);await p.locator('footer img').evaluate(img=>img.decode());await p.screenshot({path:`/workspace/work/evidence/after-${name}-footer.png`});
const logos=await p.locator('img[alt="Quartel Digital"]').evaluateAll(imgs=>imgs.map(i=>({src:i.getAttribute('src'),loaded:i.complete&&i.naturalWidth>0})));assert(logos.every(i=>i.loaded));
const overflow=await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth);assert(!overflow,`${name} overflow`);assert.equal(errors.length,0);
if(width<768){await p.evaluate(()=>scrollTo(0,0));await p.getByRole('button',{name:'Menu',exact:true}).click();assert(await p.getByRole('link',{name:'Como Funciona',exact:true}).first().isVisible());await p.getByRole('link',{name:'Como Funciona',exact:true}).first().click();assert(!await p.getByRole('link',{name:'Como Funciona',exact:true}).first().isVisible());}
results.push({name,width,height,overflow,logos,errors,accent});await p.close();}
const p=await b.newPage();await p.goto('http://localhost:3001');const links=await p.locator('link[rel="icon"],link[rel="apple-touch-icon"],link[rel="manifest"]').evaluateAll(els=>els.map(e=>e.getAttribute('href')));const http=[];for(const url of [...links,...[192,512].map(n=>`/assets/brand/quartel-digital-v1/QD_favicon_mira_${n}.png`)]){const r=await p.request.get('http://localhost:3001'+url);assert.equal(r.status(),200);http.push({url,status:r.status(),type:r.headers()['content-type'],cache:r.headers()['cache-control']});}
fs.writeFileSync('/workspace/work/evidence/browser-results.json',JSON.stringify({results,http},null,2));console.log(JSON.stringify({results,http},null,2));await b.close();})();
