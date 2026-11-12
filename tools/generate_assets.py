"""Build Maldiven's original mesh resource pack. Run with Blender --background --python.
All lengths are metres. No external downloads, textures or addons are required.
"""
import bpy, math, random, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models'
PREVIEW = ROOT / 'assets/previews'
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
MATS = {}
PALETTE = {
 'plaster':'E9D9B6','trim':'F6E9CC','roof':'B97051','roof_dark':'985B47',
 'wood':'876445','wood_light':'AA855C','door':'437D7A','glass':'365C65',
 'palm':'547F43','palm_light':'719853','palm_dark':'365F39','trunk':'91704E',
 'stone':'979E90','stone_light':'B0B5A7','sand':'E6D4A6','grass':'8FA572',
 'grass_dark':'789463','soil':'B8AA85','rope':'D7C59B','skin':'B98262',
 'shirt':'3A8988','pants':'C8B58F','shoe':'5C5149','hair':'493D32','water':'68B9BA'}
def mat(name):
 if name not in MATS:
  h=PALETTE[name]; rgb=[int(h[i:i+2],16)/255 for i in (0,2,4)]
  linear=[((c+0.055)/1.055)**2.4 if c>0.04045 else c/12.92 for c in rgb]
  m=bpy.data.materials.new(name);m.diffuse_color=(*linear,1);m.use_nodes=True
  bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*linear,1);bs.inputs['Roughness'].default_value=.85
  MATS[name]=m
 return MATS[name]
ASSETS={}
CURRENT=None

def register(o,name,material):
 o.name=name;o.data.materials.append(mat(material))
 for c in list(o.users_collection):c.objects.unlink(o)
 CURRENT.objects.link(o)
 return o

def cube(name,loc,size,material,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  m=o.modifiers.new('soft edges','BEVEL');m.width=bevel;m.segments=1
  bpy.ops.object.modifier_apply(modifier=m.name)
 return register(o,name,material)

def mesh(name,verts,faces,material):
 d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update();o=bpy.data.objects.new(name,d);CURRENT.objects.link(o);o.data.materials.append(mat(material));return o

def segment(name,a,b,r,material,vertices=8,r2=None):
 a,b=Vector(a),Vector(b);v=b-a
 bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=v.length,location=(a+b)/2)
 o=bpy.context.object;o.rotation_euler=v.to_track_quat('Z','Y').to_euler();return register(o,name,material)

def asset(name,fn):
 global CURRENT
 CURRENT=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(CURRENT);fn()
 # Merge visible static meshes per material. Keep collision proxies separate.
 if name!='explorer':
  groups={}
  for o in list(CURRENT.objects):
   if o.type=='MESH' and '-col' not in o.name:groups.setdefault(o.data.materials[0].name,[]).append(o)
  for material,objects in groups.items():
   bpy.ops.object.select_all(action='DESELECT')
   for o in objects:o.select_set(True)
   bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
   objects[0].name=name+'_'+material
 ASSETS[name]=CURRENT
 bpy.ops.object.select_all(action='DESELECT')
 for o in CURRENT.objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_extras=True)
 # Hide the asset source collections from the preview scene.
 CURRENT.hide_render=True
 CURRENT.hide_viewport=True

