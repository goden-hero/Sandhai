"""Reclaim the background app during its real Android picker; verify lost-data recovery."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from verify_phase3_android import Device
from verify_phase2_android import PACKAGE

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb',required=True);parser.add_argument('--serial',default='373c972d');parser.add_argument('--artifacts',required=True,type=Path)
    args=parser.parse_args();phone=Device(args.adb,args.serial,args.artifacts)
    state_file=args.artifacts/'state.json';state=json.loads(state_file.read_text())
    try:
        old=phone.run('shell','pidof',PACKAGE).strip()
        phone.run('shell','am','kill',PACKAGE)
        time.sleep(1)
        try: remaining=phone.run('shell','pidof',PACKAGE).strip()
        except subprocess.CalledProcessError: remaining=''
        assert not remaining,'Android did not reclaim the background process; recovery cannot be claimed.'
        # Select only the staged public photo; never select a personal album item.
        phone.system_tap('grocery-photo.jpg')
        phone.wait('Recover selected photo and draft',timeout=70)
        new=phone.run('shell','pidof',PACKAGE).strip();assert old!=new
        phone.capture('06a-recovery-offered')
        phone.tap('Recover selected photo and draft');phone.wait('Post Clearance Offer')
        for _ in range(6):
            if any('image/jpeg' in phone.label(n) for n in phone.nodes()):break
            phone.scroll()
        phone.wait('image/jpeg');phone.capture('06b-recovered-photo-draft')
        state['pickerRecovery']={'oldPid':old,'newPid':new,'result':'PASS'}
        state['checks'].append('Android background process reclaimed while picker open; selected real photo and same-ID vendor draft recovered after process restart')
    finally:
        state_file.write_text(json.dumps(state,indent=2))
        (args.artifacts/'adb-commands-picker-recovery.json').write_text(json.dumps(phone.commands,indent=2))
    print(json.dumps(state['pickerRecovery'],indent=2))

if __name__=='__main__':main()
