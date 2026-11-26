"""Live copilot page for the current meeting: the latest suggested answer in large type, the question that was
just heard (before its answer arrives), earlier answers and the live transcript.

Serves http://127.0.0.1:8765 (this computer only). The page polls /api/state, which reads sessions/LATEST,
transcript.txt, answers.md, questions.log and session.json in $ONCUE_HOME. Standard library only;
the page has no external files, fonts or scripts.
Usage: python dashboard.py [--port 8765]   (or ONCUE_PORT)
"""
import argparse
import datetime as dt
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOME = Path(os.environ.get("ONCUE_HOME") or Path.home() / "oncue")
PENDING_FOR = 120  # seconds a heard question shows as "answer coming" before it counts as skipped

PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8"><title>oncue</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<style>
:root{--bg:#0b0d12;--panel:#12151c;--panel2:#171b24;--line:#232836;--ink:#eceef3;--ink2:#b9bfcc;--muted:#7d8597;
--accent:#8ea2ff;--accent2:#b18cff;--me:#6fdcae;--them:#f2c46b;--ok:#3fd68a;--warn:#f2c46b;--r:16px}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--ink)}
body{font:15px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  -webkit-font-smoothing:antialiased;min-height:100vh;
  background:radial-gradient(1200px 500px at 10% -10%,#1a2040 0%,transparent 60%),var(--bg)}
button{font:inherit;color:inherit;cursor:pointer}
.wrap{max-width:1180px;margin:0 auto;padding:16px;display:grid;gap:14px}
header{display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between}
.brand{display:flex;align-items:center;gap:10px;font-weight:650;letter-spacing:.01em}
.logo{width:28px;height:28px;border-radius:9px;background:linear-gradient(135deg,var(--accent),var(--accent2));
  display:grid;place-items:center;color:#0b0d12;font-size:15px;font-weight:800}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.pill{display:inline-flex;align-items:center;gap:7px;padding:5px 11px;border-radius:999px;background:var(--panel);
  border:1px solid var(--line);font-size:12.5px;color:var(--ink2);white-space:nowrap}
.pill b{color:var(--ink);font-weight:600}
.dot{width:8px;height:8px;border-radius:50%;background:#5b6272}
.live .dot{background:var(--ok);animation:pulse 1.8s infinite}
@keyframes pulse{0%{box-shadow:0 0 0 0 #3fd68a88}70%{box-shadow:0 0 0 8px #3fd68a00}100%{box-shadow:0 0 0 0 #3fd68a00}}
.btn{padding:5px 11px;border-radius:999px;background:var(--panel);border:1px solid var(--line);font-size:12.5px;color:var(--ink2)}
.btn:hover{border-color:#3a4256;color:var(--ink)}.btn[aria-pressed="true"]{color:var(--ink);border-color:var(--accent)}
.btn:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
kbd{font:11px ui-monospace,monospace;padding:1px 5px;border-radius:5px;border:1px solid var(--line);color:var(--muted)}
.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--r);padding:18px}
.label{font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-bottom:10px;
  display:flex;justify-content:space-between;align-items:center;gap:8px}
.now{position:relative;background:linear-gradient(180deg,var(--panel2),var(--panel));padding:22px 24px;transition:border-color .4s,box-shadow .4s}
.now.flash{border-color:var(--accent);box-shadow:0 0 0 4px #8ea2ff2e,0 10px 40px #8ea2ff22;animation:pop .5s ease}
@keyframes pop{0%{transform:scale(.99)}60%{transform:scale(1.006)}100%{transform:scale(1)}}
.qline{color:var(--ink2);font-size:15px;border-left:3px solid var(--them);padding:2px 0 2px 12px;margin-bottom:14px}
.qline .when{color:var(--muted);font-size:12.5px;margin-right:6px}
.answer{font-size:clamp(22px,2.6vw,30px);line-height:1.38;font-weight:620;letter-spacing:-.005em;white-space:pre-wrap}
.answer.empty{color:var(--muted);font-weight:500;font-size:20px}
.copy{padding:6px 12px;border-radius:10px;background:#ffffff0d;border:1px solid var(--line);font-size:12.5px;color:var(--ink2)}
.copy:hover{background:#ffffff16;color:var(--ink)}.copy.done{color:var(--ok);border-color:#3fd68a66}
.pending{display:none;margin-bottom:14px;padding:12px 14px;border-radius:12px;background:#f2c46b12;border:1px solid #f2c46b40}
.pending.show{display:block}.pending .h{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--warn);font-weight:650}
.pending .t{margin-top:4px;color:var(--ink);font-size:16px}
.spin{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--warn);margin-right:8px;vertical-align:1px;animation:blink 1s ease-in-out infinite}
@keyframes blink{50%{opacity:.25}}
.now.waiting .answer,.now.waiting .qline{opacity:.45}
.grid{display:grid;gap:14px;grid-template-columns:1fr}
@media(min-width:900px){.grid{grid-template-columns:1fr 1.25fr}}
.qa{padding:12px 0;border-top:1px solid var(--line);display:grid;grid-template-columns:1fr auto;gap:4px 10px}
.qa:first-child{border-top:0;padding-top:2px}.qa .q{color:var(--muted);font-size:13px;grid-column:1}
.qa .s{grid-column:1;color:var(--ink)}.qa .copy{grid-column:2;grid-row:1/3;align-self:center;padding:4px 9px;font-size:12px}
.list{max-height:62vh;overflow:auto}
#tx{max-height:62vh;overflow:auto;scroll-behavior:auto;padding-right:4px}
.ln{display:grid;grid-template-columns:66px 52px 1fr;gap:8px;padding:5px 0;border-top:1px solid #ffffff07;font-size:14px}
.ln .t{color:var(--muted);font:12px/1.9 ui-monospace,SFMono-Regular,Menlo,monospace}
.who{font-size:11px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;border-radius:6px;padding:2px 0;text-align:center;height:fit-content;margin-top:2px}
.who.ME{color:var(--me);background:#6fdcae14}.who.THEM{color:var(--them);background:#f2c46b14}
.ln.hit .x{color:#fff;text-decoration:underline;text-decoration-color:#f2c46b88;text-underline-offset:3px}
.muted{color:var(--muted)}
.jump{display:none;position:sticky;bottom:0;margin:8px auto 0;padding:6px 12px;border-radius:999px;background:var(--accent);color:#0b0d12;border:0;font-weight:650;font-size:12.5px}
.jump.show{display:block}
.foot{color:var(--muted);font-size:12px;text-align:center;padding:4px 0 10px}
/* Compact: the answer only, for a narrow window beside the call. */
body.compact .wrap{max-width:none;padding:10px;gap:10px}
body.compact .grid,body.compact .foot,body.compact .hide-compact{display:none}
body.compact .now{padding:16px 18px}
body.compact .answer{font-size:clamp(20px,5.2vw,28px)}
@media(max-width:560px){.ln{grid-template-columns:58px 46px 1fr}.now{padding:18px}.wrap{padding:12px}}
@media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}
</style></head><body>
<div class="wrap">
<header>
  <div class="brand"><div class="logo">✦</div><span>oncue</span></div>
  <div class="bar">
    <span class="pill" id="status"><span class="dot"></span><b id="stText">Connecting</b><span id="sess" class="hide-compact"></span></span>
    <span class="pill hide-compact" title="Speech model">Model <b id="model">–</b></span>
    <span class="pill" title="Questions detected this meeting">Questions <b id="qcount">0</b></span>
    <button class="btn" id="soundBtn" aria-pressed="false" title="Soft sound when a new answer arrives (S)">Sound off</button>
    <button class="btn" id="compactBtn" aria-pressed="false" title="Answer only, for a small window (C)">Compact <kbd>C</kbd></button>
  </div>
</header>

<section class="card now" id="now" aria-live="polite">
  <div class="pending" id="pending"><div class="h"><span class="spin"></span>Question heard… answer coming</div><div class="t" id="pendingQ"></div></div>
  <div class="label"><span>Suggested answer</span><button class="copy" id="copyMain" hidden>Copy</button></div>
  <div class="qline" id="nq" hidden></div>
  <div class="answer empty" id="na">Waiting for a question…</div>
</section>

<div class="grid">
  <section class="card"><div class="label"><span>Earlier answers</span><span id="acount" class="muted"></span></div>
    <div class="list" id="qa"><span class="muted">None yet</span></div></section>
  <section class="card"><div class="label"><span>Live transcript</span><span class="muted" id="txinfo"></span></div>
    <div id="tx"><span class="muted">Nothing yet</span></div>
    <button class="jump" id="jump">Paused · jump to live ↓</button></section>
</div>
<div class="foot">Runs on this computer only · <kbd>C</kbd> compact · <kbd>S</kbd> sound · <kbd>Y</kbd> copy answer</div>
</div>
<script>
const $=id=>document.getElementById(id);
const store={get(k){try{return localStorage.getItem(k)}catch(e){return null}},set(k,v){try{localStorage.setItem(k,v)}catch(e){}}};
let lastAnswerKey=null,lastTxKey='',follow=true,soundOn=store.get('ma.sound')==='1',ctx=null,firstLoad=true;

function setCompact(on){document.body.classList.toggle('compact',on);$('compactBtn').setAttribute('aria-pressed',on);store.set('ma.compact',on?'1':'0');}
function setSound(on){soundOn=on;$('soundBtn').setAttribute('aria-pressed',on);$('soundBtn').textContent=on?'Sound on':'Sound off';store.set('ma.sound',on?'1':'0');if(on){chime(true)}}
function chime(quiet){try{ctx=ctx||new (window.AudioContext||window.webkitAudioContext)();if(ctx.state==='suspended')ctx.resume();
  const t=ctx.currentTime;[[660,0],[880,.13]].forEach(([f,d])=>{const o=ctx.createOscillator(),g=ctx.createGain();o.type='sine';o.frequency.value=f;
  g.gain.setValueAtTime(0,t+d);g.gain.linearRampToValueAtTime(quiet?.03:.08,t+d+.02);g.gain.exponentialRampToValueAtTime(.0001,t+d+.5);
  o.connect(g).connect(ctx.destination);o.start(t+d);o.stop(t+d+.55)})}catch(e){}}
async function copy(text,btn){try{await navigator.clipboard.writeText(text)}catch(e){const a=document.createElement('textarea');a.value=text;document.body.appendChild(a);a.select();try{document.execCommand('copy')}catch(_){}a.remove()}
  if(btn){const o=btn.textContent;btn.textContent='Copied';btn.classList.add('done');setTimeout(()=>{btn.textContent=o;btn.classList.remove('done')},1400)}}

setCompact(store.get('ma.compact')==='1');
$('soundBtn').setAttribute('aria-pressed',soundOn);$('soundBtn').textContent=soundOn?'Sound on':'Sound off';
$('compactBtn').onclick=()=>setCompact(!document.body.classList.contains('compact'));
$('soundBtn').onclick=()=>setSound(!soundOn);
$('copyMain').onclick=()=>copy($('na').textContent,$('copyMain'));
document.addEventListener('pointerdown',()=>{if(ctx&&ctx.state==='suspended')ctx.resume()});
document.addEventListener('keydown',e=>{if(e.ctrlKey||e.metaKey||e.altKey||/INPUT|TEXTAREA/.test(e.target.tagName))return;const k=e.key.toLowerCase();
  if(k==='c'){setCompact(!document.body.classList.contains('compact'))}else if(k==='s'){setSound(!soundOn)}else if(k==='y'&&!$('copyMain').hidden){copy($('na').textContent,$('copyMain'))}});
const tx=$('tx');
tx.addEventListener('scroll',()=>{follow=tx.scrollHeight-tx.scrollTop-tx.clientHeight<30;$('jump').classList.toggle('show',!follow)});
$('jump').onclick=()=>{follow=true;tx.scrollTop=tx.scrollHeight;$('jump').classList.remove('show')};

function el(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e}
function render(s){
  const live=s.live;$('status').classList.toggle('live',live);
  $('stText').textContent=live?'Listening':(s.session?'Stopped':'Not started');
  $('sess').textContent=s.session?' · '+s.session:'';$('model').textContent=s.model||'–';$('qcount').textContent=s.questions_count;
  // Pending question
  const p=s.pending;$('pending').classList.toggle('show',!!p);$('now').classList.toggle('waiting',!!p&&s.answers.length>0);if(p)$('pendingQ').textContent=p.t+' · '+p.text;
  // Latest answer
  const a=s.answers;
  if(a.length){const n=a[a.length-1],key=n.time+'|'+n.q+'|'+n.say;
    $('nq').hidden=false;$('nq').innerHTML='';$('nq').append(el('span','when',n.time),document.createTextNode(n.q));
    $('na').textContent=n.say;$('na').classList.remove('empty');$('copyMain').hidden=false;
    if(lastAnswerKey!==null&&key!==lastAnswerKey){const box=$('now');box.classList.remove('flash');void box.offsetWidth;box.classList.add('flash');
      setTimeout(()=>box.classList.remove('flash'),5000);if(soundOn)chime(false);
      if(document.hidden){document.title='● New answer · oncue';}}
    lastAnswerKey=key;
  }else{lastAnswerKey=lastAnswerKey??'';$('nq').hidden=true;$('na').textContent=live?'Waiting for a question…':'No answers yet';$('na').classList.add('empty');$('copyMain').hidden=true}
  // Earlier answers
  const older=a.slice(0,-1).reverse();$('acount').textContent=older.length?older.length:'';
  const qa=$('qa');qa.innerHTML='';
  if(!older.length)qa.append(el('span','muted','None yet'));
  older.forEach(x=>{const d=el('div','qa');d.append(el('div','q',x.time+' · '+x.q),el('div','s',x.say));const b=el('button','copy','Copy');b.onclick=()=>copy(x.say,b);d.append(b);qa.append(d)});
  // Transcript (re-drawn only when it changes, so scrolling and selecting text are not disturbed)
  const hits=new Set(s.questions.map(q=>q.t+'|'+q.text));
  const txKey=s.lines.length+'|'+(s.lines.length?s.lines[s.lines.length-1].t+s.lines[s.lines.length-1].text:'');
  if(txKey!==lastTxKey){lastTxKey=txKey;tx.innerHTML='';
    if(!s.lines.length)tx.append(el('span','muted','Nothing yet'));
    s.lines.forEach(l=>{const d=el('div','ln'+(l.who==='THEM'&&hits.has(l.t+'|'+l.text)?' hit':''));
      d.append(el('span','t',l.t),el('span','who '+l.who,l.who==='ME'?'Me':'Them'),el('span','x',l.text));tx.append(d)});
    if(follow)tx.scrollTop=tx.scrollHeight;}
  $('txinfo').textContent=s.lines.length?s.lines.length+' lines':'';
}
document.addEventListener('visibilitychange',()=>{if(!document.hidden)document.title='oncue'});
async function tick(){try{const r=await fetch('/api/state',{cache:'no-store'});render(await r.json())}
  catch(e){$('status').classList.remove('live');$('stText').textContent='Dashboard offline'}}
tick();setInterval(tick,1500);
</script></body></html>"""

LINE = re.compile(r"^\[(\d\d:\d\d:\d\d)\] (ME|THEM): (.*)$")
QA = re.compile(r"- \*\*Q \(([^)]*)\):\*\* (.*?)\n\s+\*\*Say:\*\* (.*?)(?:\n\n|\Z)", re.S)


def pid_alive(pid_file):
    """True if pid_file holds the id of a running process (listen.py writes run/listen.pid)."""
    try:
        os.kill(int(pid_file.read_text().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def secs(hms):
    h, m, s = (int(x) for x in hms.split(":"))
    return h * 3600 + m * 60 + s


def read_lines(path, limit):
    out = []
    if path.exists():
        for raw in path.read_text(errors="ignore").splitlines()[-limit:]:
            m = LINE.match(raw)
            if m:
                out.append({"t": m[1], "who": m[2], "text": m[3]})
    return out


def state():
    empty = {"live": False, "session": "", "model": "", "lines": [], "answers": [], "questions": [],
             "questions_count": 0, "pending": None}
    try:
        f = Path((HOME / "sessions" / "LATEST").read_text().strip())
    except OSError:
        return empty
    folder = f.parent
    lines = read_lines(f, 300)
    ans_file = folder / "answers.md"
    answers = [{"time": t, "q": q.strip(), "say": s.strip()} for t, q, s in QA.findall(ans_file.read_text())] if ans_file.exists() else []
    questions = read_lines(folder / "questions.log", 10_000)
    try:
        model = json.loads((folder / "session.json").read_text()).get("model", "")
    except (OSError, ValueError):
        model = ""
    # The newest heard question counts as pending until an answer is written after it, or it gets old
    # (Claude skips small talk without answering).
    pending = None
    if questions:
        q = questions[-1]
        now = secs(dt.datetime.now().strftime("%H:%M:%S"))
        age = (now - secs(q["t"])) % 86400
        answered = answers and (secs(answers[-1]["time"]) - secs(q["t"])) % 86400 < 43200
        if age <= PENDING_FOR and not answered:
            pending = q
    live = pid_alive(HOME / "run" / "listen.pid")
    return {"live": live, "session": folder.name, "model": model, "lines": lines, "answers": answers,
            "questions": questions[-50:], "questions_count": len(questions), "pending": pending}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/state"):
            body, ctype, code = json.dumps(state()).encode(), "application/json", 200
        elif self.path in ("/", "/index.html") or self.path.startswith("/?"):
            body, ctype, code = PAGE.encode(), "text/html; charset=utf-8", 200
        else:
            body, ctype, code = b"not found", "text/plain", 404
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("ONCUE_PORT") or 8765))
    port = ap.parse_args().port
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    pid_file = HOME / "run" / "dashboard.pid"
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    pid_file.write_text(str(os.getpid()))
    print(f"dashboard: http://127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
