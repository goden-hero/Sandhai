/* Real Chrome UI + independent backend evidence. Local emulators only. Run the
 * Android companion after flow.json is written; no collection/app-data resets. */
const fs=require('node:fs'), fsp=require('node:fs/promises'), path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {chromium}=require('playwright-core');
const root=path.resolve(__dirname,'..'), web=path.join(root,'build/emulator-web');
const artifacts=process.env.SANDHAI_ARTIFACTS;
assert.ok(artifacts,'Set SANDHAI_ARTIFACTS to a new evidence directory');fs.mkdirSync(artifacts,{recursive:true});
const projectId='sandhai-5km-demo', host='127.0.0.1', stamp=Date.now();
const original=fs.readFileSync(path.join(root,'firestore.rules'),'utf8');
const center=JSON.parse(process.env.SANDHAI_CENTER||'{"latitude":13.0276441,"longitude":77.6129353}');
const password='Phase4NearbyPass123', vendorEmail=`phase4-vendor-${stamp}@example.com`,customerEmail=`phase4-customer-${stamp}@example.com`;
const title=`Phase4 live photo ${stamp}`, checks=[];
let env,browser,server;const pages=[];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function waitFile(name,seconds=600){for(let n=0;n<seconds;n++){if(fs.existsSync(path.join(artifacts,name)))return;await delay(1000);}throw Error(`Timed out waiting for ${name}`);}
async function rules(content){const r=await fetch(`http://${host}:8080/emulator/v1/projects/${projectId}:securityRules`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({rules:{files:[{name:'firestore.rules',content}]}})});assert.ok(r.ok,await r.text());}
function hash(lat,lng){const chars='0123456789bcdefghjkmnpqrstuvwxyz';let minLat=-90,maxLat=90,minLng=-180,maxLng=180,even=true,out='',bits=0,num=0;while(out.length<6){let mid=even?(minLng+maxLng)/2:(minLat+maxLat)/2;const v=even?lng:lat;num=(num<<1)+(v>=mid?1:0);if(even){if(v>=mid)minLng=mid;else maxLng=mid;}else{if(v>=mid)minLat=mid;else maxLat=mid;}even=!even;if(++bits===5){out+=chars[num];bits=0;num=0;}}return out;}
function north(m){return center.latitude+m*180/(6371000*Math.PI);}
const types={'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json','.png':'image/png','.ttf':'font/ttf','.otf':'font/otf'};
(async()=>{try{
 env=await initializeTestEnvironment({projectId,firestore:{host,port:8080,rules:original}});
 async function admin(fn){let result;await env.withSecurityRulesDisabled(async c=>result=await fn(c.firestore()));return result;}
 server=http.createServer(async(req,res)=>{try{const url=new URL(req.url,'http://localhost'), file=path.resolve(web,url.pathname==='/'?'index.html':decodeURIComponent(url.pathname).replace(/^\//,''));if(!file.startsWith(web+'/'))throw Error('path');res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream'});res.end(await fsp.readFile(file));}catch(e){res.writeHead(404);res.end();}});
 await new Promise(r=>server.listen(0,host,r));const url=`http://${host}:${server.address().port}`;
 browser=await chromium.launch({executablePath:process.env.CHROME_EXECUTABLE||'/usr/bin/google-chrome',headless:true,args:['--no-sandbox']});
 async function client(){const context=await browser.newContext({viewport:{width:1280,height:1800},permissions:['geolocation'],geolocation:{...center,accuracy:5}});const page=await context.newPage();pages.push(page);const errors=[];page.on('pageerror',e=>errors.push(e.message));return {context,page,errors};}
 const vendor=await client(), customer=await client();
 async function open(c,reload=false){if(reload)await c.page.reload({waitUntil:'load'});else await c.page.goto(url,{waitUntil:'load'});await c.page.locator('flutter-view').waitFor({timeout:60000});const a=c.page.locator('flt-semantics-placeholder');if(await a.count())await a.evaluate(e=>e.click());}
 async function text(c,t){await c.page.getByText(t,{exact:false}).or(c.page.getByLabel(t,{exact:false})).first().waitFor({timeout:45000});}
 async function button(c,t){await c.page.getByRole('button',{name:new RegExp(t.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))}).first().click();}
 async function fill(c,i,value){const field=c.page.getByRole('textbox').nth(i);await field.focus();await c.page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));await field.fill(value);await c.page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));}
 async function absent(c,t){assert.equal(await c.page.getByText(t,{exact:false}).or(c.page.getByLabel(t,{exact:false})).count(),0,t);}
 await open(vendor);await button(vendor,'I want to sell excess stock');await text(vendor,'Vendor Registration');
 for(const [i,v] of ['Phase4 Store','9876543210','Phase4 address','Nearby verification',vendorEmail,password,password].entries())await fill(vendor,i,v);
 await button(vendor,'Submit Vendor Registration');await text(vendor,'APPROVAL PENDING');
 const uid=await admin(async db=>(await db.collection('users').where('email','==',vendorEmail).get()).docs[0].id);
 await admin(db=>db.doc(`users/${uid}`).update({approvalStatus:'approved'}));await text(vendor,'APPROVED');
 await button(vendor,'Business profile');await button(vendor,'Confirm / edit store location');await button(vendor,'Suggest device location');
 await vendor.page.getByRole('button',{name:'Suggest device location',exact:true}).waitFor();await vendor.page.waitForFunction(()=>document.querySelector('[role=checkbox]')?.getAttribute('aria-disabled')!=='true');await vendor.page.getByRole('checkbox').click();await button(vendor,'Save confirmed location');await text(vendor,'Vendor Profile');
 const store=await admin(async db=>(await db.doc(`vendors/${uid}`).get()).data());assert.equal(store.latitude,center.latitude);assert.equal(store.longitude,center.longitude);
 await vendor.page.getByRole('button',{name:'Back',exact:true}).click();
 await open(customer);await button(customer,"I'm here to shop");await text(customer,'Customer Registration');
 for(const [i,v] of ['Phase4 Customer',customerEmail,password,password].entries())await fill(customer,i,v);
 await button(customer,'Create Customer Account');await text(customer,'Find offers near you');await button(customer,'Use my location');
 
 await fill(customer,0,String(stamp));await text(customer,'No clearance offers found');
 const customerUid=await admin(async db=>(await db.collection('users').where('email','==',customerEmail).get()).docs[0].id);
 const base={vendorId:uid,title:title+' outside',description:'Independent 10 km north fixture',category:'fresh_produce',oldPrice:100,newPrice:50,imageUrl:'',latitude:north(10000),longitude:center.longitude,geohash:hash(north(10000),center.longitude),locationConfirmedAt:store.locationConfirmedAt,createdAt:new Date(),expiryTime:new Date(Date.now()+3600000),status:'active'};
 const outsideId=`phase4-outside-${stamp}`;await admin(db=>db.doc(`offers/${outsideId}`).set(base));await delay(1500);await absent(customer,base.title);
 checks.push('separate Chrome vendor/customer sessions use shared foreground location and exclude an independently projected 10 km fixture');
 const flow={projectId,stamp,vendorEmail,customerEmail,password,vendorUid:uid,customerUid,title,center,outsideId,outsideTitle:base.title};
 fs.writeFileSync(path.join(artifacts,'flow.json'),JSON.stringify(flow,null,2));console.log('READY: flow.json; start Android --stage customer');
 if(process.env.SANDHAI_PHONE==='1')await waitFile('phone-ready.json');
 await button(vendor,'Post Clearance Offer');
 for(const [i,v] of [title,'Real grocery photo; live nearby publication','100','50'].entries())await fill(vendor,i,v);
 await button(vendor,'Groceries');await vendor.page.getByRole('menuitem',{name:'Fresh Produce',exact:true}).click();
 const picker=vendor.page.waitForEvent('filechooser');await button(vendor,'Choose photo');await(await picker).setFiles(path.join(root,'test/fixtures/grocery-photo.jpg'));await text(vendor,'image/jpeg');
 await button(vendor,'Publish Clearance Offer');await text(vendor,title);
 const saved=await admin(async db=>(await db.collection('offers').where('vendorId','==',uid).get()).docs.filter(d=>d.data().title===title));assert.equal(saved.length,1);
 const offerId=saved[0].id, data=saved[0].data();assert.equal(data.geohash,hash(center.latitude,center.longitude));assert.equal(data.category,'fresh_produce');assert.ok(data.locationConfirmedAt);
 const metadata=await(await fetch(`http://${host}:9199/v0/b/${projectId}.appspot.com/o/${encodeURIComponent(data.imagePath)}`)).json();assert.equal(metadata.contentType,'image/jpeg');assert.equal(Number(metadata.size),fs.statSync(path.join(root,'test/fixtures/grocery-photo.jpg')).size);
 assert.deepEqual(Buffer.from(await(await fetch(data.imageUrl)).arrayBuffer()),fs.readFileSync(path.join(root,'test/fixtures/grocery-photo.jpg')));
 await text(customer,title);await customer.page.getByLabel('Saved offer photo',{exact:false}).first().waitFor();await absent(customer,base.title);
 await customer.page.screenshot({path:path.join(artifacts,'chrome-live-nearby.png')});
 Object.assign(flow,{offerId,offer:data,imageMetadata:metadata});fs.writeFileSync(path.join(artifacts,'flow.json'),JSON.stringify(flow,null,2));fs.writeFileSync(path.join(artifacts,'published.json'),JSON.stringify({offerId}));
 checks.push('real photo/category publication appears live in the separate customer session; server document, image metadata and bytes independently agree');
 if(process.env.SANDHAI_PHONE==='1')await waitFile('phone-observed.json');console.log('Observed publication; checking category and query retry');
 // Live removal/status changes, category filtering, query error and retry.
 await customer.page.getByRole('checkbox',{name:'Groceries',exact:true}).click();
 await text(customer,'No clearance offers found');await customer.page.getByRole('checkbox',{name:'All',exact:true}).click();await text(customer,title);
 const denied=original.replace("allow read: if (resource.data.status == 'active')",`allow read: if (resource.data.status == 'active' && request.auth.uid != '${customerUid}')`);assert.notEqual(denied,original);
 try{await rules(denied);console.log('Query denial installed; opening fresh bounds');await customer.context.setGeolocation({latitude:0,longitude:0,accuracy:5});await button(customer,'Update customer location');await text(customer,'Could not load nearby offers');await customer.page.screenshot({path:path.join(artifacts,'chrome-query-failed.png')});}finally{await rules(original);}
 console.log('Retrying query');await button(customer,'Retry nearby offers');await text(customer,'No clearance offers found');await customer.context.setGeolocation({...center,accuracy:5});await button(customer,'Update customer location');await text(customer,title);checks.push('category filter uses persisted ID; a denied bound query shows error, and retry restores the feed');
 // Set an imminent expiry exactly once. No Firestore write occurs during removal.
 const expiry=new Date(Date.now()+(process.env.SANDHAI_PHONE==='1'?60000:6000));await admin(db=>db.doc(`offers/${offerId}`).update({expiryTime:expiry}));
 const beforeExpiry=await fetch(`http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/offers/${offerId}`,{headers:{Authorization:'Bearer owner'}}).then(r=>r.json());
 console.log('Expiry scheduled',expiry.toISOString());fs.writeFileSync(path.join(artifacts,'expiry-start.json'),JSON.stringify({offerId,title,expiry:expiry.toISOString(),updateTime:beforeExpiry.updateTime}));
 await customer.page.getByText('No clearance offers found',{exact:false}).or(customer.page.getByLabel('No clearance offers found',{exact:false})).first().waitFor({timeout:90000});await absent(customer,title);await customer.page.screenshot({path:path.join(artifacts,'chrome-expired-without-refresh.png')});
 const afterExpiry=await fetch(`http://${host}:8080/v1/projects/${projectId}/databases/(default)/documents/offers/${offerId}`,{headers:{Authorization:'Bearer owner'}}).then(r=>r.json());assert.equal(afterExpiry.updateTime,beforeExpiry.updateTime);assert.equal(afterExpiry.fields.status.stringValue,'active');
 checks.push('expiry removes the visible offer without refresh or another backend event; independent updateTime unchanged, backend status still active');
 if(process.env.SANDHAI_PHONE==='1')await waitFile('phone-expired.json');
 // Fresh location refresh, reload, then independent 4.99/5.00/5.01 km fixtures.
 await customer.context.setGeolocation({latitude:0,longitude:0,accuracy:5});await button(customer,'Update customer location');
 const boundaryTitle=`Phase4 boundary ${stamp}`;
 for(const [suffix,lat] of [['4990',.044876148135344655],['5000',.044966080295936524],['5010',.045056012456528396]]) await admin(db=>db.doc(`offers/phase4-boundary-${stamp}-${suffix}`).set({...base,title:`${boundaryTitle} ${suffix}`,latitude:lat,longitude:0,geohash:hash(lat,0),expiryTime:new Date(Date.now()+3600000)}));
 await fill(customer,0,boundaryTitle.slice('Phase4 '.length));await text(customer,`${boundaryTitle} 4990`);await text(customer,`${boundaryTitle} 5000`);await absent(customer,`${boundaryTitle} 5010`);
 await customer.page.screenshot({path:path.join(artifacts,'chrome-radius-boundaries.png')});
 await open(customer,true);await text(customer,'Find offers near you');await button(customer,'Use my location');await fill(customer,0,boundaryTitle.slice('Phase4 '.length));await text(customer,`${boundaryTitle} 5000`);await absent(customer,`${boundaryTitle} 5010`);
 checks.push('location replacement and browser reload create fresh subscriptions; independently calculated 4990/5000/5010 m fixtures include/include/exclude');
 assert.deepEqual(vendor.errors,[]);assert.deepEqual(customer.errors,[]);
 fs.writeFileSync(path.join(artifacts,'checks.json'),JSON.stringify({result:'PASS',browser:await browser.version(),checks,flow},null,2));console.log(JSON.stringify({result:'PASS',checks,artifacts},null,2));
}catch(e){for(const [i,p] of pages.entries()){await p.screenshot({path:path.join(artifacts,`failure-${i}.png`)}).catch(()=>{});fs.writeFileSync(path.join(artifacts,`failure-${i}.html`),await p.content().catch(()=>''));}fs.writeFileSync(path.join(artifacts,'failure.txt'),e.stack);console.error(e);process.exitCode=1;}finally{await rules(original).catch(console.error);await browser?.close();await env?.cleanup();if(server)await new Promise(r=>server.close(r));}})();
