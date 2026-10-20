"""Leave the normal app signed into its verified synthetic vendor after integration tests."""
import argparse
import json
from pathlib import Path
from verify_phase3_android import Device
from verify_phase2_android import Emulator

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb',required=True);parser.add_argument('--serial',default='373c972d');parser.add_argument('--artifacts',required=True,type=Path)
    args=parser.parse_args();phone=Device(args.adb,args.serial,args.artifacts);file=args.artifacts/'state.json';state=json.loads(file.read_text())
    assert state['email'].startswith('android-phase3-') and state['email'].endswith('@example.com')
    try:
        phone.wait_any(['Your offers','Local development'],timeout=70)
        if any('Sign Out' in phone.label(n) for n in phone.nodes()):phone.tap('Sign Out');phone.wait('Local development')
        phone.tap('Sign In');phone.wait('Welcome Back')
        phone.fill('Email Address',state['email']);phone.fill('Password',state['password'])
        phone.tap('Sign In',seek=True);phone.wait('Your offers');phone.wait(state['title']);phone.capture('10-final-account-restored')
        transition=phone.restart();phone.wait('Your offers');phone.wait(state['title']);phone.capture('11-final-session-restored')
        offer=Emulator().get('offers/'+state['offer']['id']);assert offer['vendorId']==state['uid'] and offer['imagePath']==state['offer']['imagePath']
        state['finalSignInAndRestart']={'result':'PASS',**transition}
        state['checks']=list(dict.fromkeys(state['checks']+['Existing synthetic vendor signs in and restores its real photo offer after another restart on the final normal APK']))
    finally:
        file.write_text(json.dumps(state,indent=2));(args.artifacts/'adb-commands-final-restore.json').write_text(json.dumps(phone.commands,indent=2))
    print(json.dumps(state['finalSignInAndRestart'],indent=2))

if __name__=='__main__':main()
