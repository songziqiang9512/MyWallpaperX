#!/usr/bin/env python3
"""Self-authored normal input, actual loader and shared lit consumer behavior."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from script.tests import test_scene_texture_candidate as texture_fixture
from script.tests.test_scene_lit_image_layer import ROOT, SCENE

def pbr_expected(normal=(0,0,1), light=(100,0,100), view=(0,0,1), *,
                 metallic=.5, roughness=.5, albedo=128, intensity=1.5, radius=1000):
    """Independent double oracle in project light units, before SDR rounding."""
    import math
    def unit(v):
        length=math.sqrt(sum(x*x for x in v)); return tuple(x/length for x in v) if length else (0,0,0)
    def dot(a,b): return sum(x*y for x,y in zip(a,b))
    n,l,v=unit(normal),unit(light),unit(view)
    nl=max(0,dot(n,l)); nv=dot(n,v); base=albedo/255
    f0=.04*(1-metallic)+min(1,max(0,base))*metallic
    fresnel=f0; specular=0
    if nl>0 and nv>0:
        h=unit(tuple(x+y for x,y in zip(l,v))); a=max(.01,roughness**2)
        nh=max(0,min(1,dot(n,h)))
        distribution=a*a/(math.pi*(1+(a*a-1)*nh*nh)**2)
        masking=lambda c:(math.sqrt(1+a*a*(1-c*c)/(c*c))-1)/2
        geometry=1/(1+masking(nl)+masking(nv))
        fresnel=f0+(1-f0)*(1-max(0,min(1,dot(v,h))))**5
        specular=math.pi*distribution*geometry*fresnel/(4*nl*nv)*nl
    response=(1-metallic)*(1-fresnel)*base*nl+specular
    attenuation=max(0,1-math.sqrt(sum(x*x for x in light))/radius)**2
    return min(255,max(0,response*intensity*attenuation*255))

def normal_expected(sign=1, *, flat=False, encoding='rgb', parent=None, animated=False):
    n=(0,0,1) if flat else ((230 if sign>0 else 25)/255*2-1,-(128/255*2-1),204/255*2-1)
    if encoding=='rg':
        x=1 if sign>0 else -1; y=-(128/255*2-1); n=(x,y,0)
    if encoding=='bc5': n=(sign,0,0)
    if animated: n=(sign,-1/255,1/255)
    if parent=='scale': n=(n[0]/4,n[1],n[2])
    if parent=='rotate': n=(-n[1],n[0],n[2])
    if parent=='mirror': n=(-n[0],n[1],n[2])
    return pbr_expected(n)

class SceneAuthoredNormalTests(unittest.TestCase):
    def test_loaded_formats_and_typed_lit_consumer(self):
        with tempfile.TemporaryDirectory(prefix='mwx-authored-normal-') as temporary:
            work=Path(temporary)
            air=[]
            for name in ['SceneImageLayer','SceneLitImageLayer']:
                output=work/(name+'.air')
                subprocess.run(['xcrun','-sdk','macosx','metal','-c',str(SCENE/'Rendering/Composition'/(name+'.metal')),'-o',str(output)],check=True,capture_output=True,text=True)
                air.append(str(output))
            library=work/'fixture.metallib'
            subprocess.run(['xcrun','-sdk','macosx','metallib',*air,'-o',str(library)],check=True,capture_output=True,text=True)
            sources=list(dict.fromkeys(texture_fixture.SWIFT_SOURCES+[SCENE/p for p in [
                'Rendering/Metal/SceneLitImageLayerPipeline.swift',
                'Rendering/Composition/SceneOffscreenEffectRenderer+Capture.swift',
                'Diagnostics/SceneGPUCensus.swift',
                'Resources/Assets/SceneResourceIndex.swift','Resources/Assets/SceneResourceView.swift',
                'Resources/Textures/SceneTexturePathResolver.swift','Resources/Textures/SceneMaterialAssetTextureCatalog.swift']]))
            support=work/'Support.swift'
            support_text=texture_fixture.HARNESS.split('@main',1)[0]
            support_text=support_text.replace('struct SceneRenderDescriptor {', '''struct SceneRenderDescriptor {
    struct ModelMaterialLink { let modelPath: String; let materialPath: String }
    struct MaterialPass { let materialPath: String; let texturePaths: [String] }
    var modelMaterialLinks: [ModelMaterialLink] = []
    var materialPasses: [MaterialPass] = []
''').replace('let contentKind: String\n        let brightness:', 'var imagePath: String? = nil\n        var staticBaseTexturePath: String? = nil\n        let contentKind: String\n        let brightness:')
            support.write_text(support_text+'\nenum SceneMatrix { static func scale(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v,1)) } }\n')
            binary=work/'probe'
            command=['xcrun','swiftc','-D','SCENE_AUTHORED_NORMAL','-parse-as-library',*[str(p) for p in sources],str(support),str(ROOT/'script/tests/fixtures/SceneLitImageLayerHarness.swift'),str(ROOT/'script/tests/fixtures/SceneAuthoredNormalHarness.swift'),'-module-cache-path',str(work/'module-cache'),'-o',str(binary)]
            compiled=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(compiled.returncode,0,compiled.stderr)
            result=subprocess.run([str(binary),str(library),str(work)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report=json.loads(result.stdout)
            self.assertEqual(report['formatCases'],19)
            self.assertLess(report['maxOracleError'],0.002)
            self.assertTrue(all(report['contracts'].values()),report)
            print(json.dumps(report,sort_keys=True))
            if destination:=os.environ.get('MWX_SCENE_NORMAL_EVIDENCE'):
                path=Path(destination);path.mkdir(parents=True,exist_ok=True)
                (path/'loader-gpu-report.json').write_text(json.dumps(report,indent=2))


class SceneAuthoredNormalIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value=os.environ.get('MWX_SCENE_INTEGRATION_APP')
        if not value: raise unittest.SkipTest('requires frozen Debug App executable')
        cls.app=Path(value).resolve(strict=True)
        import hashlib
        cls.execution_test_sha=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()

    def run_normal(self, *, sign=1, lighting=1, normalmap=1, missing=False,
                   corrupt=False, effect=False, animated=False, instance=False, slot2=False,
                   encoding='rgb', render_size=64, parent_transform=None, shader='genericimage2',
                   scalar_values=None, instance_scalar=None, light_origin='180 48 100', intensity=1.5,
                   native_camera=None, layer_perspective=None, no_normal=False, reflection=0, property_defaults=None, instance_base_size=(4,4), instance_base_animated=False, same_model_peer=False, instance_base_failure=None, pbr_map=None, no_lights=False):
        import hashlib, struct, zlib, shutil
        from script.tests.test_scene_pkg_cache_extractor import make_package
        from script.web_benchmark_capture import png_rgb_pixels
        def png(rgb, size=(4,4)):
            def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
            return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',*size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes((*rgb,255))*size[0])*size[1]))+chunk(b'IEND',b'')
        def tex(fmt,w,h,data,flags=0):
            return b'TEXV0005\0TEXI0001\0'+struct.pack('<7I',fmt,flags,w,h,w,h,0)+b'TEXB0002\0'+struct.pack('<7I',1,1,w,h,0,0,len(data))+data
        rgb=(230 if sign>0 else 25,128,204)
        normalpath='materials/authored.png';normaldata=png(rgb)
        if encoding=='rg':
            normalpath='materials/authored.tex';normaldata=tex(8,4,4,bytes((255 if sign>0 else 0,128))*16)
        if encoding=='bc5':
            normalpath='materials/authored.tex';x=127 if sign>0 else 129
            normaldata=tex(5,4,4,bytes([x,x,0,0,0,0,0,0]+[0]*8))
        if animated:
            normalpath='materials/animated.tex'
            payload=b''.join(bytes((255,128,128,255) if i%8<4 else (0,128,128,255)) for i in range(32))
            normaldata=tex(0,8,4,payload,4)+b'TEXS0002\0'+struct.pack('<I',2)
            for origin in (0,4):normaldata+=struct.pack('<If6f',0,2.5,origin,0,4,0,0,4)
        receiver={'id':1,'name':'Normal receiver','image':'models/receiver.json','origin':'80 48 0','size':(f'{render_size[0]} {render_size[1]}' if isinstance(render_size,tuple) else f'{render_size} {render_size}')}
        if instance: receiver['instance']={'textures':['materials/instance.tex' if instance_base_animated else 'materials/instance.png',None]}
        if instance_scalar is not None: receiver.setdefault('instance',{})['constantshadervalues']=instance_scalar
        if layer_perspective is not None: receiver['perspective']=layer_perspective
        if effect: receiver['effects']=[{'id':10,'file':'effects/own_dim/effect.json','visible':True}]
        scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},'clearcolor':'0 0 0','ambientcolor':'0 0 0','skylightcolor':'0 0 0'},'objects':[receiver,
            {'id':2,'light':'lpoint','origin':light_origin,'color':'1 1 1','intensity':intensity,'radius':1000},
            {'id':99,'name':'Healthy peer','image':'models/util/solidlayer.json','origin':'140 80 0','size':'12 12','color':'0 1 0'}]}
        if no_lights:scene['objects']=[o for o in scene['objects'] if o['id']!=2]
        if same_model_peer:
            scene['objects'].append({'id':3,'name':'Same model inherited peer','image':'models/receiver.json','origin':'20 48 0','size':'16 16'})
        if native_camera:
            scene['general'].pop('orthogonalprojection')
            scene['camera']=native_camera
            scene['general']['fov']=45
        if parent_transform:
            receiver.update(parent=50,origin='0 0 0')
            parent={'id':50,'name':'Authored parent','image':'models/util/solidlayer.json',
                'origin':'80 48 0','size':'1 1','color':'0 0 0'}
            parent.update(parent_transform)
            scene['objects'].insert(0,parent)
        entries={'scene.json':json.dumps(scene).encode(),'models/receiver.json':json.dumps({'material':'materials/receiver.json'}).encode(),
            'materials/receiver.json':json.dumps({'passes':[{'shader':shader,'constantshadervalues':scalar_values or {},'textures':(['materials/albedo.png'] if no_normal else ['materials/albedo.png',None,normalpath] if slot2 else ['materials/albedo.png',normalpath]), 'combos':{'LIGHTING':lighting,'NORMALMAP':normalmap,'REFLECTION':reflection},'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode(),'materials/albedo.png':png((128,128,128)),
            'effects/own_dim/effect.json':json.dumps({'passes':[{'material':'materials/own_dim.json'}]}).encode(),
            'materials/own_dim.json':json.dumps({'passes':[{'shader':'own_dim','textures':[None],'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode(),
            'shaders/own_dim.vert':b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n',
            'shaders/own_dim.frag':b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n'}
        if instance:
            if instance_base_animated:
                payload=b''.join(bytes((64,64,64,255) if i%8<4 else (192,192,192,255)) for i in range(32))
                data=tex(0,8,4,payload,4)+b'TEXS0002\0'+struct.pack('<I',2)
                for origin in (0,4):data+=struct.pack('<If6f',0,2.5,origin,0,4,0,0,4)
                entries['materials/instance.tex']=data
            else:entries['materials/instance.png']=png((64,64,64),instance_base_size)
        if instance_base_failure == 'missing':entries.pop('materials/instance.png',None)
        if instance_base_failure == 'corrupt':entries['materials/instance.png']=b'corrupt selected asset'
        if pbr_map is not None:
            material=json.loads(entries['materials/receiver.json']);p=material['passes'][0]
            p['textures']=(p['textures']+[None]*3)[:3];p['textures'][2]='materials/pbr.tex'
            p['combos'].update(pbr_map.get('combos',{}))
            entries['materials/receiver.json']=json.dumps(material).encode()
            data=tex(0,4,4,bytes(pbr_map['rgba'])*16,pbr_map['flags'])
            if pbr_map.get('animated'):
                payload=b''.join(bytes(pbr_map['rgba'] if i%8<4 else pbr_map['next_rgba']) for i in range(32))
                data=tex(0,8,4,payload,pbr_map['flags']|4)+b'TEXS0002\0'+struct.pack('<I',2)
                for origin in (0,4):data+=struct.pack('<If6f',0,2.5,origin,0,4,0,0,4)
            entries['materials/pbr.tex']=data
            if pbr_map.get('headerless'):
                p['textures'][2]='materials/map-headerless.png';entries[p['textures'][2]]=png(pbr_map['rgba'][:3])
                entries['materials/receiver.json']=json.dumps(material).encode()
            if pbr_map.get('missing'):entries.pop('materials/pbr.tex')
            if pbr_map.get('corrupt'):entries['materials/pbr.tex']=b'corrupt map'
            if 'instance_rgba' in pbr_map:
                receiver.setdefault('instance',{})['textures']=[None,None,'materials/instance-map.tex']
                entries['materials/instance-map.tex']=tex(0,4,4,bytes(pbr_map['instance_rgba'])*16,pbr_map['flags'])
                entries['scene.json']=json.dumps(scene).encode()
        if not missing: entries[normalpath]=b'corrupt' if corrupt else normaldata
        with tempfile.TemporaryDirectory(prefix='mwx-normal-app-') as temporary:
            root=Path(temporary);content=root/'content';content.mkdir();home=root/'home';home.mkdir();evidence=root/'evidence'
            (content/'project.json').write_text(json.dumps({'type':'scene','file':'scene.json','general':{'properties':property_defaults or {}}}));(content/'scene.pkg').write_bytes(make_package(list(entries.items())))
            command=[str(self.app),'--mwx-debug-scene-root',str(content),'--mwx-debug-scene-duration','6','--mwx-debug-scene-evidence-dir',str(evidence)]
            environment=os.environ.copy();environment.update(HOME=str(home),CFFIXED_USER_HOME=str(home),MWX_SCENE_DEBUG_SURFACE_COUNT='1')
            result=subprocess.run(command,env=environment,capture_output=True,text=True,timeout=70);log=result.stdout+result.stderr
            pixels={}
            for path in sorted(evidence.glob('*-window.png')):
                w,h,rows=png_rgb_pixels(path);samples=[list(rows[y][x*3:x*3+3]) for y in range(h//2-10,h//2+10) for x in range(w//2-10,w//2+10)]
                pixels[path.name]={'center':list(rows[h//2][w//2*3:w//2*3+3]),'roiMean':[sum(v[c] for v in samples)/len(samples) for c in range(3)],'greenPeer':sum(row[x*3]<5 and row[x*3+1]>245 and row[x*3+2]<5 for row in rows[::4] for x in range(0,w,4)),'size':[w,h]}
                if same_model_peer:
                    peer=[list(rows[y][x*3:x*3+3]) for y in range(h//2-3,h//2+3) for x in range(w//8-3,w//8+3)]
                    pixels[path.name]['sameModelPeerMean']=[sum(v[c] for v in peer)/len(peer) for c in range(3)]
            if destination:=os.environ.get('MWX_SCENE_INTEGRATION_EVIDENCE'):
                saved=Path(destination)/self._testMethodName/f'{encoding}-{sign}-size{render_size}-parent{parent_transform}-case{getattr(self,"scenario_id","normal")}';saved.mkdir(parents=True,exist_ok=True)
                shutil.copytree(content,saved/'content',dirs_exist_ok=True)
                if evidence.exists():shutil.copytree(evidence,saved/'evidence',dirs_exist_ok=True)
                (saved/'app.log').write_text(log);(saved/'pixels.json').write_text(json.dumps(pixels,indent=2))
                (saved/'identity.json').write_text(json.dumps({'command':command,'returncode':result.returncode,'inputSHA':{k:hashlib.sha256(v).hexdigest() for k,v in entries.items()},'executionTestSHA':self.execution_test_sha,'appSHA':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [self.app,self.app.with_name('MyWallpaperX.debug.dylib')] if p.exists()}},indent=2))
            self.assertEqual(result.returncode,0,log[-4000:]);self.assertIn('gpuDrained=true',log)
            self.assertRegex(log,r'state=completed frame=[1-9]\d* surface=\d+ gpu=completed')
            self.assertGreaterEqual(len(pixels),2,log[-4000:])
            for p in pixels.values():self.assertGreater(p['greenPeer'],20,p)
            if missing or corrupt:self.assertIn('schema=base-material-normal status=unavailable fallback=flat-lit',log)
            return pixels

    def test_plain_rgb_normal_direction(self):
        a=self.run_normal(sign=1);b=self.run_normal(sign=-1)
        for name in a:
            self.assertLessEqual(abs(a[name]['roiMean'][0]-normal_expected(1)),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-normal_expected(-1)),1,b)
            self.assertGreaterEqual(a[name]['roiMean'][0]-b[name]['roiMean'][0],20)

    def test_effect_graph_uses_same_lit_normal(self):
        a=self.run_normal(sign=1,effect=True);b=self.run_normal(sign=-1,effect=True)
        for name in a:
            self.assertLessEqual(abs(a[name]['roiMean'][0]-normal_expected(1)/2),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-normal_expected(-1)),1,b)
            self.assertGreaterEqual(a[name]['roiMean'][0]-b[name]['roiMean'][0],20)

    def test_lighting_disabled_unchanged(self):
        for value in self.run_normal(lighting=0).values():self.assertEqual(value['center'],[128]*3)

    def test_normalmap_zero_is_flat_lit(self):
        for value in self.run_normal(normalmap=0).values():self.assertLessEqual(abs(value['roiMean'][0]-normal_expected(flat=True)),1)

    def test_missing_normal_is_flat_lit(self):
        for value in self.run_normal(missing=True).values():self.assertLessEqual(abs(value['roiMean'][0]-normal_expected(flat=True)),1)

    def test_corrupt_normal_is_flat_lit(self):
        for value in self.run_normal(corrupt=True).values():self.assertLessEqual(abs(value['roiMean'][0]-normal_expected(flat=True)),1)

    def test_instance_albedo_override_inherits_normal(self):
        # New albedo identity/64 differs from inherited 128; BC5 +X also
        # differs from a lost-normal flat result. Both wrong paths are >14 away.
        expected=pbr_expected((1,0,0),albedo=64)
        for value in self.run_normal(instance=True,encoding='bc5').values():
            self.assertLessEqual(abs(value['roiMean'][0]-expected),2,value)
            self.assertGreater(abs(value['roiMean'][0]-pbr_expected((1,0,0))),10)
            self.assertGreater(abs(value['roiMean'][0]-pbr_expected(albedo=64)),10)

    def test_slot2_is_not_normal(self):
        for value in self.run_normal(slot2=True).values():self.assertLessEqual(abs(value['roiMean'][0]-normal_expected(flat=True)),1)

    def test_rg8_and_bc5_signed_directions(self):
        for encoding in ['rg','bc5']:
            a=self.run_normal(encoding=encoding,sign=1);b=self.run_normal(encoding=encoding,sign=-1)
            for name in a:
                self.assertLessEqual(abs(a[name]['roiMean'][0]-normal_expected(1,encoding=encoding)),2,a)
                self.assertLessEqual(abs(b[name]['roiMean'][0]-normal_expected(-1,encoding=encoding)),1,b)
                self.assertGreater(a[name]['roiMean'][0]-b[name]['roiMean'][0],20)

    def test_normal_direction_excludes_intrinsic_extent(self):
        a=self.run_normal(render_size=32)
        b=self.run_normal(render_size=128)
        rectangle=self.run_normal(render_size=(128,32))
        for name in a:
            self.assertLessEqual(abs(rectangle[name]['roiMean'][0]-normal_expected()),2,rectangle)
            self.assertLessEqual(abs(a[name]['roiMean'][0]-normal_expected(1)),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-normal_expected()),2,b)
            self.assertLessEqual(abs(a[name]['roiMean'][0]-b[name]['roiMean'][0]),1)

    def test_authored_parent_direction_transform(self):
        # Analytic tangent directions: scale divides X by 4; rotation90 moves
        # X into Y; reflection reverses X. Intrinsic card dimensions do neither.
        for transform,expected in [({'scale':'4 1 1'},normal_expected(parent='scale')),
                                   ({'angles':'0 0 1.5707963267948966'},normal_expected(parent='rotate')),
                                   ({'scale':'-1 1 1'},normal_expected(parent='mirror'))]:
            for value in self.run_normal(parent_transform=transform).values():
                self.assertLessEqual(abs(value['roiMean'][0]-expected),2,value)

    def test_asset_frame_changes_normal_next_frame(self):
        p=self.run_normal(animated=True)
        self.assertLessEqual(abs(p['scene-ready-window.png']['roiMean'][0]-normal_expected(animated=True)),2,p)
        self.assertLess(p['scene-after-window.png']['roiMean'][0],1,p)

if __name__=='__main__': unittest.main()