def cottage():
 cube('CottageCollision-colonly',(0,0,1.4),(5,4,2.8),'plaster')
 cube('base',(0,0,.16),(5.3,4.3,.32),'stone',.07)
 # Open doorway framed by walls, rather than a painted rectangle.
 cube('back',(0,1.92,1.55),(5,.16,2.8),'plaster',.03)
 for x in [-2.42,2.42]:cube('side',(x,0,1.55),(.16,4,2.8),'plaster',.03)
 cube('front_left',(-1.55,-1.92,1.55),(1.9,.16,2.8),'plaster',.03)
 cube('front_right',(1.55,-1.92,1.55),(1.9,.16,2.8),'plaster',.03)
 cube('door_top',(0,-1.92,2.6),(1.2,.16,.7),'plaster')
 cube('door',(0,-2.01,1.24),(1.05,.12,2.12),'door',.025)
 for x in [-.59,.59]:cube('door_frame',(x,-2.07,1.3),(.1,.13,2.3),'trim',.02)
 cube('door_lintel',(0,-2.07,2.43),(1.28,.13,.12),'trim',.02)
 cube('door_handle',(.36,-2.1,1.25),(.06,.04,.16),'wood_light',.01)
 for x in [-1.6,1.6]:
  cube('window',(x,-2.02,1.65),(.88,.08,.88),'glass',.02)
  for sign in [-1,1]:
   cube('window_upright',(x+sign*.48,-2.09,1.65),(.08,.12,1.05),'trim',.01)
   cube('window_cross',(x,-2.09,1.65+sign*.49),(1.05,.12,.08),'trim',.01)
  cube('window_sill',(x,-2.16,1.12),(1.15,.35,.1),'wood_light',.02)
  cube('mullion',(x,-2.12,1.65),(.05,.1,.9),'wood_light')
 # Gable roof, with real pitch and terracotta ridges.
 verts=[(-2.9,-2.5,2.92),(2.9,-2.5,2.92),(-2.9,0,4.15),(2.9,0,4.15),(-2.9,2.5,2.92),(2.9,2.5,2.92)]
 mesh('pitched_roof',verts,[(0,1,3,2),(2,3,5,4),(0,2,4),(1,5,3)],'roof')
 for i in range(17):
  x=-2.85+i*5.7/16
  segment('tile_ridge',(x,-2.5,2.96),(x,0,4.19),.035,'roof_dark',5)
  segment('tile_ridge',(x,0,4.19),(x,2.5,2.96),.035,'roof_dark',5)
 segment('roof_cap',(-2.95,0,4.2),(2.95,0,4.2),.09,'roof',8)
 cube('porch',(0,-2.9,.17),(5.7,1.7,.34),'stone_light',.06)
 cube('step',(0,-3.95,.07),(2.1,.5,.14),'stone',.04)
 for x in [-2.5,2.5]:
  segment('porch_post',(x,-3.5,.3),(x,-3.5,2.7),.08,'wood')
 roof=cube('porch_awning',(0,-3,2.86),(5.7,1.8,.13),'wood_light',.02);roof.rotation_euler.x=.1
 for x in [-2.2,2.2]:
  bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=.24,radius2=.32,depth=.5,location=(x,-2.7,.57));register(bpy.context.object,'planter','roof')
  for j in range(5):
   a=j*math.tau/5;segment('plant',(x,-2.7,.8),(x+.4*math.cos(a),-2.7+.4*math.sin(a),1.12),.035,'palm',5)

def palm():
 centers=[]
 for i in range(12):
  t=i/11;centers.append(Vector((.8*t*t,.14*math.sin(t*3),5.8*t)))
 verts=[]
 for i,c in enumerate(centers):
  r=.22-.08*i/11
  for j in range(9):
   a=j*math.tau/9;verts.append(tuple(c+Vector((r*math.cos(a),r*math.sin(a),0))))
 faces=[]
 for i in range(11):
  for j in range(9):faces.append((i*9+j,i*9+(j+1)%9,(i+1)*9+(j+1)%9,(i+1)*9+j))
 mesh('curved_trunk-col',verts,faces,'trunk')
 for i,c in enumerate(centers[1:-1]):
  if i%2==0:
   bpy.ops.mesh.primitive_torus_add(major_segments=9,minor_segments=3,location=c,major_radius=.205-.06*i/11,minor_radius=.018)
   register(bpy.context.object,'trunk_ring','wood_light')
 top=centers[-1]
 for f in range(9):
  angle=f*math.tau/9;u=Vector((math.cos(angle),math.sin(angle),0));v=Vector((-math.sin(angle),math.cos(angle),0))
  length=2.4+(f%3)*.22;points=[]
  for j in range(9):
   t=j/8;points.append(top+u*length*t+Vector((0,0,.55*math.sin(t*math.pi)-.75*t*t)))
  for j in range(8):segment('frond_spine',points[j],points[j+1],.025,'palm_light',5)
  for j in range(1,9):
   t=j/9;c=top+u*length*t+Vector((0,0,.55*math.sin(t*math.pi)-.75*t*t));width=.52*math.sin(math.pi*t)**.65
   for side in [-1,1]:
    tip=c+u*.38+v*side*width+Vector((0,0,-.16))
    middle=(c+tip)/2+Vector((0,0,.07))
    verts=[tuple(c-u*.1),tuple(middle-u*.12),tuple(tip),tuple(middle+u*.12)]
    leaf=mesh('leaflet',verts,[(0,1,2),(0,2,3),(2,1,0),(3,2,0)],['palm','palm_light','palm_dark'][f%3])
 for i in range(3):
  a=i*2.1;bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=.15,location=top+Vector((.22*math.cos(a),.22*math.sin(a),-.25)));register(bpy.context.object,'coconut','wood')

