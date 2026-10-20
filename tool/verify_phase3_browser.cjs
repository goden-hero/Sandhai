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
const artifacts = process.env.SANDHAI_ARTIFACTS || '/tmp/sandhai-phase3-browser';
fs.mkdirSync(artifacts,{recursive:true});
const photo = path.join(repositoryRoot,'test/fixtures/grocery-photo.jpg');
const root = path.join(repositoryRoot, 'build/emulator-web');
const originalRules = fs.readFileSync(path.join(repositoryRoot, 'firestore.rules'), 'utf8');
const host = '127.0.0.1';
const stamp = Date.now();
const password = 'phase3-test-password';
const checks = [];
const types = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.otf':'font/otf','.ttf':'font/ttf'};
async function environment(rules) {
  return initializeTestEnvironment({projectId,firestore:{host,port:8080,rules},storage:{host,port:9199,rules:fs.readFileSync(path.join(repositoryRoot,'storage.rules'),'utf8')}});
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
    async function text(value){await page.getByText(value,{exact:false}).or(page.getByLabel(value,{exact:false})).first().waitFor({timeout:30000});}
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
    const emailA=`phase3-vendor-a-${stamp}@example.com`;
    await open();await text('5KM Sandhai');
    assert.equal(await page.evaluate(()=>window.sessionStorage.getItem('[DEFAULT]-firebaseEmulatorOrigin')),null);
    checks.push('explicit mode/host clears the previous FlutterFire debug emulator hint');
    assert.equal(await page.getByText(/Demo mode/).count(),0);
    await page.getByRole('button',{name:/I want to sell excess stock/}).click();
    await text('Vendor Registration');
    const values=['Phase 3 Store A','9876543210','Address A','Description A',emailA,password,password];
    for(let i=0;i<values.length;i++)await fill(i,values[i]);
    await button('Submit Vendor Registration');await text('APPROVAL PENDING');
    const a=await admin(async db=>{
      const q=await db.collection('users').where('email','==',emailA).get();assert.equal(q.size,1);
      const doc=q.docs[0];assert.equal(doc.data().approvalStatus,'pending');
      assert.equal((await db.doc(`vendors/${doc.id}`).get()).data().address,'Address A');return doc.id;
    });checks.push('UI vendor registration atomically persists both profiles as pending');
    await open(true);await text('APPROVAL PENDING');await text('Phase 3 Store A');
    checks.push('browser reload restores the signed-in pending vendor');
    await admin(db=>db.doc(`users/${a}`).update({approvalStatus:'approved'}));await text('APPROVED');
    checks.push('approval updates during an active session');
    await button('Business profile');await text('Vendor Profile');
    await button('Confirm / edit store location');await text('Confirm store location');
    await button('Suggest device location');await page.getByText(/Location permission (was|is permanently) denied/i).first().waitFor({timeout:30000});
    checks.push('browser location permission failure stays visible without fabricated coordinates');
    await context.grantPermissions(['geolocation'],{origin:url});
    await context.setGeolocation({latitude:11.1,longitude:77.2,accuracy:10});
    await button('Suggest device location');await page.getByRole('checkbox').waitFor();
    await admin(async db=>assert.equal((await db.doc(`vendors/${a}`).get()).data().locationConfirmedAt,undefined));
    await page.screenshot({path:path.join(artifacts,'location-suggestion.png')});
    await page.getByRole('checkbox').click();await button('Save confirmed location');
    await page.getByText('Vendor Profile',{exact:true}).waitFor({timeout:30000});
    await admin(async db=>{
      const store=(await db.doc(`vendors/${a}`).get()).data();
      assert.equal(store.latitude,11.1);assert.equal(store.longitude,77.2);assert.ok(store.locationConfirmedAt);
      fs.writeFileSync(path.join(artifacts,'store.json'),JSON.stringify(store,null,2));
    });
    checks.push('device suggestion requires explicit vendor confirmation and saves reviewed coordinates');
    await page.getByRole('button',{name:'Back',exact:true}).click();await text('Your offers');
    await button('Post Clearance Offer');await text('Post Clearance Offer');
    for(const [i,value] of ['Persistent offer A','Saved details','100','50'].entries())await fill(i,value);
    await button('Groceries');await page.getByRole('menuitem',{name:'Fresh Produce',exact:true}).click();
    let chooser=page.waitForEvent('filechooser');await button('Choose photo');
    await (await chooser).setFiles({name:'fake.jpg',mimeType:'image/jpeg',buffer:Buffer.from('fake image content')});
    await text('Choose a valid JPEG');checks.push('browser picker rejects fabricated image bytes and retains fields');
    chooser=page.waitForEvent('filechooser');await button('Choose photo');await (await chooser).setFiles(photo);
    await text('image/jpeg');await page.screenshot({path:path.join(artifacts,'photo-preview.png')});
    // Reject the real publication after upload, then inspect both backends.
    const denyPhoto=originalRules.replace('allow create: if isApprovedVendor() && validOffer',"allow create: if request.resource.data.title != 'Persistent offer A' && isApprovedVendor() && validOffer");
    const denyPhotoEnv=await environment(denyPhoto);contexts.push(denyPhotoEnv);
    await button('Publish Clearance Offer');await text('server rejected');
    await admin(async db=>assert.equal((await db.collection('offers').where('vendorId','==',a).get()).size,0));
    const objectResponse=await fetch(`http://${host}:9199/v0/b/${projectId}.appspot.com/o?prefix=${encodeURIComponent(`offers/${a}/`)}`,{headers:{Authorization:'Bearer owner'}});
    assert.ok(objectResponse.ok,`Storage listing failed: ${objectResponse.status}`);
    const objects=await objectResponse.json();
    assert.equal((objects.items||[]).length,0,JSON.stringify(objects));
    await page.screenshot({path:path.join(artifacts,'publication-failed-retained.png')});
    checks.push('failed publication is visible, retains real photo and fields, and cleans its unreferenced upload');
    const restorePhoto=await environment(originalRules);contexts.push(restorePhoto);
    await button('Publish Clearance Offer');await text('Persistent offer A');
    const offersA=await admin(async db=>(await db.collection('offers').where('vendorId','==',a).get()).docs);
    assert.equal(offersA.length,1);assert.equal(offersA[0].data().title,'Persistent offer A');
    const offerData=offersA[0].data();assert.equal(offerData.category,'fresh_produce');assert.equal(offerData.latitude,11.1);assert.equal(offerData.longitude,77.2);
    assert.match(offerData.imagePath,new RegExp(`^offers/${a}/${offersA[0].id}/[a-f0-9]{64}\\.jpg$`));
    assert.equal(offerData.imageContentType,'image/jpeg');assert.equal(offerData.imageSize,fs.statSync(photo).size);
    const metadata=await (await fetch(`http://${host}:9199/v0/b/${projectId}.appspot.com/o/${encodeURIComponent(offerData.imagePath)}`)).json();
    assert.equal(metadata.contentType,'image/jpeg');assert.equal(Number(metadata.size),offerData.imageSize);
    const remote=Buffer.from(await (await fetch(offerData.imageUrl)).arrayBuffer());assert.deepEqual(remote,fs.readFileSync(photo));
    fs.writeFileSync(path.join(artifacts,'offer.json'),JSON.stringify({id:offersA[0].id,...offerData},null,2));fs.writeFileSync(path.join(artifacts,'image-metadata.json'),JSON.stringify(metadata,null,2));
    await open(true);await text('Persistent offer A');await page.getByLabel('Saved offer photo',{exact:false}).first().waitFor();
    await page.screenshot({path:path.join(artifacts,'reloaded-offer-photo.png')});
    checks.push('retry saves one offer and one real photo with independently verified category, coordinates, bytes, MIME and metadata; reload restores them');
    await button('Business profile');await text('Vendor Profile');await button('Edit Profile');
    const deniedRules=originalRules.replace('allow update: if isOwner(uid)',"allow update: if request.resource.data.displayName != 'REJECT_SAVE' && isOwner(uid)");
    const denyEnv=await environment(deniedRules);contexts.push(denyEnv);
    await fill(0,'REJECT_SAVE');await button('Save profile');
    await page.getByText(/server rejected this operation/i).first().waitFor({timeout:30000});
    assert.equal(await page.getByText('Vendor profile saved.',{exact:true}).count(),0);
    // Check the real editing field, not a test-only UI state.
    assert.ok((await page.getByRole('textbox').first().getAttribute('aria-label')||'').includes('REJECT_SAVE') || await page.getByText('REJECT_SAVE',{exact:true}).count() || await page.locator('input').evaluateAll(inputs=>inputs.some(i=>i.value==='REJECT_SAVE')));
    await admin(async db=>{assert.equal((await db.doc(`vendors/${a}`).get()).data().name,'Phase 3 Store A');assert.equal((await db.doc(`users/${a}`).get()).data().displayName,'Phase 3 Store A');});
    checks.push('real permission-denied profile transaction shows error, retains input, and changes neither document');
    const restored=await environment(originalRules);contexts.push(restored);
    await fill(0,'Persistent updated store');await button('Save profile');await text('Vendor profile saved.');
    await open(true);await text('Persistent updated store');checks.push('retry confirms profile save and persists after reload');
    await admin(db=>db.doc(`users/${a}`).update({approvalStatus:'suspended'}));await text('APPROVAL REVOKED / REJECTED');
    const locked=page.getByRole('button',{name:'Approval required',exact:true});assert.equal(await locked.isDisabled(),true);
    checks.push('revoked approval disables publication without login');
    await button('Sign Out');await text('5KM Sandhai');assert.equal(await page.getByText('Persistent offer A',{exact:false}).or(page.getByLabel('Persistent offer A',{exact:false})).count(),0);
    const emailB=`phase3-vendor-b-${stamp}@example.com`;const b=await createAccount(emailB);
    await admin(async db=>{
      const now=new Date();await db.doc(`users/${b.localId}`).set({displayName:'Store B',email:emailB,role:'vendor',approvalStatus:'approved',createdAt:now});
      await db.doc(`vendors/${b.localId}`).set({name:'Store B',phone:'9876543210',category:'Groceries',latitude:13.0827,longitude:80.2707,geohash:'tf346c',createdAt:now});
      await db.doc(`offers/private-b-${stamp}`).set({vendorId:b.localId,title:'Private draft B',description:'B only',oldPrice:100,newPrice:50,imageUrl:'',latitude:13.0827,longitude:80.2707,geohash:'tf346c',createdAt:now,expiryTime:new Date(+now+3600000),status:'draft'});
    });
    await signIn(emailB);await text('Private draft B');assert.equal(await page.getByText('Persistent offer A',{exact:false}).or(page.getByLabel('Persistent offer A',{exact:false})).count(),0);
    checks.push('logout/account switch clears account A and shows only account B private dashboard');
    await button('Sign Out');await text('5KM Sandhai');
    const emailC=`phase3-incomplete-${stamp}@example.com`;const c=await createAccount(emailC);
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
    await page.screenshot({path:path.join(artifacts,'final.png')});
    assert.deepEqual(errors,[]);
    fs.writeFileSync(path.join(artifacts,'checks.json'),JSON.stringify(checks,null,2));
    console.log(JSON.stringify({result:'PASS',browser:await browser.version(),checks,artifact:artifacts},null,2));
  } catch(error) {
    if(page){await page.screenshot({path:path.join(artifacts,'failure.png')}).catch(()=>{});console.error('Visible semantics:',(await page.locator('body').innerText().catch(()=>'' )).slice(0,2500));console.error('Textbox count:',await page.getByRole('textbox').count().catch(()=>-1));}
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
