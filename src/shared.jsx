import React,{createContext,useContext} from 'react';
export const Language=createContext();
export function useL(){return useContext(Language);}
export function Alert({children,error=false}){return children?<div role={error?'alert':'status'} className={`alert ${error?'error':''}`}>{children}</div>:null;}
export function Field({label,children}){return <label className="field"><span>{label}</span>{children}</label>;}
export function Badge({status}){const {t}=useL();return <span className={`badge ${status}`}>{t[status]||status}</span>;}
export function date(v,lang,only=false){if(!v)return '—';return new Intl.DateTimeFormat(lang==='ar'?'ar-EG':'de-DE',{timeZone:'Europe/Berlin',dateStyle:'medium',...(only?{}:{timeStyle:'short'})}).format(new Date(v.length===10?v+'T12:00:00Z':v));}
export function money(v,lang){return new Intl.NumberFormat(lang==='ar'?'ar-EG':'de-DE',{style:'currency',currency:'EUR'}).format(v/100);}
