import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,readdir,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {makeHandler} from '../api/track.js';

const root=fileURLToPath(new URL('..',import.meta.url));
async function output(mode,base){
 const dir=join(base,mode);
 const r=spawnSync(process.execPath,[join(root,'node_modules/vite/bin/vite.js'),'build','--outDir',dir,'--emptyOutDir'],{
  cwd:root,encoding:'utf8',env:{...process.env,VITE_APP_MODE:mode,VITE_SUPABASE_URL:'https://example.supabase.co',VITE_SUPABASE_ANON_KEY:'unique-public-client-sentinel'}
 });
 assert.equal(r.status,0,r.stdout+r.stderr);
 const assets=await readdir(join(dir,'assets'));
 const js=(await Promise.all(assets.filter(f=>f.endsWith('.js')).map(f=>readFile(join(dir,'assets',f),'utf8')))).join('\n');
 return {js,html:await readFile(join(dir,'index.html'),'utf8')};
}
test('Separate production builds exclude employee authentication from citizen assets',async()=>{
 const base=await mkdtemp(join(tmpdir(),'consular-separation-'));
 try{
  const pub=await output('public',base);
  const staff=await output('staff',base);
  assert.ok(!pub.js.includes('signInWithPassword'));
  assert.ok(!pub.js.includes('unique-public-client-sentinel'));
  assert.ok(!pub.js.includes('challengeAndVerify'));
  assert.ok(!pub.js.includes('register_mail'));
  assert.ok(!pub.js.includes('href:"/staff"'));
  assert.ok(staff.js.includes('signInWithPassword'));
  assert.ok(staff.js.includes('register_mail'));
  assert.ok(!staff.js.includes('/api/track'));
  assert.ok(!staff.js.includes('turnstile/v0/api.js'));
  const config=JSON.parse(await readFile(join(root,'vercel.json'),'utf8'));
  assert.equal(config.rewrites,undefined);
  assert.deepEqual(config.redirects.find(r=>r.source==='/staff'),{source:'/staff',destination:'/',permanent:false});
 }finally{await rm(base,{recursive:true,force:true});}
});
test('Employee deployment refuses public tracking endpoint without accessing services',async()=>{
 let accessed=false;
 const handler=makeHandler({env:{VITE_APP_MODE:'staff'},clientFactory:()=>{accessed=true;throw Error('must not run');}});
 const res={setHeader(){},status(c){this.code=c;return this;},json(body){this.body=body;}};
 await handler({method:'POST',headers:{},body:{}},res);
 assert.equal(res.code,404);assert.equal(accessed,false);
});
test('Invalid deployment mode fails the build',()=>{
 const r=spawnSync(process.execPath,[join(root,'node_modules/vite/bin/vite.js'),'build'],{cwd:root,encoding:'utf8',env:{...process.env,VITE_APP_MODE:'typo'}});
 assert.notEqual(r.status,0);assert.match(r.stdout+r.stderr,/VITE_APP_MODE must be public or staff/);
});
