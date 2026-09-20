from pathlib import Path
import hashlib,json,plistlib
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
A=R/'Privofit/Resources/Assets.xcassets';A.mkdir(parents=True,exist_ok=True)
(A/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
colors={'Background':('E8F0E4','0B1210'),'Surface':('FFFFFF','17221B'),'PrimaryText':('101714','E8F0E4'),'SecondaryText':('536259','AFB9AC'),'AccentColor':('101714','C6F21A'),'Lime':('C6F21A','C6F21A'),'Success':('1F8A4C','69C687'),'Danger':('B42C2C','F18B8B')}
for name,(light,dark) in colors.items():
 d=A/(name+'.colorset');d.mkdir(exist_ok=True)
 def color(v): return {'color-space':'srgb','components':dict(zip(('red','green','blue','alpha'),[f'{int(v[i:i+2],16)/255:.6f}' for i in (0,2,4)]+['1.000']))}
 (d/'Contents.json').write_text(json.dumps({'colors':[{'idiom':'universal','color':color(light)},{'idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}],'color':color(dark)}],'info':{'author':'xcode','version':1}},indent=2))
icon=A/'AppIcon.appiconset';icon.mkdir(exist_ok=True)
im=Image.new('RGB',(1024,1024),'#C6F21A');draw=ImageDraw.Draw(im)
# Geometric P derived from the supplied website's simple lime/P brand mark.
draw.polygon([(300,245),(555,245),(710,290),(735,440),(660,552),(470,575),(435,790),(270,790)],fill='#101714')
draw.rounded_rectangle((465,355,595,450),radius=36,fill='#C6F21A')
im.save(icon/'AppIcon.png')
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
info={'CFBundleDevelopmentRegion':'cs','CFBundleDisplayName':'Privofit','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'UIApplicationSupportsIndirectInputEvents':True,'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UILaunchScreen':{'UIColorName':'Background'},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],'NSFaceIDUsageDescription':'Face ID chrání tvůj účet a potvrzuje vstup do Privofit.','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True},'APIBaseURL':'$(API_BASE_URL)','AppEnvironment':'$(APP_ENVIRONMENT)','GoogleClientID':'$(GOOGLE_CLIENT_ID)','GoogleRedirectURI':'$(GOOGLE_REDIRECT_URI)','SupportURL':'$(SUPPORT_URL)','PrivacyURL':'$(PRIVACY_URL)','TermsURL':'$(TERMS_URL)','CheckoutURL':'$(CHECKOUT_URL)','ApplePayMerchantID':'$(APPLE_PAY_MERCHANT_ID)','CFBundleURLTypes':[{'CFBundleURLName':'Google OAuth','CFBundleURLSchemes':['$(GOOGLE_CALLBACK_SCHEME)']}],'ITSAppUsesNonExemptEncryption':False,'FirebaseAppDelegateProxyEnabled':False,'UIBackgroundModes':['remote-notification']}
(R/'Privofit/Resources/Info.plist').write_bytes(plistlib.dumps(info))
(R/'Privofit/Resources/Privofit.entitlements').write_bytes(plistlib.dumps({'aps-environment':'$(APS_ENVIRONMENT)','com.apple.developer.applesignin':['Default'],'com.apple.developer.in-app-payments':['$(APPLE_PAY_MERCHANT_ID)']}))
(R/'Privofit/Resources/PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],'NSPrivacyCollectedDataTypes':[],'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryUserDefaults','NSPrivacyAccessedAPITypeReasons':['CA92.1']}]}))
for lang,text in [('cs','Face ID chrání tvůj účet a potvrzuje vstup do Privofit.'),('en','Face ID protects your account and confirms entry to Privofit.')]:
 d=R/f'Privofit/Resources/{lang}.lproj';d.mkdir(exist_ok=True);(d/'InfoPlist.strings').write_text('"NSFaceIDUsageDescription" = '+json.dumps(text,ensure_ascii=False)+';\n')
base='''// Public configuration only. Never put secrets in these files.
// Use https:/$()/your-domain/api/v1/ to avoid xcconfig // comment parsing.
API_BASE_URL =
GOOGLE_CLIENT_ID =
GOOGLE_REDIRECT_URI =
GOOGLE_CALLBACK_SCHEME = privofit-unconfigured
SUPPORT_URL =
TERMS_URL =
PRIVACY_URL =
CHECKOUT_URL =
APPLE_PAY_MERCHANT_ID = merchant.cz.privofit.app
'''
(R/'Configuration/Base.xcconfig').write_text(base)
(R/'Configuration/Development.xcconfig').write_text('''#include "Base.xcconfig"
APP_ENVIRONMENT = development
APS_ENVIRONMENT = development
API_BASE_URL = http:/$()/127.0.0.1/privofit/api/v1/
SUPPORT_URL = http:/$()/127.0.0.1/privofit/kontakt
TERMS_URL = http:/$()/127.0.0.1/privofit/dokument/obchodni-podminky
PRIVACY_URL = http:/$()/127.0.0.1/privofit/dokument/ochrana-udaju
CHECKOUT_URL = http:/$()/127.0.0.1/privofit/cenik
''')
for filename,environment,aps in [('Staging','staging','development'),('Production','production','production')]:
 (R/f'Configuration/{filename}.xcconfig').write_text('#include "Base.xcconfig"\nAPP_ENVIRONMENT = '+environment+'\nAPS_ENVIRONMENT = '+aps+'\n// Override API_BASE_URL, Apple Pay merchant ID and public OAuth configuration here.\n')
objects={}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def add(key,isa,**args):
 ident=uid(key);objects[ident]={'isa':isa,**args};return ident
def file(path,typ=None):
 ext=Path(path).suffix
 if typ is None:typ={'.swift':'sourcecode.swift','.xcconfig':'text.xcconfig','.plist':'text.plist.xml','.entitlements':'text.plist.entitlements','.xcstrings':'text.json.xcstrings','.xcprivacy':'text.xml','.strings':'text.plist.strings','.md':'net.daringfireball.markdown','.sh':'text.script.sh','.py':'text.script.python'}.get(ext,'text')
 return add('file:'+path,'PBXFileReference',lastKnownFileType=typ,name=Path(path).name,path=path,sourceTree='<group>')
def build(key,ref): return add('build:'+key,'PBXBuildFile',fileRef=ref)
appfiles=sorted((R/'Privofit').rglob('*.swift'));tests=sorted((R/'Tests').glob('*.swift'));ui=sorted((R/'UITests').glob('*.swift'))
groups={};sources={}
for name,files in [('Privofit',appfiles),('Tests',tests),('UITests',ui)]:
 sources[name]=[]
 for path in files:
  rel=str(path.relative_to(R));ref=file(rel);sources[name].append(build(rel,ref));group=rel.split('/')[1] if name=='Privofit' else name;groups.setdefault(group,[]).append(ref)
resources=[]
for path,typ in [('Privofit/Resources/Assets.xcassets','folder.assetcatalog'),('Privofit/Resources/Localizable.xcstrings',None),('Privofit/Resources/PrivacyInfo.xcprivacy',None)]:
 ref=file(path,typ);groups.setdefault('Resources',[]).append(ref);resources.append(build(path,ref))
localized=[]
for lang in ['cs','en']:
 localized.append(add('infostrings:'+lang,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=f'Privofit/Resources/{lang}.lproj/InfoPlist.strings',sourceTree='<group>'))
variant=add('infostrings','PBXVariantGroup',children=localized,name='InfoPlist.strings',sourceTree='<group>');resources.append(build('infostrings',variant));groups['Resources'].append(variant)
for name in ['Info.plist','Privofit.entitlements']:groups['Resources'].append(file('Privofit/Resources/'+name))
configs={}
for name in ['Base','Development','Staging','Production']:
 ref=file('Configuration/'+name+'.xcconfig');configs[name]=ref;groups.setdefault('Configuration',[]).append(ref)
products=[];targetids=[]
appTarget=uid('target:Privofit')
firebasePackage=add('package:firebase','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/firebase/firebase-ios-sdk',requirement={'kind':'upToNextMajorVersion','minimumVersion':'12.10.0'})
firebaseProduct=add('product:FirebaseMessaging','XCSwiftPackageProductDependency',package=firebasePackage,productName='FirebaseMessaging')
firebaseBuild=add('build:FirebaseMessaging','PBXBuildFile',productRef=firebaseProduct)
for name in ['Privofit','Tests','UITests']:
 isApp=name=='Privofit';isUI=name=='UITests';productName='Privofit' if isApp else 'Privofit'+name
 product=add('product:'+name,'PBXFileReference',explicitFileType='wrapper.application' if isApp else 'wrapper.cfbundle',includeInIndex=0,path=productName+('.app' if isApp else '.xctest'),sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
 phases=[add('sources:'+name,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources[name],runOnlyForDeploymentPostprocessing=0),add('frameworks:'+name,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[firebaseBuild] if isApp else [],runOnlyForDeploymentPostprocessing=0),add('resources:'+name,'PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources if isApp else [],runOnlyForDeploymentPostprocessing=0)]
 conf=[]
 for configuration,env in [('Debug','Development'),('Staging','Staging'),('Release','Production')]:
  settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'cz.privofit.app'+('' if isApp else '.'+name.lower()),'SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'27.0','SDKROOT':'iphoneos','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','TARGETED_DEVICE_FAMILY':'1','CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'complete','GENERATE_INFOPLIST_FILE':'NO' if isApp else 'YES'}
  if isApp:settings.update({'INFOPLIST_FILE':'Privofit/Resources/Info.plist','CODE_SIGN_ENTITLEMENTS':'Privofit/Resources/Privofit.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'1','ENABLE_PREVIEWS':'YES','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']})
  else:
   settings['LD_RUNPATH_SEARCH_PATHS']=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks'];settings['GENERATE_INFOPLIST_FILE']='YES'
   if isUI:settings['TEST_TARGET_NAME']='Privofit'
   else:settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Privofit.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Privofit','BUNDLE_LOADER':'$(TEST_HOST)'})
  conf.append(add('configuration:'+name+configuration,'XCBuildConfiguration',name=configuration,baseConfigurationReference=configs[env],buildSettings=settings))
 cfg=add('configs:'+name,'XCConfigurationList',buildConfigurations=conf,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
 deps=[]
 if not isApp:
  proxy=add('proxy:'+name,'PBXContainerItemProxy',containerPortal=uid('project'),proxyType=1,remoteGlobalIDString=appTarget,remoteInfo='Privofit')
  deps=[add('dependency:'+name,'PBXTargetDependency',target=appTarget,targetProxy=proxy)]
 targetids.append(add('target:'+name,'PBXNativeTarget',name=productName,productName=productName,productReference=product,productType='com.apple.product-type.application' if isApp else ('com.apple.product-type.bundle.ui-testing' if isUI else 'com.apple.product-type.bundle.unit-test'),buildConfigurationList=cfg,buildPhases=phases,buildRules=[],dependencies=deps,packageProductDependencies=[firebaseProduct] if isApp else []))
projectConfs=[]
for name in ['Debug','Staging','Release']:
 debug=name!='Release'
 settings={'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_STRICT_OBJC_MSGSEND':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if debug else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if debug else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if debug else 'NO','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)' if debug else '$(inherited)','ONLY_ACTIVE_ARCH':'YES' if debug else 'NO','GCC_OPTIMIZATION_LEVEL':'0' if debug else 's','IPHONEOS_DEPLOYMENT_TARGET':'27.0','SDKROOT':'iphoneos','SWIFT_VERSION':'6.0'}
 projectConfs.append(add('projectConfig:'+name,'XCBuildConfiguration',name=name,buildSettings=settings))
projectCfg=add('projectConfigs','XCConfigurationList',buildConfigurations=projectConfs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
productGroup=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
rootChildren=[add('group:'+name,'PBXGroup',children=refs,name=name,sourceTree='<group>') for name,refs in groups.items()]
rootGroup=add('root','PBXGroup',children=rootChildren+[productGroup],sourceTree='<group>')
project=add('project','PBXProject',attributes={'LastUpgradeCheck':'2700','BuildIndependentTargetsInParallel':'YES','TargetAttributes':{appTarget:{'CreatedOnToolsVersion':'27.0','SystemCapabilities':{'com.apple.Push':{'enabled':1},'com.apple.SignInWithApple':{'enabled':1},'com.apple.ApplePay':{'enabled':1}}}}},buildConfigurationList=projectCfg,compatibilityVersion='Xcode 14.0',developmentRegion='cs',hasScannedForEncodings=0,knownRegions=['cs','en','Base'],mainGroup=rootGroup,productRefGroup=productGroup,projectDirPath='',projectRoot='',packageReferences=[firebasePackage],targets=targetids)
def pbx(value,depth=0):
 if isinstance(value,dict):return '{\n'+''.join('\t'*(depth+1)+json.dumps(str(k))+' = '+pbx(v,depth+1)+';\n' for k,v in value.items())+'\t'*depth+'}'
 if isinstance(value,list):return '('+', '.join(pbx(v,depth+1) for v in value)+')'
 if isinstance(value,int):return str(value)
 return json.dumps(value,ensure_ascii=False)
proj=R/'Privofit.xcodeproj';proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n'+pbx({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
shared=proj/'xcshareddata/xcschemes';shared.mkdir(parents=True,exist_ok=True)
def buildRef(name):
 product='Privofit' if name=='Privofit' else 'Privofit'+name
 return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:"+name)}" BuildableName="{product}{".app" if name=="Privofit" else ".xctest"}" BlueprintName="{product}" ReferencedContainer="container:Privofit.xcodeproj"/>'
for demo in [False,True]:
 name='Privofit Demo' if demo else 'Privofit'
 args='<CommandLineArguments><CommandLineArgument argument="--demo" isEnabled="YES"/></CommandLineArguments>' if demo else ''
 scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildRef('Privofit')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{buildRef('Tests')}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{buildRef('UITests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildRef('Privofit')}</BuildableProductRunnable>{args}</LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildRef('Privofit')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
 (shared/(name+'.xcscheme')).write_text(scheme)
workspace=proj/'project.xcworkspace';workspace.mkdir(exist_ok=True);(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>')
print(f'Generated Xcode project: {len(appfiles)} app files, {len(tests)} unit test files, {len(ui)} UI test files')
