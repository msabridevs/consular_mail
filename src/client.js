import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const db=url&&key?createClient(url,key,{auth:{storage:window.sessionStorage,persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}}):null;
export async function rpc(name,args){const {data,error}=await db.rpc(name,args);if(error)throw error;return data;}
