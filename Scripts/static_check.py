"""Non-Apple checks. These do NOT replace xcodebuild or simulator testing.
Install optional checker dependencies: pip install tree-sitter tree-sitter-swift pbxproj
"""
from pathlib import Path
import json,plistlib,re,xml.etree.ElementTree as ET
import tree_sitter,tree_sitter_swift
from pbxproj import XcodeProject
root=Path(__file__).resolve().parents[1]
parser=tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors=[]
files=list(root.rglob('*.swift'))
for file in files:
 data=file.read_bytes();tree=parser.parse(data)
 def walk(node):
  if node.type=='ERROR' or node.is_missing:errors.append(f'{file.relative_to(root)}:{node.start_point}: {node.type}')
  for child in node.children:walk(child)
 walk(tree.root_node)
project=XcodeProject.load(str(root/'Privofit.xcodeproj/project.pbxproj'))
assert project is not None
for file in root.rglob('*.plist'):plistlib.loads(file.read_bytes())
for file in root.rglob('*.xcprivacy'):plistlib.loads(file.read_bytes())
for file in root.rglob('*.entitlements'):plistlib.loads(file.read_bytes())
for file in root.rglob('*.xcscheme'):ET.parse(file)
for file in root.rglob('*.json'):json.loads(file.read_text())
catalog=json.loads((root/'Privofit/Resources/Localizable.xcstrings').read_text())['strings']
for key,entry in catalog.items():
 for lang in ['cs','en']:assert entry['localizations'][lang]['stringUnit']['value'],key
used=set()
for file in (root/'Privofit').rglob('*.swift'):
 used.update(re.findall(r'L10n\.tr\("([^"\\]+)"\)',file.read_text()))
assert not used-catalog.keys(),used-catalog.keys()
assert not errors,'\n'.join(errors)
print(f'PASS: syntax trees for {len(files)} Swift files; parsed Xcode project, plists, schemes, asset metadata; {len(catalog)} bilingual strings.')
print('NOT RUN: Swift type checking, compilation, XCTest, Swift Testing, UI tests, simulator rendering, signing, real API integration.')
