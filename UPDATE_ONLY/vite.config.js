import {defineConfig,loadEnv} from 'vite';

export default defineConfig(({mode})=>{
 const env=loadEnv(mode,process.cwd(),'VITE_');
 const appMode=process.env.VITE_APP_MODE ?? env.VITE_APP_MODE ?? 'public';
 if(!['public','staff'].includes(appMode)) throw new Error('VITE_APP_MODE must be public or staff');
 return {
  plugins:[{
   name:'separate-consular-entry',
   transformIndexHtml:{order:'pre',handler(html){
    return appMode==='staff'?html.replace('/src/main.jsx','/src/staff-main.jsx'):html;
   }}
  }]
 };
});