def rocks():
 rng=random.Random(84)
 for i,(loc,scale) in enumerate([((0,0,.4),(1.2,.9,.75)),((1,.3,.23),(.65,.65,.48)),((-.7,.7,.16),(.5,.45,.3))]):
  bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc);o=bpy.context.object;o.scale=scale
  for v in o.data.vertices:v.co*=rng.uniform(.9,1.12)
  register(o,'coastal_rock-col','stone' if i%2==0 else 'stone_light')

def jetty():
 cube('JettyDeck-colonly',(0,0,.5),(2.4,8,.25),'wood')
 for i in range(32):cube('plank',(0,-3.9+i*.25,.5),(2.4,.235,.17),'wood_light' if i%4 else 'wood',.018)
 for x in [-.85,.85]:cube('support',(x,0,.31),(.16,8,.2),'wood')
 for y in [-3.5,0,3.5]:
  for x in [-1.16,1.16]:
   segment('post',(x,y,-1.5),(x,y,1.3),.11,'wood',8)
   segment('post_cap',(x,y,1.3),(x,y,1.37),.14,'wood_light',8)
 for x in [-1.16,1.16]:
  for y0 in [-3.5,0]:
   pts=[(x,y0+t*3.5,1.1-.25*math.sin(math.pi*t)) for t in [i/8 for i in range(9)]]
   for a,b in zip(pts,pts[1:]):segment('rope',a,b,.025,'rope',5)

def grass():
 for i in range(9):
  a=i*2.4;t=.25+(i%4)*.12;r=.12
  base=Vector((r*math.cos(a),r*math.sin(a),0));tip=base+Vector((.22*math.cos(a),.22*math.sin(a),t))
  d=Vector((-.06*math.sin(a),.06*math.cos(a),0))
  mesh('blade',[tuple(base-d),tuple(base+d),tuple(tip)],[(0,1,2),(2,1,0)],'palm' if i%2 else 'grass')

def bench():
 cube('BenchCollision-colonly',(0,0,.45),(1.8,.65,.9),'wood')
 for y in [-.22,0,.22]:cube('seat',(0,y,.55),(1.8,.18,.09),'wood_light',.025)
 for z in [.85,1.1]:cube('back',(0,.3,z),(1.8,.08,.18),'wood_light',.025)
 for x in [-.65,.65]:
  for y in [-.2,.2]:segment('leg',(x,y,0),(x,y,.58),.055,'wood',6)
  segment('back_post',(x,.3,.3),(x,.3,1.22),.05,'wood',6)

