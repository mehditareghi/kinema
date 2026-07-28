import Foundation

/// Branded HTML for the local Wi‑Fi Sharing browser page (matches in-app library feel).
enum WiFiSharingWebUI {
    /// Wine / cinema rose — same as `KinemaTheme.accent`.
    static let accent = "#C45B6A"
    static let accentSoft = "rgba(196, 91, 106, 0.14)"

    static func indexPage() -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <meta name="theme-color" content="#F2F2F7"/>
          <title>Kinema · Wi‑Fi Sharing</title>
          <link rel="icon" href="/logo.png"/>
          <style>
            :root {
              --accent: \(accent);
              --accent-soft: \(accentSoft);
              --bg: #F2F2F7;
              --card: #FFFFFF;
              --text: #1C1C1E;
              --secondary: #8E8E93;
              --separator: rgba(60,60,67,0.12);
              --radius: 12px;
              --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            }
            * { box-sizing: border-box; }
            html, body {
              margin: 0; min-height: 100%;
              background: var(--bg);
              color: var(--text);
              font-family: var(--font);
              -webkit-font-smoothing: antialiased;
            }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            .wrap { width: min(920px, calc(100% - 28px)); margin: 0 auto; padding: 22px 0 48px; }
            header.top {
              display: flex; align-items: center; justify-content: space-between;
              gap: 16px; margin-bottom: 18px; flex-wrap: wrap;
            }
            .brand { display: flex; align-items: center; gap: 12px; }
            .brand img {
              width: 44px; height: 44px; border-radius: 10px;
              box-shadow: 0 4px 14px rgba(196,91,106,0.28);
            }
            .brand h1 { margin: 0; font-size: 1.35rem; font-weight: 700; letter-spacing: -0.02em; }
            .brand p { margin: 1px 0 0; color: var(--secondary); font-size: 0.86rem; }
            .live {
              display: inline-flex; align-items: center; gap: 8px;
              padding: 7px 12px; border-radius: 999px;
              background: var(--accent-soft); color: var(--accent);
              font-size: 0.78rem; font-weight: 650;
            }
            .live i {
              width: 7px; height: 7px; border-radius: 50%; background: #34C759;
              display: inline-block;
            }
            .panel {
              background: var(--card);
              border-radius: 16px;
              padding: 16px;
              margin-bottom: 14px;
              border: 1px solid var(--separator);
            }
            .panel h2 {
              margin: 0; font-size: 0.72rem; font-weight: 700;
              letter-spacing: 0.06em; text-transform: uppercase; color: var(--secondary);
            }
            .panel .hint { margin: 6px 0 14px; color: var(--secondary); font-size: 0.9rem; line-height: 1.4; }
            .drop {
              border: 1.5px dashed rgba(196,91,106,0.45);
              border-radius: 14px; padding: 28px 16px; text-align: center;
              background: rgba(196,91,106,0.04); cursor: pointer;
              transition: border-color .15s, background .15s;
            }
            .drop.over { border-color: var(--accent); background: rgba(196,91,106,0.1); }
            .drop strong { display: block; margin-bottom: 4px; }
            .drop span { color: var(--secondary); font-size: 0.88rem; }
            .drop input { display: none; }
            .row-actions { display: flex; gap: 8px; justify-content: center; flex-wrap: wrap; margin-top: 14px; }
            button, .btn {
              appearance: none; border: 0; cursor: pointer; font: inherit; font-weight: 650;
              border-radius: 11px; padding: 10px 14px;
            }
            .btn-primary { background: var(--accent); color: #fff; }
            .btn-secondary {
              background: rgba(120,120,128,0.12); color: var(--text);
            }
            .btn-small {
              padding: 7px 10px; font-size: 0.8rem; border-radius: 9px;
              background: rgba(120,120,128,0.12); color: var(--text);
            }
            .btn-small.accent { background: var(--accent-soft); color: var(--accent); }
            .queue { margin-top: 12px; display: grid; gap: 8px; }
            .queue:empty { display: none; }
            .job {
              display: grid; grid-template-columns: 1fr auto; gap: 4px 10px;
              padding: 10px 12px; border-radius: 10px; background: var(--bg);
            }
            .job-name { font-size: 0.88rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
            .job-meta { color: var(--secondary); font-size: 0.75rem; }
            .bar { grid-column: 1 / -1; height: 5px; border-radius: 99px; background: rgba(0,0,0,0.08); overflow: hidden; }
            .bar > i { display: block; height: 100%; width: 0; background: var(--accent); }
            .crumbs {
              display: flex; align-items: center; gap: 6px; flex-wrap: wrap;
              margin: 0 0 12px; font-size: 0.88rem;
            }
            .crumbs button {
              background: none; color: var(--accent); padding: 0; font-weight: 600;
            }
            .crumbs .sep { color: var(--secondary); }
            .crumbs .here { color: var(--text); font-weight: 650; }
            .lib-head {
              display: flex; align-items: flex-start; justify-content: space-between;
              gap: 12px; margin-bottom: 12px;
            }
            .lib-head .left { min-width: 0; flex: 1; }
            .lib-head .right { display: flex; align-items: center; gap: 8px; flex: none; }
            .count { color: var(--secondary); font-size: 0.82rem; white-space: nowrap; }
            .list { display: grid; gap: 8px; }
            .tile {
              display: flex; align-items: center; gap: 12px;
              padding: 10px 12px; border-radius: var(--radius);
              background: var(--bg); border: 1px solid transparent;
              transition: border-color .15s, background .15s;
            }
            .tile:hover { border-color: rgba(196,91,106,0.35); background: #fff; }
            .tile.folder { cursor: pointer; }
            .icon-box {
              width: 44px; height: 44px; border-radius: 10px; flex: none;
              display: grid; place-items: center; font-size: 1.1rem;
              background: var(--accent-soft); color: var(--accent); font-weight: 700;
            }
            .icon-box.spot {
              background: rgba(88,86,214,0.12); color: #5856D6;
            }
            .thumb-box {
              width: 72px; height: 40px; border-radius: 8px; flex: none;
              overflow: hidden; background: #1C1C1E; position: relative;
            }
            .thumb-box img { width: 100%; height: 100%; object-fit: cover; display: block; }
            .thumb-box .ph {
              position: absolute; inset: 0; display: grid; place-items: center;
              color: rgba(255,255,255,0.55); font-size: 0.85rem;
            }
            .meta { min-width: 0; flex: 1; }
            .meta .name {
              font-size: 0.92rem; font-weight: 600; line-height: 1.25;
              overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
            }
            .meta .sub { color: var(--secondary); font-size: 0.78rem; margin-top: 2px; }
            .tile-actions { display: flex; gap: 6px; flex: none; }
            .empty {
              text-align: center; padding: 36px 12px; color: var(--secondary);
              border: 1px dashed var(--separator); border-radius: 12px;
            }
            .empty strong { display: block; color: var(--text); margin-bottom: 4px; }
            footer {
              margin-top: 22px; text-align: center; color: var(--secondary); font-size: 0.78rem;
            }
            footer .greek { color: var(--accent); letter-spacing: 0.14em; margin-bottom: 2px; }
            .toast {
              position: fixed; left: 50%; bottom: 20px; transform: translateX(-50%) translateY(140%);
              background: #1C1C1E; color: #fff; padding: 11px 14px; border-radius: 12px;
              font-size: 0.88rem; z-index: 20; max-width: min(400px, calc(100% - 24px));
              transition: transform .2s ease;
            }
            .toast.show { transform: translateX(-50%) translateY(0); }
          </style>
        </head>
        <body>
          <div class="wrap">
            <header class="top">
              <div class="brand">
                <img src="/logo.png" width="44" height="44" alt="Kinema"/>
                <div>
                  <h1>Kinema</h1>
                  <p>Wi‑Fi Sharing · your cinema</p>
                </div>
              </div>
              <div class="live"><i></i> Connected</div>
            </header>

            <section class="panel">
              <h2>Upload</h2>
              <p class="hint">Drop files or whole folders here. They appear in your built-in Kinema library on this device.</p>
              <div class="drop" id="drop">
                <strong>Drop media or folders</strong>
                <span>Videos, audio, or a folder of titles</span>
                <div class="row-actions">
                  <button type="button" class="btn-primary" id="pickFiles">Choose files</button>
                  <button type="button" class="btn-secondary" id="pickFolder">Choose folder</button>
                </div>
                <input id="fileInput" type="file" multiple accept="video/*,audio/*,.mkv,.avi,.mov,.mp4,.m4v,.webm,.mp3,.flac,.aac,.m4a,.wav,.opus"/>
                <input id="folderInput" type="file" webkitdirectory directory multiple/>
              </div>
              <div class="queue" id="queue"></div>
            </section>

            <section class="panel">
              <div class="lib-head">
                <div class="left">
                  <h2>Library</h2>
                  <div class="crumbs" id="crumbs"></div>
                </div>
                <div class="right">
                  <span class="count" id="count"></span>
                  <button type="button" class="btn-small" id="refreshBtn">Refresh</button>
                </div>
              </div>
              <div id="library"></div>
            </section>

            <footer>
              <div class="greek">κίνημα</div>
              <div>motion · cinema · Kinema</div>
            </footer>
          </div>
          <div class="toast" id="toast"></div>
          <script>
            let currentPath = '';
            let spotlight = null; // { id, title, files: [...] } when drilled into a spotlight
            const drop = document.getElementById('drop');
            const fileInput = document.getElementById('fileInput');
            const folderInput = document.getElementById('folderInput');
            const queue = document.getElementById('queue');
            const library = document.getElementById('library');
            const crumbs = document.getElementById('crumbs');
            const countEl = document.getElementById('count');
            const toast = document.getElementById('toast');

            function showToast(msg) {
              toast.textContent = msg;
              toast.classList.add('show');
              clearTimeout(showToast._t);
              showToast._t = setTimeout(() => toast.classList.remove('show'), 2600);
            }
            function formatBytes(n) {
              if (n == null || n < 0) return '';
              const u = ['B','KB','MB','GB']; let i = 0; let v = n;
              while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
              return (i === 0 ? v : v.toFixed(v >= 10 ? 0 : 1)) + ' ' + u[i];
            }
            function enc(path) {
              return path.split('/').filter(Boolean).map(encodeURIComponent).join('/');
            }
            function joinPath(base, name) {
              return base ? (base + '/' + name) : name;
            }

            function renderCrumbs() {
              const parts = currentPath ? currentPath.split('/') : [];
              let html = '<button type="button" data-path="">Kinema</button>';
              let acc = '';
              parts.forEach((p, idx) => {
                acc = acc ? acc + '/' + p : p;
                html += '<span class="sep">/</span>';
                if (idx === parts.length - 1 && !spotlight) {
                  html += '<span class="here">' + escapeHtml(p) + '</span>';
                } else {
                  html += '<button type="button" data-path="' + escapeAttr(acc) + '">' + escapeHtml(p) + '</button>';
                }
              });
              if (spotlight) {
                html += '<span class="sep">/</span><span class="here">' + escapeHtml(spotlight.title) + '</span>';
              }
              crumbs.innerHTML = html;
              crumbs.querySelectorAll('button[data-path]').forEach(btn => {
                btn.addEventListener('click', () => {
                  spotlight = null;
                  currentPath = btn.getAttribute('data-path') || '';
                  refreshLibrary();
                });
              });
            }

            function escapeHtml(s) {
              return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
            }
            function escapeAttr(s) { return escapeHtml(s).replace(/'/g,'&#39;'); }

            function renderLibrary(data) {
              renderCrumbs();
              if (spotlight) {
                const files = spotlight.files || [];
                countEl.textContent = files.length + (files.length === 1 ? ' title' : ' titles');
                if (!files.length) {
                  library.innerHTML = '<div class="empty"><strong>Nothing in this spotlight</strong></div>';
                  return;
                }
                library.innerHTML = '<div class="list">' + files.map(fileTile).join('') + '</div>';
                return;
              }

              const folders = data.folders || [];
              const spotlights = data.spotlights || [];
              const files = data.files || [];
              const total = folders.length + spotlights.length + files.length;
              countEl.textContent = total === 1 ? '1 item' : total + ' items';

              if (!total) {
                library.innerHTML = '<div class="empty"><strong>Nothing here yet</strong>Upload media above, or open another folder.</div>';
                return;
              }

              const rows = [];
              folders.forEach(f => {
                rows.push({ sort: f.name, html: folderTile(f, false) });
              });
              spotlights.forEach(s => {
                rows.push({ sort: s.title, html: folderTile(s, true) });
              });
              files.forEach(f => {
                rows.push({ sort: f.name, html: fileTile(f) });
              });
              rows.sort((a, b) => a.sort.localeCompare(b.sort, undefined, { sensitivity: 'base', numeric: true }));
              library.innerHTML = '<div class="list">' + rows.map(r => r.html).join('') + '</div>';

              library.querySelectorAll('[data-open-folder]').forEach(el => {
                el.addEventListener('click', (e) => {
                  if (e.target.closest('a,button.download')) return;
                  currentPath = el.getAttribute('data-open-folder') || '';
                  spotlight = null;
                  refreshLibrary();
                });
              });
              library.querySelectorAll('[data-open-spot]').forEach(el => {
                el.addEventListener('click', (e) => {
                  if (e.target.closest('a,button.download')) return;
                  const id = el.getAttribute('data-open-spot');
                  const spot = (data.spotlights || []).find(s => s.id === id);
                  if (spot) { spotlight = spot; renderLibrary(data); }
                });
              });
            }

            function folderTile(item, isSpot) {
              const name = isSpot ? item.title : item.name;
              const sub = isSpot ? 'Kinema Spotlight · ' + (item.files?.length || 0) + ' titles'
                                : 'Folder' + (item.count != null ? ' · ' + item.count + ' items' : '');
              const openAttr = isSpot
                ? 'data-open-spot="' + escapeAttr(item.id) + '"'
                : 'data-open-folder="' + escapeAttr(joinPath(currentPath, item.name)) + '"';
              const dl = isSpot
                ? '/zip?files=' + encodeURIComponent((item.files || []).map(f => f.path).join('|'))
                : '/zip?path=' + encodeURIComponent(joinPath(currentPath, item.name));
              return `
                <div class="tile folder" ${openAttr}>
                  <div class="icon-box ${isSpot ? 'spot' : ''}">${isSpot ? 'S' : 'F'}</div>
                  <div class="meta">
                    <div class="name">${escapeHtml(name)}</div>
                    <div class="sub">${escapeHtml(sub)}</div>
                  </div>
                  <div class="tile-actions">
                    <a class="btn-small accent download" href="${dl}">Download</a>
                  </div>
                </div>`;
            }

            function fileTile(f) {
              const thumb = '/thumb/' + enc(f.path);
              const dl = '/download/' + enc(f.path);
              const icon = f.kind === 'audio' ? '♪' : '▶';
              return `
                <div class="tile">
                  <div class="thumb-box">
                    <div class="ph">${icon}</div>
                    <img src="${thumb}" alt="" loading="lazy"
                      onload="this.previousElementSibling.style.display='none'"
                      onerror="this.remove()"/>
                  </div>
                  <div class="meta">
                    <div class="name" title="${escapeAttr(f.name)}">${escapeHtml(f.name)}</div>
                    <div class="sub">${escapeHtml((f.ext || '').toUpperCase())} · ${formatBytes(f.size)}</div>
                  </div>
                  <div class="tile-actions">
                    <a class="btn-small accent download" href="${dl}" download="${escapeAttr(f.name)}.${escapeAttr((f.ext||'').toLowerCase())}">Download</a>
                  </div>
                </div>`;
            }

            async function refreshLibrary() {
              const url = '/api/library?path=' + encodeURIComponent(currentPath);
              const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
              const data = await res.json();
              if (spotlight) {
                // Keep spotlight context but refresh underlying listing payload if needed
                const spot = (data.spotlights || []).find(s => s.id === spotlight.id);
                if (spot) spotlight = spot;
              }
              renderLibrary(data);
            }

            function addJob(label) {
              const row = document.createElement('div');
              row.className = 'job';
              row.innerHTML = '<div class="job-name"></div><div class="job-meta">Waiting…</div><div class="bar"><i></i></div>';
              row.querySelector('.job-name').textContent = label;
              queue.appendChild(row);
              return row;
            }

            function uploadFile(file, relativePath) {
              const row = addJob(relativePath || file.name);
              const meta = row.querySelector('.job-meta');
              const bar = row.querySelector('.bar > i');
              const fd = new FormData();
              fd.append('files', file, relativePath || file.name);
              return new Promise((resolve) => {
                const xhr = new XMLHttpRequest();
                xhr.open('POST', '/upload?json=1');
                xhr.upload.onprogress = (e) => {
                  if (!e.lengthComputable) return;
                  const pct = Math.round(e.loaded / e.total * 100);
                  bar.style.width = pct + '%';
                  meta.textContent = pct + '%';
                };
                xhr.onload = () => {
                  const ok = xhr.status >= 200 && xhr.status < 300;
                  bar.style.width = '100%';
                  meta.textContent = ok ? 'Done' : 'Failed';
                  meta.style.color = ok ? '#34C759' : '#FF3B30';
                  resolve(ok);
                };
                xhr.onerror = () => { meta.textContent = 'Error'; meta.style.color = '#FF3B30'; resolve(false); };
                xhr.send(fd);
              });
            }

            async function handleFileList(fileList) {
              const files = Array.from(fileList || []);
              if (!files.length) return;
              let ok = 0;
              for (const file of files) {
                const rel = file.webkitRelativePath || file.name;
                if (await uploadFile(file, rel)) ok++;
              }
              showToast(ok === files.length ? 'Uploaded to Kinema' : ('Uploaded ' + ok + ' of ' + files.length));
              spotlight = null;
              await refreshLibrary();
            }

            drop.addEventListener('click', (e) => {
              if (e.target.closest('button')) return;
              fileInput.click();
            });
            document.getElementById('pickFiles').addEventListener('click', (e) => { e.stopPropagation(); fileInput.click(); });
            document.getElementById('pickFolder').addEventListener('click', (e) => { e.stopPropagation(); folderInput.click(); });
            fileInput.addEventListener('change', () => handleFileList(fileInput.files));
            folderInput.addEventListener('change', () => handleFileList(folderInput.files));
            ;['dragenter','dragover'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.add('over'); }));
            ;['dragleave','drop'].forEach(ev => drop.addEventListener(ev, e => { e.preventDefault(); drop.classList.remove('over'); }));
            drop.addEventListener('drop', e => handleFileList(e.dataTransfer.files));
            document.getElementById('refreshBtn').addEventListener('click', () => { spotlight = null; refreshLibrary(); });
            refreshLibrary();
          </script>
        </body>
        </html>
        """
    }

    static func resultPage(message: String, success: Bool) -> String {
        let safe = htmlEscape(message)
        return """
        <!DOCTYPE html>
        <html lang="en"><head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1"/>
          <meta http-equiv="refresh" content="2;url=/"/>
          <title>Kinema</title>
          <style>
            body{margin:0;min-height:100vh;display:grid;place-items:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#F2F2F7;color:#1C1C1E}
            .card{background:#fff;border-radius:16px;padding:24px;width:min(400px,calc(100% - 32px));text-align:center;border:1px solid rgba(60,60,67,.12)}
            a{color:#C45B6A}
          </style>
        </head>
        <body><div class="card">
          <h1 style="margin:0 0 8px;font-size:1.25rem">\(success ? "In your library" : "Upload issue")</h1>
          <p style="color:#8E8E93">\(safe)</p>
          <p><a href="/">Back to Kinema</a></p>
        </div></body></html>
        """
    }

    static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
