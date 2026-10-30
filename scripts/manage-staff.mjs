// Run with Node >=22: node --env-file=.env scripts/manage-staff.mjs
// Secrets come from .env; passwords entered interactively are never logged.
import {createClient} from '@supabase/supabase-js';
import {createInterface} from 'node:readline/promises';
import {stdin,stdout} from 'node:process';
const rl=createInterface({input:stdin,output:stdout});
try {
 if(!process.env.SUPABASE_URL||!process.env.SUPABASE_SERVICE_ROLE_KEY)throw new Error('Missing server environment variables.');
 const db=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
 console.log('Create a confirmed staff authentication account. This does not assign application permissions.');
 const email=(await rl.question('Work email: ')).trim();
 // Generate a temporary random password rather than echo a typed password.
 const {randomBytes}=await import('node:crypto');
 const password=randomBytes(24).toString('base64url')+'aA1!';
 const {data,error}=await db.auth.admin.createUser({email,password,email_confirm:true});
 if(error)throw error;
 console.log('User UUID:',data.user.id);
 console.log('Temporary password (deliver privately, change after first login):',password);
 console.log('Now assign role/departments with supabase/002_staff-template.sql in the SQL Editor.');
} catch(e){console.error(e.message);process.exitCode=1;} finally{rl.close();}
