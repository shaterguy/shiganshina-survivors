#!/usr/bin/env python3
"""Verify unsigned APK contents against pinned tools and current approved source."""
import argparse
import json
import sys
from pathlib import Path
from android_common import BuildError, ROOT, read_manifest, verify_apk


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk',type=Path)
    parser.add_argument('--template',type=Path,required=True)
    parser.add_argument('--development-validation', action='store_true', help='Verify only the explicit incomplete development package')
    args=parser.parse_args()
    try:
        print(json.dumps(verify_apk(args.apk,args.template,ROOT,read_manifest(ROOT, development_validation=args.development_validation), development_validation=args.development_validation),indent=2))
        return 0
    except (BuildError,OSError,ValueError) as exc:
        print('VERIFY_BLOCKED: '+str(exc),file=sys.stderr)
        return 2

if __name__ == '__main__': sys.exit(main())
