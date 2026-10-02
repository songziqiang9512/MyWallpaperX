#!/usr/bin/env python3
"""F5 independent numeric oracle, frozen before reading reflection product code.

Source: approved project F5 prose at 4f198574. No private/static raw input.
This is the project's bounded strategy, not an official-pixel golden.
"""
from __future__ import annotations
import json
import math
import struct
from copy import deepcopy
from pathlib import Path

HALF_MAX = 65504.0
FLOAT_MAX = struct.unpack('f', bytes.fromhex('ffff7f7f'))[0]
TOLERANCES = {
    'half_radiance_absolute_floor': 0.0,
    'half_radiance_ulps': 2,
    'alpha_absolute': 0.0,
    'projection_absolute': 0.000002,
    'roughness_lod_absolute': 0.000002,
    'disabled_and_unavailable': 'disabled/unavailable/B0/strength0 exact original-route pixels; coverage0 exact RGBA0',
    'constant_mip_absolute': 0.002,
    'spatial_colour': 'predeclared signed chroma and UV oracle; no global-brightness substitute',
}

def f32(x):
    return struct.unpack('f', struct.pack('f', float(x)))[0]

def h16(x):
    return struct.unpack('e', struct.pack('e', max(0.0, min(HALF_MAX, float(x)))))[0]

def dot(a, b):
    return math.fsum(x*y for x, y in zip(a, b))

def unit(a):
    a = tuple(map(float, a))
    length = math.sqrt(dot(a, a))
    if length == 0:
        raise ValueError('zero world direction is not an admitted oracle input')
    return tuple(x/length for x in a)

def surface(v):
    # Texture values are actually stored in half targets; uniforms are Float32.
    source = tuple(h16(x) for x in v['source'])
    env = tuple(h16(x) for x in v['environment'][:3])
    n = unit(tuple(f32(x) for x in v['normal']))
    view = unit(tuple(f32(x) for x in v['view']))
    metallic, b, strength = (f32(v[k]) for k in ('metallic', 'b', 'strength'))
    tint = tuple(f32(x) for x in v['tint'])
    opacity = f32(v['opacity'])
    cosine = min(1.0, abs(dot(n, view)))
    straight = tuple(min(1.0, max(0.0, x/source[3])) if source[3] > 0 else 0.0 for x in source[:3])
    f0 = tuple(0.04*(1-metallic)+x*metallic for x in straight)
    fresnel = tuple(x+(1-x)*(1-cosine)**5 for x in f0)
    original = tuple(v.get('original_radiance', source[:3]))
    reflected = tuple(env[c]*fresnel[c]*strength*b*source[3]*tint[c]*opacity
                      if v['enabled'] and v['environment_ready'] else 0.0 for c in range(3))
    base = tuple(float(original[c])*tint[c]*opacity for c in range(3))
    rgba = tuple(min(HALF_MAX, max(0.0, base[c]+reflected[c])) for c in range(3)) + (source[3]*f32(v.get('tint_alpha',1))*opacity,)
    return {'f0': f0, 'fresnel': fresnel, 'reflection': reflected, 'linear_rgba': rgba,
            'half_rgba': tuple(h16(x) for x in rgba),
            'environment_alpha_used': False, 'cosine': cosine}

def orthographic(width=160.0, height=96.0):
    # Explicit self-authored world-up scene VP; Metal viewport flips Y once.
    return ((2/width,0,0,-1),(0,2/height,0,-1),(0,0,1,0),(0,0,0,1))

def perspective_eye_z(eye_z=8.0, aspect=2.0):
    # 90 degree vertical FOV, right-handed camera at (0,0,eye_z), looking -Z.
    # Depth does not affect 2D UV; rows use a declared near .1/far 100.
    near, far = .1, 100.0
    a, q = far/(near-far), far*near/(near-far)
    return ((1/aspect,0,0,0),(0,1,0,0),(0,0,a,-a*eye_z+q),(0,0,-1,eye_z))

def project(v):
    n = unit(tuple(f32(x) for x in v['normal']))
    p = tuple(f32(x) for x in v['position'])
    if 'eye' in v:
        view = unit(tuple(f32(v['eye'][c])-p[c] for c in range(3)))
    else:
        view = unit(tuple(f32(x) for x in v['view']))
    # Public mirror geometry: incident is -view, then reflect about N.
    direction = tuple(2*dot(n, view)*n[c]-view[c] for c in range(3))
    distance = f32(v['distance'])
    q = tuple(p[c]+distance*direction[c] for c in range(3))+(1.0,)
    clip = tuple(dot(tuple(f32(x) for x in row), q) for row in v['vp'])
    valid = all(math.isfinite(x) and abs(x) <= FLOAT_MAX for x in clip) and clip[3] > 0
    if not valid:
        return {'direction': direction, 'clip': clip, 'valid': False, 'uv': None}
    xy = (clip[0]/clip[3], clip[1]/clip[3])
    uv = ((xy[0]+1)/2, (1-xy[1])/2)
    return {'direction': direction, 'clip': clip, 'valid': True,
            'uv': tuple(min(1,max(0,x)) for x in uv), 'unclamped_uv': uv}

