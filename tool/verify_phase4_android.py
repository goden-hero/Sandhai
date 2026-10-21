"""Physical Android customer paired with verify_phase4_browser.cjs.
Uses normal UI/foreground GPS and independent REST reads. Never resets app data.
"""
import argparse,json,time
from datetime import datetime,timedelta,timezone
from pathlib import Path
from verify_phase2_android import Phone,Emulator

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--adb',required=True);p.add_argument('--serial',default='373c972d');p.add_argument('--artifacts',required=True,type=Path);p.add_argument('--stage',choices=['customer','observe','expiry','resume'],required=True);a=p.parse_args()
 a.artifacts.mkdir(parents=True,exist_ok=True);flow=json.loads((a.artifacts/'flow.json').read_text());phone=Phone(a.adb,a.serial,a.artifacts);backend=Emulator();checks=[]
 try:
  if a.stage=='customer':
   phone.run('shell','am','start','-n','com.sandhai.app/.MainActivity');phone.wait_any(['Your offers','Nearby offers','Local development'],timeout=70)
   nodes=phone.nodes()
   if any('Your offers' in phone.label(n) for n in nodes):phone.tap('Sign Out')
   elif any('Nearby offers' in phone.label(n) for n in nodes):
    phone.tap('Profile & Settings');phone.tap('Sign Out',seek=True)
   phone.wait('Local development');phone.tap('Sign In');phone.wait('Welcome Back')
   phone.fill('Email Address',flow['customerEmail']);phone.fill('Password',flow['password']);phone.tap('Sign In',seek=True)
   phone.wait('Find offers near you');pids=phone.restart();phone.wait('Find offers near you')
   phone.tap('Use my location');phone.wait_any(['No clearance offers found','Contact Vendor','Location unavailable'],timeout=70)
   phone.absent('Location unavailable');phone.fill('Search clearance items', str(flow['stamp']),field_index=0);phone.wait('No clearance offers found')
   phone.capture('android-01-customer-location-ready');checks.append('Customer sign-in survives force-close/reopen; foreground GPS used without manual/mock customer coordinates')
   (a.artifacts/'phone-ready.json').write_text(json.dumps({'result':'PASS','pids':pids,'checks':checks},indent=2))
  elif a.stage=='observe':
   phone.wait(flow['title'],timeout=80);phone.absent(flow['outsideTitle']);phone.capture('android-02-live-photo-nearby')
   phone.tap('Groceries');phone.wait('No clearance offers found');phone.tap('All');phone.wait(flow['title']);phone.capture('android-02b-category-restored')
   saved=backend.get('offers/'+flow['offerId']);assert saved['category']=='fresh_produce';assert saved.get('locationConfirmedAt');assert saved['geohash']==flow['offer']['geohash'];assert saved['imageContentType']=='image/jpeg'
   checks.append('Chrome vendor real-photo publication appears live on Android customer; outside-radius fixture excluded; independent backend fields match')
   (a.artifacts/'phone-observed.json').write_text(json.dumps({'result':'PASS','checks':checks,'offer':saved},indent=2))
  elif a.stage=='expiry':
   if any('Could not load nearby offers' in phone.label(n) for n in phone.nodes()):
    phone.capture('android-query-failed');phone.tap('Retry nearby offers');phone.wait(flow['title'])
   phone.capture('android-before-expiry')
   phone.wait('No clearance offers found',timeout=100);phone.absent(flow['title']);phone.capture('android-03-expired-without-refresh')
   saved=backend.get('offers/'+flow['offerId']);assert saved['status']=='active'
   checks.append('Offer disappears on foreground phone at expiry without refresh; backend still active')
   (a.artifacts/'phone-expired.json').write_text(json.dumps({'result':'PASS','checks':checks},indent=2))
  elif a.stage=='resume':
   # Trusted local fixture: extend the same real publication once, then leave
   # Firestore untouched while it expires in the background. No edit UI added.
   expiry=datetime.now(timezone.utc)+timedelta(seconds=25)
   raw=backend.request(backend.documents+'/offers/'+flow['offerId']+'?updateMask.fieldPaths=expiryTime',{'fields':{'expiryTime':{'timestampValue':expiry.isoformat().replace('+00:00','Z')}}},method='PATCH')
   phone.wait(flow['title']);phone.capture('android-04-before-background')
   phone.run('shell','input','keyevent','3');time.sleep(30);phone.run('shell','am','start','-n','com.sandhai.app/.MainActivity')
   phone.wait('No clearance offers found');phone.absent(flow['title']);phone.capture('android-05-resumed-expired')
   after=backend.request(backend.documents+'/offers/'+flow['offerId']);assert after['updateTime']==raw['updateTime'];assert after['fields']['status']['stringValue']=='active'
   checks.append('Real Android HOME/background/resume removes expiry without refresh or another backend write; updateTime unchanged')
   (a.artifacts/'phone-background.json').write_text(json.dumps({'result':'PASS','checks':checks,'expiry':expiry.isoformat(),'unchangedUpdateTime':after['updateTime']},indent=2))
  print(json.dumps({'result':'PASS','stage':a.stage,'checks':checks},indent=2),flush=True)
 except Exception:
  phone.capture('android-failure-'+a.stage);raise
 finally:(a.artifacts/('adb-commands-'+a.stage+'.json')).write_text(json.dumps(phone.commands,indent=2))
if __name__=='__main__':main()
