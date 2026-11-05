import React,{useState,useEffect} from 'react';
import {labels} from './i18n.js';
import {Language} from './shared.jsx';
import './style.css';
export default function Shell({children,internal=false}) {
 const [lang,setLang]=useState(localStorage.getItem('language')==='de'?'de':'ar');
 const t=labels[lang];
 useEffect(()=>{document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';localStorage.setItem('language',lang);document.title=t.brand+' | Frankfurt';},[lang]);
 return <Language.Provider value={{lang,t}}><header><a className="brand" href="/"><span className="mark">✉</span><span><strong>{t.brand}</strong><small>{t.mission}</small></span></a><nav><button className="language" onClick={()=>setLang(lang==='ar'?'de':'ar')}>{lang==='ar'?'Deutsch':'العربية'}</button></nav></header>{children}<footer>{t.mission}<span>{internal?t.security:t.publicFoot}</span></footer></Language.Provider>;
}