def half_ulp(x):
    x = h16(x)
    bits = struct.unpack('H', struct.pack('e', x))[0]
    if bits >= 0x7bff:
        lower = struct.unpack('e', struct.pack('H', bits-1))[0]
        return x-lower
    upper = struct.unpack('e', struct.pack('H', bits+1))[0]
    return upper-x

def numeric_vectors():
    base = dict(source=[.2,.15,.1,.5],environment=[.5,.25,.125,1],normal=[0,0,1],view=[0,0,1],
                metallic=0,b=1,strength=1,tint=[1,1,1],opacity=1,enabled=True,environment_ready=True)
    specs = [('flat-dielectric',{}),('metal-endpoint',dict(metallic=1)),('metal-mix',dict(metallic=.5)),
             ('schlick-grazing',dict(view=[1,0,0])),('full-normal-sign',dict(normal=[0,0,-1])),
             ('strength-zero',dict(strength=0)),('strength-four',dict(strength=4)),
             ('B-zero',dict(b=0)),('B-half',dict(b=.5)),
             ('coverage-quarter',dict(source=[.1,.075,.05,.25])),
             ('coverage-one',dict(source=[.4,.3,.2,1])),
             ('coverage-zero',dict(source=[0,0,0,0],strength=1e38,environment=[65504,65504,65504,1])),
             ('tint-opacity-once',dict(tint=[.5,.25,2],opacity=.25)),
             ('environment-alpha-zero',dict(environment=[.5,.25,.125,0])),
             ('environment-alpha-half',dict(environment=[.5,.25,.125,.5])),
             ('hdr-keeps-radiance',dict(environment=[8,4,2,1],strength=4)),
             ('hdr-final-half-saturation',dict(environment=[65504,65504,65504,1],strength=100)),
             ('finite-hdr-cancellation',dict(source=[1,1,1,1],environment=[65504,65504,65504,1],
                                            strength=1e38,tint=[1e-10]*3,opacity=1e-30)),
             ('disabled-original',dict(enabled=False)),('unavailable-original',dict(environment_ready=False)),
             ('direct-original-plus-reflection',dict(original_radiance=[.06,.04,.02]))]
    return [dict(deepcopy(base),**changes,name=name) for name,changes in specs]

def projection_vectors():
    s=math.sqrt(.5)
    base=dict(position=[80,48,0],normal=[0,0,1],view=[0,0,1],distance=4,vp=orthographic())
    specs=[('ortho-flat',{},[.5,.5]),('ortho-tilt-positive',dict(normal=[s,0,s]),[.525,.5]),
           ('ortho-tilt-negative',dict(normal=[-s,0,s]),[.475,.5]),
           ('ortho-normal-full-sign',dict(normal=[-s,0,-s]),[.525,.5]),
           ('distance-zero',dict(normal=[s,0,s],distance=0),[.5,.5]),
           ('world-origin',dict(position=[40,24,0],normal=[s,0,s]),[.275,.75]),
           ('ortho-y-up',dict(normal=[0,s,s]),[.5,11/24]),
           ('clamp-edge',dict(position=[159,48,0],normal=[s,0,s]),[1,.5]),
           ('perspective-tilt',dict(position=[0,0,0],normal=[s,0,s],eye=[0,0,8],vp=perspective_eye_z()),[.625,.5]),
           ('perspective-flat',dict(position=[0,0,0],eye=[0,0,8],vp=perspective_eye_z()),[.5,.5]),
           ('perspective-behind',dict(position=[0,0,0],eye=[0,0,8],vp=perspective_eye_z(),distance=12),None),
           ('perspective-on-eye',dict(position=[0,0,0],eye=[0,0,8],vp=perspective_eye_z(),distance=8),None)]
    return [dict(deepcopy(base),**changes,name=name,hand_uv=hand) for name,changes,hand in specs]

def normal_from_texel(spec):
    if spec['format']=='bc5-rg-snorm':
        x,y=(max(-1,f32(value/127)) for value in spec['endpoints'])
        return (x,y,f32(math.sqrt(max(0,1-x*x-y*y))))
    if spec['format']=='rgba8-unorm':
        return tuple(f32(f32(value/255)*2-1) for value in spec['texel'][:3])
    raise ValueError(spec)

