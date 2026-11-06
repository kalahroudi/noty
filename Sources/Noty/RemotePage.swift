// SPDX-License-Identifier: Apache-2.0

/// The single page served to your phone or another computer over Tailscale. Plain HTML and JS, no libraries, follows the system light/dark theme.
enum RemotePage {
    static let html = #"""
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes"><meta name="apple-mobile-web-app-title" content="Noty">
<title>Noty</title>
<style>
:root{--bg:#f6f5f1;--card:#fff;--ink:#1c1c1e;--mute:#6b6b70;--line:#e4e2db;--accent:#f5c518;--accent-ink:#1c1c1e;--danger:#c0392b}
@media(prefers-color-scheme:dark){:root{--bg:#161618;--card:#222226;--ink:#f2f2f4;--mute:#9b9ba3;--line:#34343a;--accent:#f5c518}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.4 -apple-system,system-ui,sans-serif;padding:env(safe-area-inset-top) 16px env(safe-area-inset-bottom)}
main{max-width:640px;margin:0 auto;padding:14px 0 40px}
h1{font-size:20px;margin:6px 0 12px}
input,textarea{width:100%;font:inherit;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:11px 12px}
.tabs{display:flex;gap:6px;margin:12px 0;overflow-x:auto}
.tabs button{flex:none;font:inherit;font-size:14px;padding:7px 13px;border-radius:999px;border:1px solid var(--line);background:var(--card);color:var(--ink)}
.tabs button.on{background:var(--accent);color:var(--accent-ink);border-color:var(--accent);font-weight:600}
.row{display:flex;align-items:center;gap:12px;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 12px;margin-bottom:8px}
.row .t{flex:1;min-width:0}.row .t b{font-weight:500;display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.row small,.mute{color:var(--mute);font-size:12.5px}.done b{text-decoration:line-through;color:var(--mute)}
.chk{width:26px;height:26px;border-radius:7px;border:2px solid var(--mute);background:none;flex:none;padding:0;color:var(--accent-ink);font-size:15px}
.done .chk{background:var(--accent);border-color:var(--accent)}
.empty{text-align:center;color:var(--mute);padding:40px 0}
#sheet{position:fixed;inset:0;background:rgba(0,0,0,.4);display:none;align-items:flex-end}
#sheet.on{display:flex}#sheet>div{background:var(--bg);width:100%;max-height:88vh;overflow:auto;border-radius:18px 18px 0 0;padding:18px 16px 28px;max-width:640px;margin:0 auto}
blockquote{margin:10px 0;padding:8px 12px;border-left:3px solid var(--accent);color:var(--mute);white-space:pre-wrap}
.btns{display:flex;gap:8px;margin-top:12px}.btns button{flex:1;font:inherit;padding:11px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--ink)}
.btns .p{background:var(--accent);color:var(--accent-ink);border-color:var(--accent);font-weight:600}
#err{color:var(--danger);font-size:13px;min-height:18px}
</style></head><body><main>
<h1>Noty</h1>
<input id="add" placeholder="Quick add to Inbox…" enterkeyhint="send" autocomplete="off">
<div class="tabs" id="tabs"></div>
<input id="q" type="search" placeholder="Search" autocomplete="off">
<div id="err"></div><div id="list" style="margin-top:10px"></div>
</main>
<div id="sheet"><div id="detail"></div></div>
<script>
const $=s=>document.querySelector(s);let view="today",timer;
async function api(p,body){const o=body===undefined?{}:{method:"POST",headers:{"X-Noty":"1","Content-Type":"application/json"},body:JSON.stringify(body)};
 const r=await fetch(p,o);const j=await r.json();if(!r.ok)throw new Error(j.error||r.status);return j}
function el(t,c,x){const e=document.createElement(t);if(c)e.className=c;if(x!==undefined)e.textContent=x;return e}
const views=[["today","Today"],["inbox","Inbox"],["open","Open"],["done","Done"]];
function tabs(){const t=$("#tabs");t.replaceChildren();for(const[v,n]of views){const b=el("button",v===view?"on":"",n);b.onclick=()=>{view=v;$("#q").value="";tabs();load()};t.append(b)}}
async function load(){try{$("#err").textContent="";const q=$("#q").value.trim();
 const r=await api("/api/items?"+(q?"q="+encodeURIComponent(q):"view="+view));const l=$("#list");l.replaceChildren();
 if(!r.items.length)l.append(el("div","empty",q?"Nothing found.":"All clear."));
 for(const it of r.items){const row=el("div","row"+(it.done?" done":""));const c=el("button","chk",it.done?"✓":"");c.setAttribute("aria-label","Toggle done");
  c.onclick=async e=>{e.stopPropagation();await api("/api/items/"+it.id+"/done",{done:!it.done});load()};
  const t=el("div","t");t.append(el("b","",it.title),el("small","",it.path+(it.reminders?" · 🔔 "+it.reminders:"")));row.append(c,t);row.onclick=()=>open(it.id);l.append(row)}
 }catch(e){$("#err").textContent=e.message}}
async function open(id){const d=await api("/api/items/"+id);const s=$("#detail");s.replaceChildren();s.append(el("h1","",d.title),el("div","mute",d.path+" · "+d.kind));
 if(d.quote)s.append(el("blockquote","",d.quote));
 if(d.sourceURL){const a=el("a","",d.sourceTitle||d.sourceURL);a.href=d.sourceURL;a.rel="noopener noreferrer";s.append(a)}
 for(const r of d.reminders||[])s.append(el("div","mute","🔔 "+r.text+" · "+new Date(r.due).toLocaleString()+(r.done?" (done)":"")));
 const n=el("textarea");n.rows=6;n.value=d.notes;n.placeholder="Notes";n.style.marginTop="12px";s.append(n);
 const b=el("div","btns"),save=el("button","p","Save notes"),today=el("button","",d.today?"Remove from Today":"Add to Today"),done=el("button","",d.done?"Reopen":"Mark done"),close=el("button","","Close");
 save.onclick=async()=>{await api("/api/items/"+id+"/notes",{notes:n.value});save.textContent="Saved"};
 today.onclick=async()=>{await api("/api/items/"+id+"/today",{today:!d.today});$("#sheet").classList.remove("on");load()};
 done.onclick=async()=>{await api("/api/items/"+id+"/done",{done:!d.done});$("#sheet").classList.remove("on");load()};
 close.onclick=()=>{$("#sheet").classList.remove("on");load()};b.append(save,today,done,close);s.append(b);$("#sheet").classList.add("on")}
$("#add").addEventListener("keydown",async e=>{if(e.key!=="Enter")return;const t=e.target.value.trim();if(!t)return;
 try{await api("/api/items",{title:t,today:view==="today"});e.target.value="";load()}catch(x){$("#err").textContent=x.message}});
$("#q").addEventListener("input",()=>{clearTimeout(timer);timer=setTimeout(load,250)});
document.addEventListener("visibilitychange",()=>{if(!document.hidden)load()});
tabs();load();
</script></body></html>
"""#
}
