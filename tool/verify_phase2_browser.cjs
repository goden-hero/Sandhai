/* Local emulator integration probe. Never run against production. */
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const http = require('node:http');
const assert = require('node:assert/strict');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright-core');
const projectId = 'sandhai-5km-demo';
const repositoryRoot = path.resolve(__dirname, '..');
const artifactRoot=process.env.SANDHAI_ARTIFACTS||'/tmp';
fs.mkdirSync(artifactRoot,{recursive:true});
const root = path.join(repositoryRoot, 'build/emulator-web');
const originalRules = fs.readFileSync(path.join(repositoryRoot, 'firestore.rules'), 'utf8');
const host = '127.0.0.1';
const stamp = Date.now();
const password = 'phase2-test-password';
const checks = [];
const types = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.otf':'font/otf','.ttf':'font/ttf'};
async function environment(rules) {
  return initializeTestEnvironment({projectId,firestore:{host,port:8080,rules}});
}
async function createAccount(email) {
  const r = await fetch(`http://${host}:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`,{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email,password,returnSecureToken:true})});
  const data = await r.json(); assert.ok(r.ok,JSON.stringify(data)); return data;
}
(async()=>{
  let env, browser, server, page;
  const contexts = [];
  try {
    env = await environment(originalRules);
    async function admin(task) {
      let result;
      await env.withSecurityRulesDisabled(async c=>{result=await task(c.firestore());});
      return result;
    }
    server = http.createServer(async(req,res)=>{
      try {
        const url = new URL(req.url, 'http://localhost');
        const file = path.resolve(root,url.pathname==='/'?'index.html':decodeURIComponent(url.pathname).replace(/^\/+/,''));
        if(!file.startsWith(root+'/')) throw Error('Bad path');
        const bytes=await fsp.readFile(file);
        res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream'});
        res.end(bytes);
      } catch (_) { res.writeHead(404);res.end(); }
    });
    await new Promise(r=>server.listen(0,host,r));
    browser=await chromium.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
    const context=await browser.newContext({viewport:{width:1280,height:1600},ignoreHTTPSErrors:true}); contexts.push(context);
    await context.addInitScript(()=>window.sessionStorage.setItem('[DEFAULT]-firebaseEmulatorOrigin','http://127.0.0.1:1'));
    page=await context.newPage();
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    const url=`http://${host}:${server.address().port}`;
    async function open(reload=false){
      if(reload)await page.reload({waitUntil:'load'});else await page.goto(url,{waitUntil:'load'});
      await page.locator('flutter-view').waitFor({timeout:60000});
      const accessibility=page.locator('flt-semantics-placeholder');
      if(await accessibility.count())await accessibility.evaluate(e=>e.click());
    }
    async function text(value){await page.getByText(value,{exact:false}).first().waitFor({timeout:30000});}
    async function fill(index,value){
      const box=page.getByRole('textbox').nth(index);
      await box.focus();
      await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
      await box.fill(value);
      // Flutter applies editing/focus events on its next animation frame.
      // Wait for two frames before moving to a different field.
      await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    }
    async function button(name){
      const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
      await page.getByRole('button',{name:new RegExp(escaped)}).first().click();
    }
    async function signIn(email){await button('Sign In');await text('Welcome Back');await fill(0,email);await fill(1,password);await page.getByRole('button',{name:'Sign In',exact:true}).last().click();}
    const emailA=`phase2-vendor-a-${stamp}@example.com`;
    await open();await text('5KM Sandhai');
    assert.equal(await page.evaluate(()=>window.sessionStorage.getItem('[DEFAULT]-firebaseEmulatorOrigin')),null);
    checks.push('explicit mode/host clears the previous FlutterFire debug emulator hint');
    assert.equal(await page.getByText(/Demo mode/).count(),0);
    await page.getByRole('button',{name:/I want to sell excess stock/}).click();
    await text('Vendor Registration');
    const values=['Phase 2 Store A','9876543210','Address A','Description A',emailA,password,password];
    for(let i=0;i<values.length;i++)await fill(i,values[i]);
    await button('Submit Vendor Registration');await text('APPROVAL PENDING');
    const a=await admin(async db=>{
      const q=await db.collection('users').where('email','==',emailA).get();assert.equal(q.size,1);
      const doc=q.docs[0];assert.equal(doc.data().approvalStatus,'pending');
      assert.equal((await db.doc(`vendors/${doc.id}`).get()).data().address,'Address A');return doc.id;
    });checks.push('UI vendor registration atomically persists both profiles as pending');
    await open(true);await text('APPROVAL PENDING');await text('Phase 2 Store A');
    checks.push('browser reload restores the signed-in pending vendor');
    await admin(db=>db.doc(`users/${a}`).update({approvalStatus:'approved'}));await text('APPROVED');
    checks.push('approval updates during an active session');
    await button('Business profile');await text('Vendor Profile');
    await button('Confirm / edit store location');await text('Confirm store location');
    await fill(0,'11.1');await fill(1,'77.2');
    await page.getByRole('checkbox').click();await button('Save confirmed location');
    await page.getByText('Vendor Profile',{exact:true}).waitFor({timeout:30000});
    await page.getByRole('button',{name:'Back',exact:true}).click();await text('Your offers');
    await button('Post Clearance Offer');await text('Post Clearance Offer');
    for(const [i,value] of ['Persistent offer A','Saved details','100','50'].entries())await fill(i,value);
    await button('Publish Clearance Offer');await text('Persistent offer A');
    const offersA=await admin(async db=>(await db.collection('offers').where('vendorId','==',a).get()).docs);
    assert.equal(offersA.length,1);assert.equal(offersA[0].data().title,'Persistent offer A');
    await open(true);await text('Persistent offer A');checks.push('confirmed offer survives browser reload');
    await button('Business profile');await text('Vendor Profile');await button('Edit Profile');
    const deniedRules=originalRules.replace('allow update: if isOwner(uid)',"allow update: if request.resource.data.displayName != 'REJECT_SAVE' && isOwner(uid)");
    const denyEnv=await environment(deniedRules);contexts.push(denyEnv);
    await fill(0,'REJECT_SAVE');await button('Save profile');
    await page.getByText(/server rejected this operation/i).first().waitFor({timeout:30000});
    assert.equal(await page.getByText('Vendor profile saved.',{exact:true}).count(),0);
    // Check the real editing field, not a test-only UI state.
    assert.ok((await page.getByRole('textbox').first().getAttribute('aria-label')||'').includes('REJECT_SAVE') || await page.getByText('REJECT_SAVE',{exact:true}).count() || await page.locator('input').evaluateAll(inputs=>inputs.some(i=>i.value==='REJECT_SAVE')));
    await admin(async db=>{assert.equal((await db.doc(`vendors/${a}`).get()).data().name,'Phase 2 Store A');assert.equal((await db.doc(`users/${a}`).get()).data().displayName,'Phase 2 Store A');});
    checks.push('real permission-denied profile transaction shows error, retains input, and changes neither document');
    const restored=await environment(originalRules);contexts.push(restored);
    await fill(0,'Persistent updated store');await button('Save profile');await text('Vendor profile saved.');
    await open(true);await text('Persistent updated store');checks.push('retry confirms profile save and persists after reload');
    await admin(db=>db.doc(`users/${a}`).update({approvalStatus:'suspended'}));await text('APPROVAL REVOKED / REJECTED');
    const locked=page.getByRole('button',{name:'Approval required',exact:true});assert.equal(await locked.isDisabled(),true);
    checks.push('revoked approval disables publication without login');
    await button('Sign Out');await text('5KM Sandhai');assert.equal(await page.getByText('Persistent offer A',{exact:false}).count(),0);
    const emailB=`phase2-vendor-b-${stamp}@example.com`;const b=await createAccount(emailB);
    await admin(async db=>{
      const now=new Date();await db.doc(`users/${b.localId}`).set({displayName:'Store B',email:emailB,role:'vendor',approvalStatus:'approved',createdAt:now});
      await db.doc(`vendors/${b.localId}`).set({name:'Store B',phone:'9876543210',category:'Groceries',latitude:13.0827,longitude:80.2707,geohash:'tf346c',createdAt:now});
      await db.doc(`offers/private-b-${stamp}`).set({vendorId:b.localId,title:'Private draft B',description:'B only',oldPrice:100,newPrice:50,imageUrl:'',latitude:13.0827,longitude:80.2707,geohash:'tf346c',createdAt:now,expiryTime:new Date(+now+3600000),status:'draft'});
    });
    await signIn(emailB);await text('Private draft B');assert.equal(await page.getByText('Persistent offer A',{exact:false}).count(),0);
    checks.push('logout/account switch clears account A and shows only account B private dashboard');
    await button('Sign Out');await text('5KM Sandhai');
    const emailC=`phase2-incomplete-${stamp}@example.com`;const c=await createAccount(emailC);
    await signIn(emailC);await text('Complete registration');await open(true);await text('Complete registration');
    await fill(0,'Recovered Store');await fill(1,'9876543210');await fill(2,'Recovered address');await button('Complete registration');
    await text('APPROVAL PENDING');await text('Recovered Store');
    await admin(async db=>{const q=await db.collection('users').where('email','==',emailC).get();assert.equal(q.size,1);assert.equal(q.docs[0].id,c.localId);assert.equal(q.docs[0].data().approvalStatus,'pending');assert.equal((await db.doc(`vendors/${c.localId}`).get()).data().name,'Recovered Store');});
    checks.push('Auth-only interrupted registration survives reload and completes under the original UID with pending approval');
    await button('Sign Out');await text('5KM Sandhai');
    await page.getByRole('button',{name:/I'm here to shop/}).click();
    await text('Customer Registration');
    for(const [i,value] of ['Persisted customer',`phase2-customer-${stamp}@example.com`,password,password].entries())await fill(i,value);
    await button('Create Customer Account');await text('Nearby discovery is not connected yet');
    await open(true);await text('Nearby discovery is not connected yet');
    assert.equal(await page.getByText('Simulate Empty:',{exact:false}).count(),0);
    await button('Profile & Settings');await text('Persisted customer');
    assert.equal(await page.getByText('Mock 5 KM',{exact:false}).count(),0);
    assert.equal(await page.getByText('Push Notifications',{exact:false}).count(),0);
    checks.push('customer registration restores after reload and live screens contain no sample offers/location/settings');
    await page.screenshot({path:path.join(artifactRoot,'sandhai-phase2-browser.png')});
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({result:'PASS',browser:await browser.version(),checks,artifact:path.join(artifactRoot,'sandhai-phase2-browser.png')},null,2));
  } catch(error) {
    if(page){await page.screenshot({path:path.join(artifactRoot,'sandhai-phase2-browser-failure.png')}).catch(()=>{});console.error('Visible semantics:',(await page.locator('body').innerText().catch(()=>'' )).slice(0,2500));console.error('Textbox count:',await page.getByRole('textbox').count().catch(()=>-1));}
    throw error;
  } finally {
    // Restore the original policy even if the deliberate rejection check failed.
    const restored=await environment(originalRules).catch(()=>null);if(restored)await restored.cleanup();
    if(browser)await browser.close();
    if(server)await new Promise(resolve=>server.close(resolve));
    for(const c of contexts){if(c.cleanup)await c.cleanup();}
    if(env)await env.cleanup();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
