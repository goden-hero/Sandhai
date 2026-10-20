"""Physical Android UI probe; real system picker and foreground GPS, no app bridge.
Run with a normal emulator-mode APK installed. Never resets emulator/app data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from verify_phase2_android import Phone, Emulator, PACKAGE, PROJECT, ROOT

class Device(Phone):
    def all_nodes(self):
        file='/data/local/tmp/sandhai-phase3-system.xml'
        self.run('shell','uiautomator','dump',file)
        return [n.attrib for n in ET.fromstring(self.run('exec-out','cat',file)).iter('node')]
    def system_tap(self, text):
        for node in self.all_nodes():
            if text.lower() in self.label(node).lower():
                self.tap_node(node);return
        raise AssertionError(f'System picker/permission control not found: {text}')
    def inputs(self):
        return [n for n in self.nodes() if n.get('class')=='android.widget.EditText']

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb',required=True);parser.add_argument('--serial',default='373c972d');parser.add_argument('--artifacts',required=True,type=Path)
    parser.add_argument('--stage',choices=['location','gps','photo','reselect','finish','inspect'],default='location')
    args=parser.parse_args();args.artifacts.mkdir(parents=True,exist_ok=True)
    phone=Device(args.adb,args.serial,args.artifacts);backend=Emulator()
    state_file=args.artifacts/'state.json'
    state=json.loads(state_file.read_text()) if state_file.exists() else {'checks':[]}
    try:
        if args.stage=='inspect': print(json.dumps(phone.inspect(),indent=2));return
        if args.stage=='location':
            phone.wait_any(['Local development','Your offers'])
            if any('Sign Out' in phone.label(n) for n in phone.nodes()):phone.tap('Sign Out');phone.wait('Local development')
            stamp=int(time.time());email=f'android-phase3-{stamp}@example.com'
            state.update(email=email,name=f'Android Phase3 {stamp}',password='AndroidPhase3Pass123')
            phone.tap('I want to sell excess stock');phone.wait('Vendor Registration')
            for label,value in [('Store / Business Name',state['name']),('Phone Number','9876543210'),('Business Address','Phase3 verification store'),('Business Description','Real device location and image verification'),('Email Address',email),('Password',state['password']),('Confirm Password',state['password'])]:phone.fill(label,value)
            phone.tap('Submit Vendor Registration',seek=True);phone.wait('APPROVAL PENDING')
            rows=backend.query('users','email',email);assert len(rows)==1;state['uid']=rows[0]['id']
            store=backend.get('vendors/'+state['uid']);assert 'latitude' not in store and 'locationConfirmedAt' not in store
            backend.patch('users/'+state['uid'],'approvalStatus','approved');phone.wait('APPROVED')
            phone.tap('Business profile');phone.wait('Vendor Profile');phone.tap('Confirm / edit store location');phone.wait('Confirm store location')
        if args.stage in ['location','gps']:
            phone.capture('01-empty-location')
            phone.tap('Suggest device location');time.sleep(1)
            # Verify first denial through the real Android permission dialog.
            nodes=phone.all_nodes()
            if any('deny' in phone.label(n).lower() for n in nodes):
                phone.system_tap('Deny');phone.wait('Location permission was denied');phone.capture('02-permission-denied')
                assert all(not n.get('text') for n in phone.inputs())
                state['checks'].append('Real Android foreground permission denied: visible error and empty coordinates')
                phone.tap('Suggest device location');time.sleep(1)
            nodes=phone.all_nodes()
            options=[n for n in nodes if re.search(r'allow|while using',phone.label(n),re.I) and n.get('clickable')=='true']
            if options:phone.tap_node(options[0])
            deadline=time.monotonic()+28
            while time.monotonic()<deadline:
                fields=phone.inputs()
                if len(fields)==2 and all(n.get('text') for n in fields):break
                time.sleep(1)
            fields=phone.inputs();phone.capture('03-device-location-result')
            if len(fields)!=2 or not all(n.get('text') for n in fields):
                state['locationBlocked']='No real GPS fix returned. No fabricated coordinates were substituted.'
                raise AssertionError(state['locationBlocked'])
            lat,lng=map(lambda n:float(n['text']),fields);assert -90<=lat<=90 and -180<=lng<=180
            state.update(latitude=lat,longitude=lng)
            assert 'locationConfirmedAt' not in backend.get('vendors/'+state['uid'])
            phone.tap('I confirm this is my store location');phone.tap('Save confirmed location',seek=True);phone.wait('Vendor Profile')
            store=backend.get('vendors/'+state['uid']);assert store['latitude']==lat and store['longitude']==lng and store['locationConfirmedAt']
            state['store']=store;phone.capture('04-confirmed-store');state['checks'].append('Real device coordinates explicitly confirmed on phone and independently read from Firestore')
        elif args.stage=='photo':
            if any('Vendor Profile' in phone.label(n) for n in phone.nodes()):phone.tap('Back')
            phone.wait('Your offers');phone.tap('Post Clearance Offer');phone.wait('Offer Title')
            title='Android real photo '+str(int(time.time()));state['title']=title
            for label,value in [('Offer Title',title),('Offer Description','Real grocery photo selected on Android'),('Original Price','100'),('Clearance Price','50')]:phone.fill(label,value)
            # Select a stable category via the existing dropdown.
            phone.scroll(up=True)
            phone.tap('Groceries',seek=True);phone.tap('Fresh Produce',seek=True)
            phone.tap('Choose photo',seek=True);time.sleep(1)
            print('SYSTEM PICKER:',json.dumps([{k:n.get(k) for k in ['text','content-desc','class','bounds']} for n in phone.all_nodes() if phone.label(n).strip()],indent=2),flush=True)
            # Cancel via the actual system Back action; fields remain intact.
            phone.run('shell','input','keyevent','4');phone.wait('Choose photo');phone.capture('05-picker-cancelled')
            phone.tap('Choose photo');time.sleep(1)
            print('Choose the staged grocery photo with --stage finish after selecting it.',flush=True)
        elif args.stage=='reselect':
            phone.wait('Resume unsaved offer',timeout=70);phone.tap('Resume unsaved offer');phone.wait('Post Clearance Offer')
            phone.tap('Choose photo',seek=True);time.sleep(1);phone.system_tap('grocery-photo.jpg')
            for _ in range(6):
                if any('image/jpeg' in phone.label(n) for n in phone.nodes()):break
                phone.scroll()
            phone.wait('image/jpeg');phone.capture('06d-reselected-after-emulator-recovery')
        elif args.stage=='finish':
            phone.wait('image/jpeg');phone.capture('06-real-photo-preview')
            uid=state['uid'];title=state['title']
            storage_rules=(ROOT/'storage.rules').read_text()
            def storage_policy(content):
                request=urllib.request.Request('http://127.0.0.1:9199/internal/setRules',data=json.dumps({'rules':{'files':[{'name':'storage.rules','content':content}]}}).encode(),method='PUT',headers={'Content-Type':'application/json'})
                with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(request,timeout=20) as response: assert response.status==200
            denied_storage=storage_rules.replace('return request.auth != null',f"return request.auth != null && request.auth.uid != '{uid}'",1)
            try:
                storage_policy(denied_storage)
                phone.tap('Publish Clearance Offer',seek=True);phone.wait('server rejected');phone.capture('06c-upload-denied-retained')
                assert len(backend.query('offers','vendorId',uid))==0
                state['checks'].append('Real Storage upload denied on phone: visible error, retained photo/form, no offer or success')
            finally: storage_policy(storage_rules)
            deny=backend.original_rules.replace('allow create: if isApprovedVendor() && validOffer',f"allow create: if request.resource.data.title != '{title}' && isApprovedVendor() && validOffer")
            assert deny!=backend.original_rules
            try:
                backend.rules(deny);phone.tap('Publish Clearance Offer',seek=True);phone.wait('server rejected');phone.capture('07-publication-denied')
                assert len(backend.query('offers','vendorId',uid))==0
                listing=f'http://127.0.0.1:9199/v0/b/{PROJECT}.appspot.com/o?prefix='+urllib.parse.quote('offers/'+uid+'/',safe='')
                with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(urllib.request.Request(listing,headers={'Authorization':'Bearer owner'}),timeout=20) as response:
                    assert len(json.load(response).get('items',[]))==0
                state['checks'].append('Real photo publication denied by Firestore: visible error, retained fields/photo, no false success')
            finally:backend.rules(backend.original_rules)
            phone.tap('Publish Clearance Offer',seek=True);phone.wait('Your offers');phone.wait(title)
            rows=backend.query('offers','vendorId',uid);assert len(rows)==1;offer=rows[0]
            assert offer['latitude']==state['latitude'] and offer['longitude']==state['longitude'] and offer['geohash']==state['store']['geohash']
            assert offer['category']=='fresh_produce' and offer['imageContentType']=='image/jpeg'
            local=(ROOT/'test/fixtures/grocery-photo.jpg').read_bytes();digest=hashlib.sha256(local).hexdigest()
            assert offer['imagePath'].endswith('/'+digest+'.jpg') and int(offer['imageSize'])==len(local)
            base=f'http://127.0.0.1:9199/v0/b/{PROJECT}.appspot.com/o/'
            opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
            metadata=json.load(opener.open(base+urllib.parse.quote(offer['imagePath'],safe='')))
            assert metadata['contentType']=='image/jpeg' and int(metadata['size'])==len(local)
            assert opener.open(offer['imageUrl']).read()==local
            state.update(offer=offer,imageMetadata=metadata);phone.capture('08-published-offer')
            state['restart']=phone.restart();phone.wait('Your offers');phone.wait(title);phone.capture('09-restarted-offer-photo')
            assert backend.get('offers/'+offer['id'])['imagePath']==offer['imagePath']
            state['checks'].append('Successful retry publishes one offer and photo; independent Firestore/Storage reads verify coordinates, geohash, category, MIME, digest and bytes; restart restores offer/photo')
            state['result']='PASS'
    finally:
        state['checks']=list(dict.fromkeys(state['checks']))
        state_file.write_text(json.dumps(state,indent=2));(args.artifacts/f'adb-commands-{args.stage}.json').write_text(json.dumps(phone.commands,indent=2))
    print(json.dumps(state,indent=2))

if __name__=='__main__':main()
