import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.185.1/build/three.module.min.js";

const canvas=document.getElementById("farm3d");
const stage=canvas?.closest(".islandStage");
const button=document.getElementById("viewModeBtn");
const reduced=matchMedia("(prefers-reduced-motion: reduce)").matches;
let renderer=null,scene=null,camera=null,staticGroup=null,dynamicGroup=null,active=false,entered=false;
let staticSignature="",lastWidth=0,lastHeight=0,staticBaseCount=0;
const animalMeshes=new Map();
const colors={ink:0x3d2b2b,grass:0x75c95c,wood:0x8b562f,leaf:0x3e9a4b,water:0x45bfe0};

const mat=(color,extra={})=>new THREE.MeshToonMaterial({color,...extra});
function mesh(geometry,color,extra){
  const out=new THREE.Mesh(geometry,mat(color,extra)); out.castShadow=true; out.receiveShadow=true; return out;
}
function add(parent,geometry,color,pos=[0,0,0],scale=[1,1,1],rotation=[0,0,0]){
  const out=mesh(geometry,color); out.position.set(...pos); out.scale.set(...scale); out.rotation.set(...rotation); parent.add(out); return out;
}
function mapPoint(x,y){ return new THREE.Vector3((x-450)/18,0,(y-390)/16); }
function disposeObject(root){
  root?.traverse(o=>{ if(o.geometry)o.geometry.dispose(); if(o.material){const list=Array.isArray(o.material)?o.material:[o.material];list.forEach(m=>m.dispose());} });
}
function roundedBox(w,h,d,r=.18,color=0xffffff){
  r=Math.min(r,w/2,h/2,d/2);
  const g=new THREE.Group();
  add(g,new THREE.BoxGeometry(Math.max(.01,w-r*2),h,d),color);
  add(g,new THREE.BoxGeometry(w,h,Math.max(.01,d-r*2)),color);
  const ball=new THREE.SphereGeometry(r,10,7);
  for(const x of [-w/2+r,w/2-r])for(const y of [-h/2+r,h/2-r])for(const z of [-d/2+r,d/2-r]) add(g,ball,color,[x,y,z]);
  return g;
}
function init(){
  if(renderer||!canvas||!stage||reduced)return false;
  try{
    const probe=document.createElement("canvas"); if(!probe.getContext("webgl2"))return false;
    renderer=new THREE.WebGLRenderer({canvas,antialias:true,alpha:false,powerPreference:"high-performance"});
    renderer.setPixelRatio(Math.min(devicePixelRatio||1,1.5));
    renderer.shadowMap.enabled=true; renderer.shadowMap.type=THREE.PCFShadowMap;
    renderer.outputColorSpace=THREE.SRGBColorSpace; renderer.toneMapping=THREE.ACESFilmicToneMapping; renderer.toneMappingExposure=1.08;
    scene=new THREE.Scene(); scene.background=new THREE.Color(0x91dcff); scene.fog=new THREE.Fog(0xbeeaff,48,82);
    camera=new THREE.PerspectiveCamera(38,1,.1,140); camera.position.set(0,31,38); camera.lookAt(0,0,4);
    scene.add(new THREE.HemisphereLight(0xe9f8ff,0x497b38,2.25));
    const sun=new THREE.DirectionalLight(0xfff1bd,3.4); sun.position.set(-18,34,22); sun.castShadow=true;
    sun.shadow.mapSize.set(1024,1024); sun.shadow.camera.left=-32;sun.shadow.camera.right=32;sun.shadow.camera.top=30;sun.shadow.camera.bottom=-30; scene.add(sun);
    staticGroup=new THREE.Group(); dynamicGroup=new THREE.Group(); scene.add(staticGroup,dynamicGroup);
    buildBase(); staticBaseCount=staticGroup.children.length; return true;
  }catch(err){ console.warn("Math Farm 3D unavailable",err); renderer?.dispose(); renderer=null; return false; }
}
function buildBase(){
  const meadow=add(staticGroup,new THREE.PlaneGeometry(100,100),0x72b958,[0,-1.31,10],[1,1,1],[-Math.PI/2,0,0]); meadow.receiveShadow=true;
  const ground=roundedBox(51,1.1,29,1.25,0x69b950); ground.position.set(0,-.72,-1); staticGroup.add(ground);
  add(staticGroup,new THREE.PlaneGeometry(20.7,23.5),0x71bd55,[-11.8,.02,.5],[1,1,1],[-Math.PI/2,0,0]);
  add(staticGroup,new THREE.PlaneGeometry(21,23.5),0x91d862,[11.5,.025,.5],[1,1,1],[-Math.PI/2,0,0]);
  const path=add(staticGroup,new THREE.PlaneGeometry(3.7,23),0xe0bd73,[.2,.04,2.5],[1,1,1],[-Math.PI/2,0,-.05]); path.receiveShadow=true;
  const pond=roundedBox(18.3,.28,6.55,.7,0xd9c58c); pond.position.copy(mapPoint(680,502)); pond.position.y=.08; staticGroup.add(pond);
  const water=roundedBox(17.4,.22,5.8,.58,colors.water); water.position.copy(pond.position);water.position.y=.28;staticGroup.add(water);
  const sun=mesh(new THREE.SphereGeometry(2.4,20,14),0xffdb55); sun.position.set(18,23,-15); scene.add(sun);
  for(let i=0;i<5;i++){
    const cloud=new THREE.Group(); for(const [x,y,s] of [[0,0,1.4],[-1.4,-.1,1],[1.4,-.15,1.1]]) add(cloud,new THREE.SphereGeometry(1,12,8),0xffffff,[x,y,0],[s,.72*s,.75*s]);
    cloud.position.set(-22+i*11,18+(i%2)*2,-18-i); scene.add(cloud);
  }
}
function buildTree(t){
  const g=new THREE.Group(),p=mapPoint(t.x,t.y); g.position.copy(p);
  add(g,new THREE.CylinderGeometry(.42,.62,3.4,8),colors.wood,[0,1.7,0]);
  add(g,new THREE.SphereGeometry(1.45,12,9),0x378f43,[0,4.2,0],[1.25,1,1]);
  add(g,new THREE.SphereGeometry(1.15,12,9),0x52ad4f,[-.8,3.9,.25]);
  add(g,new THREE.SphereGeometry(1.05,12,9),0x68bd55,[.85,4,.1]);
  return g;
}
function buildHouse(d){
  const g=new THREE.Group(); g.position.copy(mapPoint(d.x,d.y));
  add(g,new THREE.BoxGeometry(4.8,3.7,4.2),0xf0c68e,[0,1.85,0]);
  add(g,new THREE.ConeGeometry(3.8,2.5,4),0xc95238,[0,4.75,0],[1,1,1],[0,Math.PI/4,0]);
  add(g,new THREE.BoxGeometry(1.15,2.35,.22),0x8a5b35,[0,1.18,2.12]);
  add(g,new THREE.BoxGeometry(1.1,1.1,.2),0x9fe3ff,[-1.45,2.35,2.13]);
  return g;
}
function buildFence(d){
  const g=new THREE.Group(); g.position.copy(mapPoint(d.x,d.y)); const vertical=d.orientation==="vertical";
  add(g,new THREE.BoxGeometry(.36,2.2,.36),0x8a542d,vertical?[0,1.1,-1.15]:[-1.15,1.1,0]);
  add(g,new THREE.BoxGeometry(.36,2.2,.36),0x8a542d,vertical?[0,1.1,1.15]:[1.15,1.1,0]);
  const rail=new THREE.BoxGeometry(vertical?.27:2.65,.24,vertical?2.65:.27);
  add(g,rail,0xb9783f,[0,.72,0]); add(g,rail,0xb9783f,[0,1.52,0]); return g;
}
function buildDecor(d){
  if(d.type==="house")return buildHouse(d); if(d.type==="fence")return buildFence(d);
  const g=new THREE.Group();g.position.copy(mapPoint(d.x,d.y));
  if(d.type==="flower"){
    add(g,new THREE.CylinderGeometry(.06,.08,.7,6),0x398e3c,[0,.35,0]);
    for(let i=0;i<6;i++){const a=i*Math.PI/3;add(g,new THREE.SphereGeometry(.18,8,6),i%2?0xff8db6:0xffcf44,[Math.cos(a)*.28,.88,Math.sin(a)*.28]);}
  }else if(d.type==="fountain"){
    add(g,new THREE.CylinderGeometry(1.55,1.75,.45,18),0xd7d2bd,[0,.23,0]); add(g,new THREE.CylinderGeometry(.22,.35,2.5,10),0xc6c1ae,[0,1.45,0]);
    add(g,new THREE.SphereGeometry(.38,12,8),0x72d8f0,[0,2.65,0]);
  }else{
    add(g,new THREE.CylinderGeometry(.85,1.05,.55,10),0xc8c0a8,[0,.27,0]); add(g,new THREE.CapsuleGeometry(.55,1.25,5,10),0xada998,[0,1.5,0]);
  } return g;
}
function rebuildStatic(state){
  [...staticGroup.children].slice(staticBaseCount).forEach(o=>{staticGroup.remove(o);disposeObject(o);});
  state.trees.filter(t=>t.alive).forEach(t=>staticGroup.add(buildTree(t)));
  state.decors.forEach(d=>staticGroup.add(buildDecor(d)));
}
function eye(parent,x){
  add(parent,new THREE.SphereGeometry(.12,10,7),colors.ink,[x,1.83,.92],[1,1.25,.55]);
  add(parent,new THREE.SphereGeometry(.035,7,5),0xffffff,[x-.025,1.88,.985]);
}
function addAccessory(g,id){
  if(id==="hat"){
    add(g,new THREE.CylinderGeometry(.78,.9,.2,16),0x332947,[0,2.62,.05]); add(g,new THREE.CylinderGeometry(.53,.62,.8,16),0x46345f,[0,3.04,.05]);
  }else if(id==="bow"){
    add(g,new THREE.SphereGeometry(.36,10,7),0xff4e91,[-.38,1.1,.86],[1.25,.65,.4]); add(g,new THREE.SphereGeometry(.36,10,7),0xff4e91,[.38,1.1,.86],[1.25,.65,.4]);
    add(g,new THREE.SphereGeometry(.18,9,6),0xffcf46,[0,1.1,1]);
  }else if(id==="bag"){
    const bag=roundedBox(1.35,1.25,.5,.2,0xf06b45);bag.position.set(-1.05,1.05,-.38);bag.rotation.z=.08;g.add(bag);
  }
}
function animalColor(type,accessory){
  if(accessory==="color_pink")return 0xd53f86;if(accessory==="color_blue")return 0x197daa;if(accessory==="color_gold")return 0xbd8100;
  return ({cow:0xf2eee2,pug:0xd9aa74,pig:0xf49ab2,chicken:0xf0a13b,duck:0xf7d74e,fish:0x3bbdd3,sheep:0xf0eadf,rabbit:0xe6d7d3})[type]||0xe49a54;
}
function buildAnimal(a){
  const g=new THREE.Group(),body=animalColor(a.type,a.accessory),shade=new THREE.Color(body).multiplyScalar(.78).getHex();
  add(g,new THREE.SphereGeometry(1,14,10),body,[0,.82,0],[1.12,.83,.86]);
  add(g,new THREE.SphereGeometry(1,14,10),body,[0,1.72,.18],[.78,.8,.76]);
  add(g,new THREE.ConeGeometry(.28,.65,8),shade,[-.62,2.35,.08],[1,1,1],[0,0,.38]);
  add(g,new THREE.ConeGeometry(.28,.65,8),shade,[.62,2.35,.08],[1,1,1],[0,0,-.38]);
  eye(g,-.27);eye(g,.27); add(g,new THREE.SphereGeometry(.13,10,7),0x70412f,[0,1.54,.96],[1.2,.75,.55]);
  add(g,new THREE.SphereGeometry(.18,10,7),0xff8e93,[-.5,1.48,.84],[1.1,.55,.35]); add(g,new THREE.SphereGeometry(.18,10,7),0xff8e93,[.5,1.48,.84],[1.1,.55,.35]);
  for(const x of [-.62,.62])add(g,new THREE.CylinderGeometry(.17,.2,.65,8),shade,[x,.28,0]);
  if(a.type==="cow"){
    add(g,new THREE.SphereGeometry(.35,9,7),0x3f3637,[-.38,1.93,.73],[1.1,.8,.35]);
    add(g,new THREE.SphereGeometry(.22,9,7),0x3f3637,[.48,.82,.7],[1.4,.85,.4]);
    add(g,new THREE.ConeGeometry(.12,.45,7),0xd9ad62,[-.45,2.45,.18],[1,1,1],[0,0,.2]);add(g,new THREE.ConeGeometry(.12,.45,7),0xd9ad62,[.45,2.45,.18],[1,1,1],[0,0,-.2]);
  }else if(a.type==="chicken"){
    for(let i=0;i<3;i++)add(g,new THREE.SphereGeometry(.22,8,6),0xe44739,[(i-1)*.25,2.53,.05]);
    add(g,new THREE.ConeGeometry(.2,.45,4),0xf2b22d,[0,1.57,1.08],[1,1,1],[Math.PI/2,0,0]);
  }else if(a.type==="fish"){
    g.scale.set(.92,.72,1);add(g,new THREE.ConeGeometry(.65,1.1,3),shade,[-1.15,.8,0],[1,1,1],[0,0,-Math.PI/2]);
  }else if(a.type==="pug"){
    add(g,new THREE.SphereGeometry(.55,12,8),0x6a4738,[0,1.55,.65],[1,.72,.45]);
  }
  addAccessory(g,a.accessory); return g;
}
function makePlayer(state){
  const g=new THREE.Group(),c=new THREE.Color(state.color||"#4a90ff").getHex();
  add(g,new THREE.CapsuleGeometry(.63,1.25,5,10),c,[0,1.15,0]); add(g,new THREE.SphereGeometry(.72,14,10),0xeaf7ff,[0,2.35,0]);
  add(g,new THREE.BoxGeometry(1.12,.42,.16),0x21334e,[0,2.38,.68]);
  for(const x of [-.26,.26])add(g,new THREE.SphereGeometry(.08,8,6),0x63f5cf,[x,2.4,.79]);
  add(g,new THREE.CylinderGeometry(.12,.12,.55,8),0xb9c8d8,[-.48,.25,0]);add(g,new THREE.CylinderGeometry(.12,.12,.55,8),0xb9c8d8,[.48,.25,0]); return g;
}
function updateDynamic(state){
  const live=new Set(state.animals.map(a=>a.key));
  for(const [key,o] of animalMeshes)if(!live.has(key)){dynamicGroup.remove(o);disposeObject(o);animalMeshes.delete(key);}
  for(const a of state.animals){
    let g=animalMeshes.get(a.key);
    if(!g||g.userData.style!==`${a.type}:${a.accessory}`){if(g){dynamicGroup.remove(g);disposeObject(g);}g=buildAnimal(a);g.userData.style=`${a.type}:${a.accessory}`;animalMeshes.set(a.key,g);dynamicGroup.add(g);}
    const p=mapPoint(a.x,a.y);g.position.set(p.x,.18+(reduced?0:Math.sin(state.t*.045+(a.phase||0))*.08),p.z);g.rotation.y=(a.dir||1)<0?-.12:.12;
  }
  let playerMesh=dynamicGroup.getObjectByName("player");
  if(!playerMesh&&state.player){playerMesh=makePlayer(state.player);playerMesh.name="player";dynamicGroup.add(playerMesh);}
  if(playerMesh&&state.player){const p=mapPoint(state.player.x,state.player.y);playerMesh.position.set(p.x,.12+(reduced?0:Math.sin(state.t*.09)*.04),p.z);playerMesh.rotation.y=state.player.dir<0?-.16:.16;}
}
function resize(){
  const w=Math.max(1,canvas.clientWidth),h=Math.max(1,canvas.clientHeight); if(w===lastWidth&&h===lastHeight)return;
  lastWidth=w;lastHeight=h;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();
}
function setActive(next,remember=true){
  active=Boolean(next&&entered&&renderer);stage?.classList.toggle("mode3d",active);
  if(button){button.disabled=!renderer;button.innerHTML=active?'<span class="wideLabel">🎨 2D</span><span class="compactLabel">2D</span>':'<span class="wideLabel">🧊 3D</span><span class="compactLabel">3D</span>';button.setAttribute("aria-pressed",String(active));}
  if(remember)try{localStorage.setItem("math_farm_view",active?"3d":"2d");}catch(_){}
  if(!active&&window.drawFarm&&entered)window.drawFarm();
}
function enterFarm(){
  entered=true; const ok=init(); if(button){button.disabled=!ok;button.title=ok?"สลับมุมมองฟาร์ม 2D และ 3D":"เครื่องนี้ไม่รองรับ WebGL 2 หรือเปิดโหมดลดการเคลื่อนไหว";}
  let pref="";try{pref=localStorage.getItem("math_farm_view")||"";}catch(_){}
  const desktop=matchMedia("(min-width: 760px)").matches; setActive(ok&&(pref==="3d"||(!pref&&desktop)),false);
}
function leaveFarm(){entered=false;setActive(false,false);}
function render(state){
  if(!active||!renderer||!state?.active)return;resize();
  const signature=JSON.stringify([state.trees.map(t=>[t.id,t.alive]),state.decors]);if(signature!==staticSignature){staticSignature=signature;rebuildStatic(state);}
  updateDynamic(state);renderer.render(scene,camera);
}
function toggle(){setActive(!active);}

const available=init();
window.MathFarm3D={available,enterFarm,leaveFarm,render,toggle,isActive:()=>active};
if(button){button.disabled=!available;button.title=available?"สลับมุมมองฟาร์ม 2D และ 3D":"เครื่องนี้ไม่รองรับ WebGL 2 หรือเปิดโหมดลดการเคลื่อนไหว";}
addEventListener("webglcontextlost",e=>{if(e.target!==canvas)return;e.preventDefault();setActive(false,false);if(button)button.disabled=true;},{passive:false});
