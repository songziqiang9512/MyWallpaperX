"""Independent authored-world geometric shadow oracle; no product imports.

F6 project policy only: a covered fraction <= 0.5 does not cast. This is not
an official cutout/PCF/bias/parity claim. Samples lie safely inside/outside a
silhouette; no expected edge filtering is inferred from product pixels.
"""
import math

def dot(a,b):return sum(x*y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def ray_triangle(origin,direction,triangle):
    """Positive ray/triangle hit in authored world, double precision."""
    a,b,c=triangle;e1=sub(b,a);e2=sub(c,a);h=cross(direction,e2);det=dot(e1,h)
    if abs(det)<1e-12:return None
    inverse=1/det;s=sub(origin,a);u=inverse*dot(s,h)
    if not 0<=u<=1:return None
    q=cross(s,e1);v=inverse*dot(direction,q)
    if v<0 or u+v>1:return None
    distance=inverse*dot(e2,q)
    return distance if distance>1e-9 else None

def expected_visibility(v):
    if not v.get('shadow_enabled',True):return 1
    for caster in v['casters']:
        if not caster.get('cast',True) or not caster.get('visible',True):continue
        coverage=caster.get('layer_alpha',1)*caster.get('material_opacity',1)
        if caster.get('uses_coverage_alpha',True) and not caster.get('tint_mask',False):coverage*=caster.get('texture_alpha',1)
        if coverage<=.5:continue
        if any(ray_triangle(v['receiver'],v['toward_light'],tri) is not None for tri in caster['triangles']):return 0
    return 1

def rectangle(x0=70,x1=90,y0=38,y1=58,z=20,**flags):
    a=(x0,y0,z);b=(x1,y0,z);c=(x1,y1,z);d=(x0,y1,z)
    return dict(triangles=[(a,c,b),(a,d,c)],**flags)

def freeze_vectors():
    specs=[
      ('opaque-shadow',{},rectangle()),('outside-lit',{'receiver':[120,48,0]},rectangle()),
      ('shadow-off',{'shadow_enabled':False},rectangle()),('no-caster',{},None),
      ('cast-false-not-caster',{},rectangle(cast=False)),
      ('cast-false-receiver-gets-shadow',{'receiver_cast':False},rectangle()),
      ('unlit-casts',{},rectangle(receives_lighting=False)),
      ('alpha-zero',{},rectangle(texture_alpha=0)),('alpha-half',{},rectangle(texture_alpha=.5)),
      ('alpha-one',{},rectangle(texture_alpha=1)),('opacity-product-half',{},rectangle(layer_alpha=.5,material_opacity=1)),
      ('opacity-product-above-half',{},rectangle(layer_alpha=.75,material_opacity=.75)),
      ('tint-mask-alpha-zero',{},rectangle(texture_alpha=0,tint_mask=True)),
      ('no-coverage-alpha-zero',{},rectangle(texture_alpha=0,uses_coverage_alpha=False)),
      ('behind-receiver',{},rectangle(x0=30,x1=50,z=-20)),
      ('offscreen-caster',{},rectangle(x0=170,x1=190,z=120)),
      ('late-authored-caster',{'authored_order':'receiver,caster'},rectangle()),
      ('caster-parent-translation',{'receiver':[65,48,0]},rectangle(x0=75,x1=95)),
      ('direction-flipped',{'receiver':[100,48,0],'toward_light':[-1,0,1]},rectangle()),
      ('caster-moved-away',{},rectangle(x0=105,x1=125)),
      ('hidden-caster',{},rectangle(visible=False)),
      ('orthographic',{'camera':'orthographic'},rectangle()),
      ('perspective-same-world-ray',{'camera':'perspective'},rectangle()),
    ]
    result=[]
    for name,changes,caster in specs:
        v=dict(name=name,receiver=[60,48,0],toward_light=[1,0,1],casters=[] if caster is None else [caster]);v.update(changes)
        v['expected_visibility']=expected_visibility(v);result.append(v)
    return result

if __name__=='__main__':
    import json
    print(json.dumps({'policy':'F6 independent world ray, coverage > 0.5, no boundary filter oracle','vectors':freeze_vectors()},indent=2))