def terrain():
 rng=random.Random(5);n=96;rings=[0,.2,.4,.6,.75,.83,.9,.96,1.03]
 verts=[(0,0,.42)]
 for ring in rings[1:]:
  for j in range(n):
   a=j*math.tau/n;variation=1+.045*math.sin(a*5)+.025*math.cos(a*9)
   x=32*ring*math.cos(a)*variation;y=27*ring*math.sin(a)*variation
   h=.42 if ring<=.75 else (.42-(ring-.75)*3.6)
   if ring<.75:h+=max(0,(y-5)/18)*max(0,(x-2)/28)*2
   verts.append((x,y,h))
 faces=[];indices=[]
 for j in range(n):faces.append((0,1+j,1+(j+1)%n));indices.append(0)
 for i in range(len(rings)-2):
  for j in range(n):
   a=1+i*n+j;b=1+i*n+(j+1)%n;c=1+(i+1)*n+j;d=1+(i+1)*n+(j+1)%n
   faces.extend([(a,c,d),(a,d,b)]);indices.extend([0 if rings[i+2]<=.83 else 1]*2)
 o=mesh('island_ground-col',verts,faces,'grass');o.data.materials.append(mat('sand'))
 for p,idx in zip(o.data.polygons,indices):p.material_index=idx;p.use_smooth=True
 # Uniform sandy path over the flat central village area.
 surface=BVHTree.FromPolygons(verts,faces)
 pts=[(0,-24),(0,-18),(-2,-12),(-1,-6),(0,0),(7,4),(15,6),(20,10)]
 vs=[]
 for i,p in enumerate(pts):
  prev=Vector(pts[max(0,i-1)]);nxt=Vector(pts[min(len(pts)-1,i+1)]);t=(nxt-prev).normalized();side=Vector((-t.y,t.x))*1.1
  for q in [Vector(p)-side,Vector(p)+side]:
   # Stop before the raised lookout, following the terrain height.
   hit=surface.ray_cast(Vector((q.x,q.y,10)),Vector((0,0,-1)))[0]
   h=hit.z if hit else -.3
   vs.append((q.x,q.y,h+.035))
 mesh('village_path',vs,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(pts)-1)],'sand')

def explorer():
 # A clean, stylised human with pivoted limbs; engine animates the pivots.
 cube('torso',(0,0,1.12),(.52,.28,.58),'shirt',.08)
 cube('hips',(0,0,.77),(.44,.26,.2),'pants',.035)
 cube('collar',(0,0,1.43),(.22,.18,.06),'trim',.02)
 segment('neck',(0,0,1.39),(0,0,1.52),.085,'skin',8)
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=1,location=(0,-.015,1.67));o=bpy.context.object;o.scale=(.17,.16,.22);register(o,'head','skin')
 # Front is -Y in Blender, mapping to +Z in Godot.
 cube('nose',(0,-.17,1.66),(.065,.07,.07),'skin',.02)
 cube('hair',(0,.015,1.83),(.32,.29,.1),'hair',.04)
 for sign,side in [(-1,'Left'),(1,'Right')]:
  limb=bpy.data.objects.new(side+'Leg',None);limb.location=(sign*.13,0,.75);CURRENT.objects.link(limb)
  leg=cube(side+'Trouser',(sign*.13,0,.44),(.19,.22,.62),'pants',.035)
  shoe=cube(side+'Shoe',(sign*.13,-.055,.1),(.22,.34,.17),'shoe',.04)
  bpy.context.view_layer.update()
  for obj in [leg,shoe]:
   obj.parent=limb;obj.matrix_parent_inverse=Matrix.Identity(4);obj.location-=limb.location
  arm=bpy.data.objects.new(side+'Arm',None);arm.location=(sign*.32,0,1.35);CURRENT.objects.link(arm)
  sleeve=cube(side+'Sleeve',(sign*.33,0,1.25),(.19,.24,.25),'shirt',.04)
  fore=segment(side+'Forearm',(sign*.34,0,1.16),(sign*.35,-.015,.88),.075,'skin',8)
  hand=cube(side+'Hand',(sign*.35,-.015,.83),(.13,.16,.16),'skin',.035)
  bpy.context.view_layer.update()
  for obj in [sleeve,fore,hand]:
   obj.parent=arm;obj.matrix_parent_inverse=Matrix.Identity(4);obj.location-=arm.location
 # Hat with a recognisable brim and crown.
 bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=.29,depth=.035,location=(0,0,1.89));register(bpy.context.object,'hat_brim','pants')
 bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=.19,radius2=.16,depth=.18,location=(0,.01,1.99));register(bpy.context.object,'hat_crown','pants')
 cube('hat_band',(0,-.16,1.94),(.28,.04,.055),'wood',.01)