def gpu_numeric_vectors():
    vectors=numeric_vectors()
    vectors=[v for v in vectors if v['name']!='full-normal-sign']
    vectors.append(dict(deepcopy(vectors[0]),name='tint-alpha-half',tint_alpha=.5))
    for name,texel in [('rgb-normal-pair-positive',[217,128,217,255]),
                       ('rgb-normal-pair-negative',[38,127,38,255])]:
        vectors.append(dict(deepcopy(vectors[0]),name=name,
            normal_texel=dict(format='rgba8-unorm',texel=texel)))
    for v in vectors:
        v.setdefault('normal_texel',dict(format='bc5-rg-snorm',endpoints=[0,0]))
        v['normal']=normal_from_texel(v['normal_texel'])
        v['map_texel']=[0,0,128 if v['name']=='B-half' else 0 if v['name']=='B-zero' else 255,255]
        v['map_header_bits']=4
        v['b']=f32(v['map_texel'][2]/255)
    return vectors

def gpu_projection_vectors():
    vectors=[]
    for v in projection_vectors():
        v=deepcopy(v)
        x,y,z=v['normal']
        if x!=0:
            texel=[217 if x>0 else 38,128,217 if z>0 else 38,255]
            if z<0:texel[1]=127
        elif y!=0:texel=[128,217 if y>0 else 38,217,255]
        else:
            v['normal_texel']=dict(format='bc5-rg-snorm',endpoints=[0,0])
            v['normal']=normal_from_texel(v['normal_texel'])
            vectors.append(v);continue
        v['normal_texel']=dict(format='rgba8-unorm',texel=texel)
        v['normal']=normal_from_texel(v['normal_texel'])
        vectors.append(v)
    return vectors

def freeze():
    numerical=[]
    for v in numeric_vectors():
        expected=surface(v)
        expected['radiance_tolerance']=[max(TOLERANCES['half_radiance_absolute_floor'],
            TOLERANCES['half_radiance_ulps']*half_ulp(x)) for x in expected['half_rgba'][:3]]
        numerical.append(dict(input=v,expected=expected))
    spatial=[]
    for v in projection_vectors():
        expected=project(v)
        if v['hand_uv'] is None:
            assert not expected['valid'],v
        else:
            assert expected['valid'],v
            assert max(abs(a-b) for a,b in zip(v['hand_uv'],expected['uv'])) < 2e-6,(v,expected)
        spatial.append(dict(input=v,expected=expected))
    byname={row['input']['name']:row['expected'] for row in numerical}
    assert byname['flat-dielectric']['f0'] == (.04,.04,.04)
    for name in ['full-normal-sign','environment-alpha-zero','environment-alpha-half']:
        assert byname[name]['half_rgba']==byname['flat-dielectric']['half_rgba']
    assert byname['coverage-zero']['half_rgba']==(0,0,0,0)
    assert byname['strength-four']['reflection'][0] > byname['flat-dielectric']['reflection'][0]
    assert 26 < byname['finite-hdr-cancellation']['half_rgba'][0] < 27
    for name in ['strength-zero','B-zero','disabled-original','unavailable-original']:
        assert byname[name]['half_rgba']==tuple(h16(x) for x in [.2,.15,.1,.5])
    lod=[dict(roughness=r,mip_count=count,lod=f32(r)*(count-1)) for count in [1,4,8] for r in [0,.5,1]]
    costs=[dict(width=13,height=7,bytes_per_pixel=b,levels=[[13,7],[6,3],[3,1],[1,1]],
                full_chain_bytes=113*b,one_byte_short=113*b-1) for b in [4,8]]
    gpu_numeric=[]
    for v in gpu_numeric_vectors():
        expected=surface(v)
        expected['radiance_tolerance']=[max(TOLERANCES['half_radiance_absolute_floor'],
            TOLERANCES['half_radiance_ulps']*half_ulp(x)) for x in expected['half_rgba'][:3]]
        gpu_numeric.append(dict(input=v,expected=expected))
    gpu_spatial=[dict(input=v,expected=project(v)) for v in gpu_projection_vectors()]
    rgb={row['input']['name']:row['expected'] for row in gpu_numeric}
    assert rgb['rgb-normal-pair-positive']['half_rgba']==rgb['rgb-normal-pair-negative']['half_rgba']
    assert rgb['tint-alpha-half']['half_rgba'][3]==.25
    assert rgb['tint-alpha-half']['half_rgba'][:3]==rgb['flat-dielectric']['half_rgba'][:3]
    return dict(schema='f5-independent-oracle-v3',contract_commit='4f1985748d9dbcfe4dd5468800833011020c519a',
                evidence_grade='independent project-policy arithmetic only; no product executed',
                provenance='did-not-receive-raw-static-output',tolerances=TOLERANCES,
                numerical=numerical,spatial=spatial,gpu_numerical=gpu_numeric,gpu_spatial=gpu_spatial,
                roughness_lod=lod,logical_mip_cost=costs)

if __name__=='__main__':
    data=freeze()
    print(json.dumps(data,indent=2,sort_keys=True,allow_nan=False))
