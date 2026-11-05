import { createClient } from '@supabase/supabase-js';
import { createHmac } from 'node:crypto';
import { normalizeTracking, validTracking } from '../lib/validation.js';

export function makeHandler({ env = process.env, fetcher = fetch, clientFactory = createClient } = {}) {
 return async function handler(req,res) {
  res.setHeader('Cache-Control','no-store, max-age=0');
  res.setHeader('Pragma','no-cache');
  res.setHeader('X-Content-Type-Options','nosniff');
  if((env.VITE_APP_MODE||'public')!=='public') return res.status(404).json({error:'NOT_FOUND'});
  if(req.method!=='POST') {res.setHeader('Allow','POST');return res.status(405).json({error:'METHOD'});}
  const required=['APP_ORIGIN','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','TURNSTILE_SECRET_KEY','TURNSTILE_HOSTNAME','RATE_LIMIT_SECRET'];
  if(required.some(k=>!env[k]) || env.RATE_LIMIT_SECRET.length<32) return res.status(503).json({error:'UNAVAILABLE'});
  if(req.headers.origin!==env.APP_ORIGIN) return res.status(403).json({error:'FORBIDDEN'});
  if(!String(req.headers['content-type']||'').startsWith('application/json')) return res.status(415).json({error:'INVALID'});
  try {
   const body=typeof req.body==='string'?JSON.parse(req.body):req.body;
   if(!body || JSON.stringify(body).length>4096) return res.status(400).json({error:'INVALID'});
   const tracking=normalizeTracking(body.tracking);
   if(!validTracking(tracking)||typeof body.token!=='string'||body.token.length<1||body.token.length>2048) return res.status(400).json({error:'INVALID'});
   // Vercel replaces x-forwarded-for at its edge. Do not expose this handler through an untrusted proxy.
   const ip=String(req.headers['x-forwarded-for']||'').split(',')[0].trim();
   if(!ip && env.VERCEL) return res.status(503).json({error:'UNAVAILABLE'});
   const bucket=createHmac('sha256',env.RATE_LIMIT_SECRET).update(ip||'local-development').digest('hex');
   const db=clientFactory(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
   const limit=await db.rpc('take_rate_limit',{p_bucket:bucket});
   if(limit.error) return res.status(503).json({error:'UNAVAILABLE'});
   if(!limit.data) {res.setHeader('Retry-After','600');return res.status(429).json({error:'RATE_LIMIT'});}
   const verify=await fetcher('https://challenges.cloudflare.com/turnstile/v0/siteverify',{
    method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({secret:env.TURNSTILE_SECRET_KEY,response:body.token,...(ip?{remoteip:ip}:{})}),signal:AbortSignal.timeout(7000)
   });
   if(!verify.ok) return res.status(503).json({error:'UNAVAILABLE'});
   const check=await verify.json();
   if(!check.success||check.hostname!==env.TURNSTILE_HOSTNAME||check.action!=='track') return res.status(400).json({error:'CHALLENGE'});
   const {data,error}=await db.rpc('lookup_public',{p_tracking:tracking});
   if(error) return res.status(503).json({error:'UNAVAILABLE'});
   // A second allowlist at the HTTP boundary prevents accidental exposure after SQL changes.
   const result=data?{tracking:data.tracking,registered_date:data.registered_date,status:data.status,note_ar:data.note_ar,note_de:data.note_de}:null;
   return res.status(200).json({result});
  } catch { return res.status(503).json({error:'UNAVAILABLE'}); }
 };
}
export default makeHandler();