for name,fn in [('cottage',cottage),('palm',palm),('coastal_rocks',rocks),('jetty',jetty),('grass_tuft',grass),('bench',bench),('island_terrain',terrain),('explorer',explorer)]:asset(name,fn)

# Build a composed preview from linked copies of the exported resource geometry.
CURRENT=bpy.data.collections.new('Preview');bpy.context.scene.collection.children.link(CURRENT)
def place(name,at,rotation=0,scale=1):
 root=bpy.data.objects.new(name+'_instance',None);CURRENT.objects.link(root);root.location=at;root.rotation_euler.z=rotation;root.scale=(scale,)*3
 originals=ASSETS[name].objects;copies={}
 for o in originals:
  if '-colonly' in o.name:continue
  cp=o.copy();cp.data=o.data;CURRENT.objects.link(cp);cp.hide_render=False;copies[o]=cp
 for o,cp in copies.items():cp.parent=copies.get(o.parent,root)
 return root
place('island_terrain',(0,0,0))
for p in [(-7,1,.42),(6,3,.42),(-8,10,.42)]:place('cottage',p)
for i,p in enumerate([(-14,-9,.42),(10,-9,.42),(-18,6,.42),(16,10,.6),(5,15,.42),(-20,-1,.42),(-9,-15,.42),(15,-3,.42)]):place('palm',p,i*1.7,.95+(i%3)*.1)
for p in [(-21,-12,.3),(21,-8,.3),(20,13,.5),(-17,15,.3)]:place('coastal_rocks',p,1.3,1.1)
place('jetty',(0,-28,-.1));place('bench',(-4,-3,.42),math.pi)
place('explorer',(0,-10,.42),math.pi/8)
for i in range(35):
 rng=random.Random(i*17);x=rng.uniform(-21,21);y=rng.uniform(-15,18)
 if abs(x)>4:place('grass_tuft',(x,y,.43),i)
# Water plane, slightly below the sandy shoreline.
cube('Ocean',(0,0,-.42),(200,200,.08),'water')
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=48
scene.cycles.use_denoising=False
scene.world.color=(.45,.55,.65)
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.78,.85,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.light_add(type='SUN',location=(0,-10,20));sun=bpy.context.object;sun.rotation_euler=(.5,-.4,-.5);sun.data.energy=3;sun.data.angle=.12
bpy.ops.object.camera_add(location=(34,-48,27));camera=bpy.context.object
camera.rotation_euler=(Vector((0,-2,1))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=47;scene.camera=camera
scene.render.resolution_x=1600;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(PREVIEW/'island-resources-preview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW/'resource-preview.blend'))
bpy.ops.render.render(write_still=True)
# A closer view checks resource detail at player scale.
camera.location=(13,-24,12);camera.rotation_euler=(Vector((-1,0,1))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=26
scene.render.filepath=str(PREVIEW/'village-resources-preview.png');bpy.ops.render.render(write_still=True)
report={}
for name,col in ASSETS.items():
 meshes=[o for o in col.objects if o.type=='MESH'];report[name]={'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),'mesh_nodes':len(meshes),'bytes':(OUT/(name+'.glb')).stat().st_size}
(OUT/'manifest.json').write_text(json.dumps({'generator':'tools/generate_assets.py','blender_version':bpy.app.version_string,'units':'metres','source':'original procedural models, no external assets','assets':report},indent=2))
print('ASSET_REPORT',json.dumps(report))
