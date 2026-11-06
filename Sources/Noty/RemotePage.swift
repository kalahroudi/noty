// SPDX-License-Identifier: Apache-2.0

/// The single page served to your phone or another computer over Tailscale. Plain HTML and JS, no libraries, follows the system light/dark theme.
/// It renders Markdown and the notes' inline tags (see NotesMarkdown) as DOM nodes, never as HTML strings, and edits notes in the same dialect.
enum RemotePage {
    static let html = #"""
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-title" content="Noty">
<title>Noty</title>
<style>
:root{--bg:#f6f5f1;--card:#fff;--ink:#1c1c1e;--mute:#6b6b70;--line:#e4e2db;--accent:#f5c518;--accent-ink:#1c1c1e;--danger:#c0392b;--base:15px;--fill:#efede6}
@media(prefers-color-scheme:dark){:root{--bg:#161618;--card:#222226;--ink:#f2f2f4;--mute:#9b9ba3;--line:#34343a;--accent:#f5c518;--fill:#2b2b30}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.4 -apple-system,system-ui,sans-serif;padding:env(safe-area-inset-top) 16px env(safe-area-inset-bottom)}
main{max-width:640px;margin:0 auto;padding:14px 0 40px}
h1{font-size:20px;margin:6px 0 12px}
input,textarea{width:100%;font:inherit;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:11px 12px}
button{font:inherit;color:inherit;cursor:pointer}
.addrow{display:flex;gap:8px}.addrow input{flex:1}.clip{flex:none;width:46px;border-radius:10px;border:1px solid var(--line);background:var(--card);font-size:15px}
.tabs{display:flex;gap:6px;margin:12px 0;overflow-x:auto}
.tabs button{flex:none;font-size:14px;padding:7px 13px;border-radius:999px;border:1px solid var(--line);background:var(--card)}
.tabs button.on{background:var(--accent);color:var(--accent-ink);border-color:var(--accent);font-weight:600}
.row{display:flex;align-items:center;gap:12px;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 12px;margin-bottom:8px}
.row .t{flex:1;min-width:0}.row .t b{font-weight:500;display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.row small,.mute{color:var(--mute);font-size:12.5px}.done b{text-decoration:line-through;color:var(--mute)}
.chk{width:26px;height:26px;border-radius:7px;border:2px solid var(--mute);background:none;flex:none;padding:0;color:var(--accent-ink);font-size:15px}
.done .chk{background:var(--accent);border-color:var(--accent)}
.empty{text-align:center;color:var(--mute);padding:40px 0}
#sheet{position:fixed;inset:0;background:rgba(0,0,0,.4);display:none;align-items:flex-end}
#sheet.on{display:flex}#sheet>div{background:var(--bg);width:100%;max-height:92vh;overflow:auto;border-radius:18px 18px 0 0;padding:18px 16px 28px;max-width:640px;margin:0 auto}
.sec{font-size:11.5px;font-weight:600;letter-spacing:.05em;text-transform:uppercase;color:var(--mute);margin:16px 0 6px}
.btns{display:flex;gap:8px;margin-top:16px}.btns button,.pill{flex:1;padding:11px;border-radius:10px;border:1px solid var(--line);background:var(--card)}
.btns .p,.pill.p{background:var(--accent);color:var(--accent-ink);border-color:var(--accent);font-weight:600}
.pill{flex:none;padding:8px 13px;font-size:14px}
#err{color:var(--danger);font-size:13px;min-height:18px}
/* rendered markdown */
.md{font-size:var(--base);overflow-wrap:anywhere}.md>*{margin:0 0 8px}.md h1,.md h2,.md h3,.md h4{margin:10px 0 6px;line-height:1.25}.md h1{font-size:1.5em}.md h2{font-size:1.3em}.md h3{font-size:1.15em}.md h4,.md h5,.md h6{font-size:1em}
.md p{white-space:pre-wrap}.md blockquote{margin:0 0 8px;padding:2px 12px;border-left:3px solid var(--accent);color:var(--mute)}
.md pre{background:var(--fill);padding:10px;border-radius:8px;overflow:auto;font-size:.85em}.md code{background:var(--fill);padding:1px 5px;border-radius:4px;font-size:.9em}.md pre code{padding:0;background:none}
.md .li{display:flex;gap:8px}.md .li>span:first-child{color:var(--mute);flex:none}.md hr{border:0;border-top:1px solid var(--line)}
.md .tbl{overflow-x:auto}.md table{border-collapse:collapse;font-size:.92em}.md th,.md td{border:1px solid var(--line);padding:5px 9px;text-align:left}.md th{background:var(--fill)}
.md img,.pics img{max-width:100%;border-radius:8px;border:1px solid var(--line);display:block}.md a{color:inherit;text-decoration:underline}
.quote{border-left:3px solid var(--accent);padding-left:12px}
.pics{display:flex;flex-direction:column;gap:8px}.pics .pic{position:relative}.rm{position:absolute;top:6px;right:6px;width:30px;height:30px;border-radius:50%;border:0;background:rgba(0,0,0,.6);color:#fff;font-size:15px}
.file{display:flex;align-items:center;gap:10px;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:9px 12px;margin-bottom:6px}.file a{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:inherit}.file button{border:0;background:none;color:var(--mute);font-size:16px}
/* notes editor */
.tool{display:flex;gap:4px;overflow-x:auto;padding:6px;background:var(--card);border:1px solid var(--line);border-bottom:0;border-radius:10px 10px 0 0;align-items:center}
.tool button{flex:none;min-width:34px;height:32px;border-radius:7px;border:0;background:none;font-size:15px}.tool button:active{background:var(--fill)}
.tool .sep{width:1px;height:20px;background:var(--line);margin:0 3px;flex:none}.dot{width:18px;height:18px;border-radius:50%;display:block;margin:auto}
#ed{min-height:130px;background:var(--card);border:1px solid var(--line);border-radius:0 0 10px 10px;padding:10px 12px;font-size:var(--base);white-space:pre-wrap;overflow-wrap:anywhere;outline:none}
#ed:empty:before{content:attr(data-ph);color:var(--mute)}.saved{font-size:12px;color:var(--mute);margin-top:4px;min-height:16px}
mark{background:rgba(245,197,24,.42);color:inherit}
#lb{position:fixed;inset:0;background:rgba(0,0,0,.92);display:none;align-items:center;justify-content:center;z-index:5}#lb.on{display:flex}#lb img{max-width:100%;max-height:100%}
</style></head><body><main>
<h1>Noty</h1>
<div class="addrow"><input id="add" placeholder="Quick add to Inbox…" enterkeyhint="send" autocomplete="off"><button class="clip" id="clip" aria-label="Attach files">📎</button></div>
<input id="pick" type="file" multiple hidden>
<div class="tabs" id="tabs"></div>
<input id="q" type="search" placeholder="Search" autocomplete="off">
<div id="err"></div><div id="list" style="margin-top:10px"></div>
</main>
<div id="sheet"><div id="detail"></div></div><div id="lb"><img alt=""></div>
<script>
const $=s=>document.querySelector(s);let view="today",timer,pending=[];
async function api(p,body,raw){const o=body===undefined?{}:raw?{method:"POST",headers:{"X-Noty":"1","Content-Type":raw},body}:{method:"POST",headers:{"X-Noty":"1","Content-Type":"application/json"},body:JSON.stringify(body)};
 const r=await fetch(p,o);const j=await r.json();if(!r.ok)throw new Error(j.error||r.status);return j}
function el(t,c,x){const e=document.createElement(t);if(c)e.className=c;if(x!==undefined)e.textContent=x;return e}
const att=n=>"/api/attachments/"+encodeURIComponent(n);

/* ---------- Markdown (captured text): blocks and inline, as DOM ---------- */
const INL=/\\([\\`*~\[\]()#>!_|-])|`([^`]+)`|!\[([^\]]*)\]\(attachment:(\d+)\)|\[([^\]]+)\]\((https?:\/\/[^\s)]+|mailto:[^\s)]+)\)|\*\*(.+?)\*\*|~~(.+?)~~|\*([^*\s][^*]*?)\*/;
function inline(s,imgs,out){out=out||document.createDocumentFragment();
 while(s){const m=INL.exec(s);if(!m){out.append(s);break}
  if(m.index)out.append(s.slice(0,m.index));
  if(m[1]!==undefined)out.append(m[1]);
  else if(m[2]!==undefined)out.append(el("code","",m[2]));
  else if(m[4]!==undefined){const n=imgs[+m[4]-1];if(n){const i=el("img");i.src=att(n);i.alt=m[3]||"image";i.onclick=()=>zoom(att(n));out.append(i)}}
  else if(m[5]!==undefined){const a=el("a");a.href=m[6];a.target="_blank";a.rel="noopener noreferrer";a.append(inline(m[5],imgs));out.append(a)}
  else if(m[7]!==undefined){const b=el("b");b.append(inline(m[7],imgs));out.append(b)}
  else if(m[8]!==undefined){const d=el("s");d.append(inline(m[8],imgs));out.append(d)}
  else if(m[9]!==undefined){const e=el("i");e.append(inline(m[9],imgs));out.append(e)}
  s=s.slice(m.index+m[0].length)}
 return out}
const cells=l=>l.trim().replace(/^\|/,"").replace(/\|$/,"").split(/(?<!\\)\|/).map(c=>c.trim().replace(/\\\|/g,"|"));
const isBlock=l=>/^(```|#{1,6}\s|>|\s*([-*+]|\d+[.)])\s|\s*\|.*\|\s*$|\s*([-*_])(\s*\3){2,}\s*$)/.test(l);
function renderMD(md,imgs){const root=el("div","md"),L=(md||"").replace(/\r/g,"").split("\n");let i=0,m;
 while(i<L.length){const l=L[i];
  if(/^\s*$/.test(l)){i++;continue}
  if(/^```/.test(l)){const c=[];i++;while(i<L.length&&!/^```/.test(L[i]))c.push(L[i++]);i++;const p=el("pre"),k=el("code","",c.join("\n"));p.append(k);root.append(p);continue}
  if(m=l.match(/^(#{1,6})\s+(.*)$/)){const h=el("h"+Math.min(m[1].length,4));h.append(inline(m[2],imgs));root.append(h);i++;continue}
  if(/^\s*([-*_])(\s*\1){2,}\s*$/.test(l)){root.append(el("hr"));i++;continue}
  if(/^>/.test(l)){const c=[];while(i<L.length&&/^>/.test(L[i]))c.push(L[i++].replace(/^>\s?/,""));const q=el("blockquote");q.append(renderMD(c.join("\n"),imgs));root.append(q);continue}
  if(/^\s*\|.*\|\s*$/.test(l)&&i+1<L.length&&/^\s*\|?\s*:?-{2,}/.test(L[i+1])){
   const rows=[cells(l)];i+=2;while(i<L.length&&/^\s*\|.*\|\s*$/.test(L[i]))rows.push(cells(L[i++]));
   const t=el("table");rows.forEach((r,ri)=>{const tr=el("tr");r.forEach(c=>{const td=el(ri?"td":"th");td.append(inline(c,imgs));tr.append(td)});t.append(tr)});
   const w=el("div","tbl");w.append(t);root.append(w);continue}
  if(m=l.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/)){
   while(i<L.length&&(m=L[i].match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/))){const d=el("div","li");d.style.paddingLeft=Math.floor(m[1].replace(/\t/g,"  ").length/2)*16+"px";
    d.append(el("span","",/\d/.test(m[2])?m[2]:"•"));const t=el("span");t.append(inline(m[3],imgs));d.append(t);root.append(d);i++}
   continue}
  const c=[];while(i<L.length&&!/^\s*$/.test(L[i])&&(!c.length||!isBlock(L[i])))c.push(L[i++]);
  const p=el("p");p.append(inline(c.join("\n"),imgs));root.append(p)}
 return root}

/* ---------- Notes: the app's Markdown dialect (** * ~~ <u> <mark> <span color/size>), as DOM and back ---------- */
const BASE=13,COLORS=[["Red","D64545"],["Orange","D9822B"],["Green","2E9E5B"],["Blue","2F6FED"],["Purple","8A5CD6"]];
function notesDOM(md){const out=document.createDocumentFragment();let b=0,i=0,s=0,u=0,mk=0,cols=[],sizes=[],spans=[],buf="";
 const flush=()=>{if(!buf)return;let n=document.createDocumentFragment();buf.split("\n").forEach((part,k)=>{if(k)n.append(el("br"));if(part)n.append(part)});buf="";
  const wrap=(tag,st)=>{const e=el(tag);if(st)e.style.cssText=st;e.append(n);n=document.createDocumentFragment();n.append(e)};
  if(b)wrap("b");if(i)wrap("i");if(s)wrap("s");if(u)wrap("u");if(mk)wrap("mark");
  if(sizes.length)wrap("span","font-size:calc(var(--base) * "+sizes[sizes.length-1]/BASE+")");
  if(cols.length)wrap("span","color:#"+cols[cols.length-1]);out.append(n)};
 const S=md;let k=0;
 while(k<S.length){const lineStart=k===0||S[k-1]==="\n",r=S.slice(k);
  if(S[k]==="\\"&&k+1<S.length&&"\\*~<".includes(S[k+1])){buf+=S[k+1];k+=2;continue}
  if(r.startsWith("**")){flush();b^=1;k+=2;continue}
  if(S[k]==="*"&&!(lineStart&&S[k+1]===" ")){flush();i^=1;k++;continue}
  if(r.startsWith("~~")){flush();s^=1;k+=2;continue}
  if(r.startsWith("<mark>")){flush();mk=1;k+=6;continue}if(r.startsWith("</mark>")){flush();mk=0;k+=7;continue}
  if(r.startsWith("<u>")){flush();u=1;k+=3;continue}if(r.startsWith("</u>")){flush();u=0;k+=4;continue}
  if(r.startsWith("</span>")){flush();const t=spans.pop();if(t==="c")cols.pop();else if(t==="s")sizes.pop();k+=7;continue}
  if(r.startsWith('<span style="')){const e=S.indexOf(">",k);if(e>0){const tag=S.slice(k,e+1);let m=tag.match(/color:#([0-9A-Fa-f]{6})/);
    if(m){flush();cols.push(m[1].toUpperCase());spans.push("c");k=e+1;continue}
    m=tag.match(/font-size:(\d+)px/);if(m){flush();sizes.push(+m[1]);spans.push("s");k=e+1;continue}}}
  buf+=S[k];k++}
 flush();return out}
function hexOf(c){const m=/rgba?\(\s*(\d+)[ ,]+(\d+)[ ,]+(\d+)/.exec(c||"");return m?[m[1],m[2],m[3]].map(x=>(+x).toString(16).padStart(2,"0")).join("").toUpperCase():null}
function domNotes(root){const rootCS=getComputedStyle(root),baseCol=hexOf(rootCS.color),basePx=parseFloat(rootCS.fontSize)||15;const runs=[];
 const push=(t,st)=>{const key=JSON.stringify(st),l=runs[runs.length-1];if(l&&l.key===key)l.t+=t;else runs.push({t,st,key})};
 const endNL=()=>runs.length&&/\n$/.test(runs[runs.length-1].t);
 (function walk(n,a){
  if(n.nodeType===3){const cs=getComputedStyle(n.parentElement),st={b:+(parseInt(cs.fontWeight)>=600||cs.fontWeight==="bold"),i:+(cs.fontStyle==="italic"),s:a.s,u:a.u,m:a.m,
     px:Math.round(parseFloat(cs.fontSize)/basePx*BASE),c:hexOf(cs.color)===baseCol?null:hexOf(cs.color)};push(n.nodeValue.replace(/ /g," "),st);return}
  if(n.nodeType!==1)return;const t=n.tagName;if(t==="BR"){push("\n",{b:0,i:0,s:0,u:0,m:0,px:BASE,c:null});return}
  const a2={...a},d=(n.style.textDecorationLine||n.style.textDecoration||"");
  if(t==="U"||/underline/.test(d))a2.u=1;if(t==="S"||t==="STRIKE"||t==="DEL"||/line-through/.test(d))a2.s=1;
  const bg=n.style.backgroundColor;if(t==="MARK"||(bg&&bg!=="transparent"&&!/rgba\(0, 0, 0, 0\)/.test(bg)))a2.m=1;else if(bg==="transparent")a2.m=0;
  const blk=t==="DIV"||t==="P";if(blk&&runs.length&&!endNL())push("\n",{b:0,i:0,s:0,u:0,m:0,px:BASE,c:null});
  n.childNodes.forEach(c=>walk(c,a2))})(root,{s:0,u:0,m:0});
 const esc=x=>x.replace(/[\\*~<]/g,"\\$&");let md="";
 for(const r of runs){const st=r.st;r.t.split("\n").forEach((line,k)=>{if(k)md+="\n";const core=line.trim();if(!core){md+=line;return}
   const lead=line.match(/^[ \t]*/)[0],trail=line.match(/[ \t]*$/)[0];let x=esc(core);
   if(st.b)x="**"+x+"**";if(st.i)x="*"+x+"*";if(st.s)x="~~"+x+"~~";if(st.u)x="<u>"+x+"</u>";if(st.m)x="<mark>"+x+"</mark>";
   if(st.px!==BASE)x='<span style="font-size:'+st.px+'px">'+x+"</span>";if(st.c)x='<span style="color:#'+st.c+'">'+x+"</span>";md+=lead+x+trail})}
 return md.replace(/\n+$/,"")}

/* ---------- list ---------- */
const views=[["today","Today"],["inbox","Inbox"],["open","Open"],["done","Done"]];
function tabs(){const t=$("#tabs");t.replaceChildren();for(const[v,n]of views){const b=el("button",v===view?"on":"",n);b.onclick=()=>{view=v;$("#q").value="";tabs();load()};t.append(b)}}
async function load(){try{$("#err").textContent="";const q=$("#q").value.trim();
 const r=await api("/api/items?"+(q?"q="+encodeURIComponent(q):"view="+view));const l=$("#list");l.replaceChildren();
 if(!r.items.length)l.append(el("div","empty",q?"Nothing found.":"All clear."));
 for(const it of r.items){const row=el("div","row"+(it.done?" done":""));const c=el("button","chk",it.done?"✓":"");c.setAttribute("aria-label","Toggle done");
  c.onclick=async e=>{e.stopPropagation();await api("/api/items/"+it.id+"/done",{done:!it.done});load()};
  const t=el("div","t");t.append(el("b","",it.title),el("small","",it.path+(it.attachments?" · 📎 "+it.attachments:"")+(it.reminders?" · 🔔 "+it.reminders:"")));row.append(c,t);row.onclick=()=>openItem(it.id);l.append(row)}
 }catch(e){$("#err").textContent=e.message}}

/* ---------- attachments ---------- */
const size=n=>n>1e6?(n/1e6).toFixed(1)+" MB":Math.max(1,Math.round(n/1e3))+" KB";
async function upload(id,files){for(const f of files){const ext=(f.name.match(/\.(\w+)$/)||[])[1]||(f.type.split("/")[1]||"bin");
 await api("/api/items/"+id+"/attach?name="+encodeURIComponent(f.name||("file."+ext)),f,f.type||"application/octet-stream")}}
function zoom(src){const lb=$("#lb");lb.querySelector("img").src=src;lb.classList.add("on")}$("#lb").onclick=()=>$("#lb").classList.remove("on");

/* ---------- item sheet ---------- */
let current=null;
async function closeSheet(){if(current)await current.save();current=null;$("#sheet").classList.remove("on");load()}
async function openItem(id){const d=await api("/api/items/"+id);const s=$("#detail");s.replaceChildren();
 s.append(el("h1","",d.title),el("div","mute",d.path+" · "+d.kind));
 const refd=new Set([...(d.quote||"").matchAll(/attachment:(\d+)/g)].map(m=>+m[1]-1));
 if(d.quote){const q=el("div","quote");q.append(renderMD(d.quote,d.images));s.append(el("div","sec","Highlighted text"),q)}
 if(d.sourceURL&&/^https?:/.test(d.sourceURL)){const a=el("a","",d.sourceTitle||d.sourceURL);a.href=d.sourceURL;a.target="_blank";a.rel="noopener noreferrer";s.append(a)}
 for(const r of d.reminders||[])s.append(el("div","mute","🔔 "+r.text+" · "+new Date(r.due).toLocaleString()+(r.done?" (done)":"")));
 // attachments
 s.append(el("div","sec","Attachments"));const pics=el("div","pics");
 const remove=async n=>{if(!confirm("Remove "+n+"?"))return;await current.save();await api("/api/items/"+id+"/detach",{name:n});openItem(id)};
 d.images.forEach((n,k)=>{if(refd.size&&refd.has(k))return;const w=el("div","pic"),i=el("img");i.src=att(n);i.alt=n;i.loading="lazy";i.onclick=()=>zoom(att(n));
  const x=el("button","rm","✕");x.setAttribute("aria-label","Remove picture");x.onclick=()=>remove(n);w.append(i,x);pics.append(w)});
 if(pics.children.length)s.append(pics);
 for(const f of d.files){const row=el("div","file"),a=el("a","","📄 "+f.name);a.href=att(f.name);a.download=f.name;const x=el("button","","✕");x.setAttribute("aria-label","Remove file");x.onclick=()=>remove(f.name);row.append(a,el("span","mute",size(f.size)),x);s.append(row)}
 const st=el("span","mute"),add=el("button","pill","📎 Add photo or file"),inp=el("input");inp.type="file";inp.multiple=true;inp.hidden=true;
 add.onclick=()=>inp.click();
 inp.onchange=async()=>{try{await current.save();for(let k=0;k<inp.files.length;k++){st.textContent="Uploading "+(k+1)+" of "+inp.files.length+"…";await upload(id,[inp.files[k]])}openItem(id)}catch(e){st.textContent=e.message}};
 const ar=el("div");ar.style.cssText="display:flex;gap:10px;align-items:center;margin-top:6px";ar.append(add,st,inp);s.append(ar);
 // notes editor
 s.append(el("div","sec","Notes"));
 const tool=el("div","tool"),ed=el("div");ed.id="ed";ed.contentEditable="true";ed.dataset.ph="Notes";ed.spellcheck=true;ed.append(notesDOM(d.notes||""));
 const saved=el("div","saved");let dirty=false,t2;
 const save=async()=>{if(!dirty)return;dirty=false;clearTimeout(t2);try{await api("/api/items/"+id+"/notes",{notes:domNotes(ed)});saved.textContent="Saved"}catch(e){dirty=true;saved.textContent=e.message}};
 const touch=()=>{dirty=true;saved.textContent="";clearTimeout(t2);t2=setTimeout(save,900)};
 const exec=(c,v)=>{ed.focus();document.execCommand("styleWithCSS",false,true);document.execCommand(c,false,v);touch()};
 const btn=(label,title,fn,node)=>{const b=el("button","",label);b.title=title;b.setAttribute("aria-label",title);if(node)b.replaceChildren(node);
  b.addEventListener("pointerdown",e=>{e.preventDefault();fn()});b.addEventListener("click",e=>{if(e.detail===0)fn()});tool.append(b);return b};
 const sep=()=>tool.append(el("span","sep"));
 btn("B","Bold",()=>exec("bold")).style.fontWeight="700";btn("I","Italic",()=>exec("italic")).style.fontStyle="italic";
 btn("U","Underline",()=>exec("underline")).style.textDecoration="underline";btn("S","Strikethrough",()=>exec("strikeThrough")).style.textDecoration="line-through";
 btn("▮","Highlight",()=>{ed.focus();const v=document.queryCommandValue("hiliteColor")||document.queryCommandValue("backColor");const on=v&&v!=="transparent"&&!/rgba\(0, 0, 0, 0\)/.test(v);exec("hiliteColor",on?"transparent":"rgba(245,197,24,0.42)")}).style.color="#d9a400";
 sep();
 const setSize=px=>{ed.focus();document.execCommand("styleWithCSS",false,true);document.execCommand("fontSize",false,"7");
  ed.querySelectorAll('font[size="7"],span').forEach(f=>{if(f.tagName==="FONT"||f.style.fontSize==="xxx-large"){const sp=el("span");sp.style.fontSize="calc(var(--base) * "+px/BASE+")";while(f.firstChild)sp.append(f.firstChild);f.replaceWith(sp)}});touch()};
 [["S",11,"Small"],["M",BASE,"Normal"],["L",17,"Large"],["XL",22,"Title"]].forEach(([l,px,t])=>btn(l,t,()=>setSize(px)).style.fontSize=(10+px/3)+"px");
 sep();
 btn("","Default colour",()=>exec("foreColor",getComputedStyle(ed).color),(()=>{const d=el("span","dot");d.style.cssText="border:2px solid var(--mute)";return d})());
 COLORS.forEach(([n,h])=>btn("",n,()=>exec("foreColor","#"+h),(()=>{const d=el("span","dot");d.style.background="#"+h;return d})()));
 ed.addEventListener("input",touch);ed.addEventListener("blur",save);
 ed.addEventListener("beforeinput",e=>{if(e.inputType==="insertParagraph"){e.preventDefault();document.execCommand("insertLineBreak");touch()}});
 ed.addEventListener("paste",e=>{e.preventDefault();document.execCommand("insertText",false,e.clipboardData.getData("text/plain"))});
 s.append(tool,ed,saved);
 current={save};
 const b=el("div","btns"),today=el("button","",d.today?"Remove from Today":"Add to Today"),done=el("button","",d.done?"Reopen":"Mark done"),close=el("button","p","Close");
 today.onclick=async()=>{await current.save();await api("/api/items/"+id+"/today",{today:!d.today});current=null;$("#sheet").classList.remove("on");load()};
 done.onclick=async()=>{await current.save();await api("/api/items/"+id+"/done",{done:!d.done});current=null;$("#sheet").classList.remove("on");load()};
 close.onclick=closeSheet;b.append(today,done,close);s.append(b);$("#sheet").classList.add("on")}

/* ---------- quick add (with files) ---------- */
$("#clip").onclick=()=>$("#pick").click();
$("#pick").onchange=e=>{pending=[...e.target.files];$("#clip").textContent=pending.length?"📎 "+pending.length:"📎"};
$("#add").addEventListener("keydown",async e=>{if(e.key!=="Enter")return;let t=e.target.value.trim();if(!t&&pending.length)t=pending[0].name.replace(/\.[^.]+$/,"");if(!t)return;
 try{const it=await api("/api/items",{title:t,today:view==="today"});if(pending.length)await upload(it.id,pending);pending=[];$("#pick").value="";$("#clip").textContent="📎";e.target.value="";load()}catch(x){$("#err").textContent=x.message}});
$("#q").addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(load,250)});
document.addEventListener("visibilitychange",()=>{if(!document.hidden&&!current)load()});
tabs();load();
</script></body></html>
"""#
}
