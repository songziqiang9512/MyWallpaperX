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
''').replace('let contentKind: String\n        let brightness:', 'var imagePath: String? = nil\n        let contentKind: String\n        let brightness:')
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
                   encoding='rgb', render_size=64, parent_transform=None):
        import hashlib, struct, zlib, shutil
        from script.tests.test_scene_pkg_cache_extractor import make_package
        from script.web_benchmark_capture import png_rgb_pixels
        def png(rgb):
            def chunk(k,v):return struct.pack('>I',len(v))+k+v+struct.pack('>I',zlib.crc32(k+v)&0xffffffff)
            return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',4,4,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\0'+bytes((*rgb,255))*4)*4))+chunk(b'IEND',b'')
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
        if instance: receiver['material']={'textures':['materials/albedo.png',None]}
        if effect: receiver['effects']=[{'id':10,'file':'effects/own_dim/effect.json','visible':True}]
        scene={'version':3,'general':{'orthogonalprojection':{'width':160,'height':96},'clearcolor':'0 0 0','ambientcolor':'0 0 0','skylightcolor':'0 0 0'},'objects':[receiver,
            {'id':2,'light':'lpoint','origin':'180 48 100','color':'1 1 1','intensity':1.5,'radius':1000},
            {'id':99,'name':'Healthy peer','image':'models/util/solidlayer.json','origin':'140 80 0','size':'12 12','color':'0 1 0'}]}
        if parent_transform:
            receiver.update(parent=50,origin='0 0 0')
            parent={'id':50,'name':'Authored parent','image':'models/util/solidlayer.json',
                'origin':'80 48 0','size':'1 1','color':'0 0 0'}
            parent.update(parent_transform)
            scene['objects'].insert(0,parent)
        entries={'scene.json':json.dumps(scene).encode(),'models/receiver.json':json.dumps({'material':'materials/receiver.json'}).encode(),
            'materials/receiver.json':json.dumps({'passes':[{'shader':'genericimage2','textures':['materials/albedo.png',None,normalpath] if slot2 else ['materials/albedo.png',normalpath], 'combos':{'LIGHTING':lighting,'NORMALMAP':normalmap},'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode(),'materials/albedo.png':png((128,128,128)),
            'effects/own_dim/effect.json':json.dumps({'passes':[{'material':'materials/own_dim.json'}]}).encode(),
            'materials/own_dim.json':json.dumps({'passes':[{'shader':'own_dim','textures':[None],'blending':'normal','depthtest':'disabled','depthwrite':'disabled','cullmode':'nocull'}]}).encode(),
            'shaders/own_dim.vert':b'attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\nvarying vec2 v_TexCoord;\nvoid main(){gl_Position=vec4(a_Position,1.0);v_TexCoord=a_TexCoord;}\n',
            'shaders/own_dim.frag':b'uniform sampler2D g_Texture0;\nvarying vec2 v_TexCoord;\nvoid main(){vec4 c=texSample2D(g_Texture0,v_TexCoord);c.rgb*=0.5;gl_FragColor=c;}\n'}
        if not missing: entries[normalpath]=b'corrupt' if corrupt else normaldata
        with tempfile.TemporaryDirectory(prefix='mwx-normal-app-') as temporary:
            root=Path(temporary);content=root/'content';content.mkdir();home=root/'home';home.mkdir();evidence=root/'evidence'
            (content/'project.json').write_text(json.dumps({'type':'scene','file':'scene.json'}));(content/'scene.pkg').write_bytes(make_package(list(entries.items())))
            command=[str(self.app),'--mwx-debug-scene-root',str(content),'--mwx-debug-scene-duration','6','--mwx-debug-scene-evidence-dir',str(evidence)]
            environment=os.environ.copy();environment.update(HOME=str(home),CFFIXED_USER_HOME=str(home),MWX_SCENE_DEBUG_SURFACE_COUNT='1')
            result=subprocess.run(command,env=environment,capture_output=True,text=True,timeout=70);log=result.stdout+result.stderr
            pixels={}
            for path in sorted(evidence.glob('*-window.png')):
                w,h,rows=png_rgb_pixels(path);samples=[list(rows[y][x*3:x*3+3]) for y in range(h//2-10,h//2+10) for x in range(w//2-10,w//2+10)]
                pixels[path.name]={'center':list(rows[h//2][w//2*3:w//2*3+3]),'roiMean':[sum(v[c] for v in samples)/len(samples) for c in range(3)],'greenPeer':sum(row[x*3]<5 and row[x*3+1]>245 and row[x*3+2]<5 for row in rows[::4] for x in range(0,w,4)),'size':[w,h]}
            if destination:=os.environ.get('MWX_SCENE_INTEGRATION_EVIDENCE'):
                saved=Path(destination)/self._testMethodName/f'{encoding}-{sign}-size{render_size}-parent{parent_transform}';saved.mkdir(parents=True,exist_ok=True)
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
            self.assertLessEqual(abs(a[name]['roiMean'][0]-140),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-0),1,b)
            self.assertGreaterEqual(a[name]['roiMean'][0]-b[name]['roiMean'][0],20)

    def test_effect_graph_uses_same_lit_normal(self):
        a=self.run_normal(sign=1,effect=True);b=self.run_normal(sign=-1,effect=True)
        for name in a:
            self.assertLessEqual(abs(a[name]['roiMean'][0]-70),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-0),1,b)
            self.assertGreaterEqual(a[name]['roiMean'][0]-b[name]['roiMean'][0],20)

    def test_lighting_disabled_unchanged(self):
        for value in self.run_normal(lighting=0).values():self.assertEqual(value['center'],[128]*3)

    def test_normalmap_zero_is_flat_lit(self):
        for value in self.run_normal(normalmap=0).values():self.assertLessEqual(abs(value['roiMean'][0]-100),1)

    def test_missing_normal_is_flat_lit(self):
        for value in self.run_normal(missing=True).values():self.assertLessEqual(abs(value['roiMean'][0]-100),1)

    def test_corrupt_normal_is_flat_lit(self):
        for value in self.run_normal(corrupt=True).values():self.assertLessEqual(abs(value['roiMean'][0]-100),1)

    def test_instance_albedo_override_inherits_normal(self):
        for value in self.run_normal(instance=True).values():self.assertLessEqual(abs(value['roiMean'][0]-140),2)

    def test_slot2_is_not_normal(self):
        for value in self.run_normal(slot2=True).values():self.assertLessEqual(abs(value['roiMean'][0]-100),1)

    def test_rg8_and_bc5_signed_directions(self):
        for encoding in ['rg','bc5']:
            a=self.run_normal(encoding=encoding,sign=1);b=self.run_normal(encoding=encoding,sign=-1)
            for name in a:
                self.assertGreater(a[name]['roiMean'][0],90,a);self.assertLess(b[name]['roiMean'][0],1,b)

    def test_normal_direction_excludes_intrinsic_extent(self):
        a=self.run_normal(render_size=32)
        b=self.run_normal(render_size=128)
        rectangle=self.run_normal(render_size=(128,32))
        for name in a:
            self.assertLessEqual(abs(rectangle[name]['roiMean'][0]-140),2,rectangle)
            self.assertLessEqual(abs(a[name]['roiMean'][0]-140),2,a)
            self.assertLessEqual(abs(b[name]['roiMean'][0]-140),2,b)
            self.assertLessEqual(abs(a[name]['roiMean'][0]-b[name]['roiMean'][0]),1)

    def test_authored_parent_direction_transform(self):
        # Analytic tangent directions: scale divides X by 4; rotation90 moves
        # X into Y; reflection reverses X. Intrinsic card dimensions do neither.
        for transform,expected in [({'scale':'4 1 1'},127),
                                   ({'angles':'0 0 1.5707963267948966'},60),
                                   ({'scale':'-1 1 1'},0)]:
            for value in self.run_normal(parent_transform=transform).values():
                self.assertLessEqual(abs(value['roiMean'][0]-expected),2,value)

    def test_asset_frame_changes_normal_next_frame(self):
        p=self.run_normal(animated=True)
        self.assertGreater(p['scene-ready-window.png']['roiMean'][0],100,p)
        self.assertLess(p['scene-after-window.png']['roiMean'][0],1,p)

if __name__=='__main__': unittest.main()
