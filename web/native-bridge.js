// Shared by WKWebView and Android WebView. Product UI stays owned by the relay.
(() => {
  if (window.__remoteCodexNativeInstalled) return;
  window.__remoteCodexNativeInstalled = true;
  const send = (type, data = {}) => {
    const message = JSON.stringify({ type, ...data });
    if (window.RemoteCodexHost) window.RemoteCodexHost.postMessage(message);
    else window.webkit?.messageHandlers?.remoteCodex?.postMessage(message);
  };
  const viewport = () => {
    if (!document.documentElement || !(window.innerHeight > 0)) return;
    // Some WebViews retain a zero small-viewport height when the first page
    // loads before its native view is measured. Use the actual native viewport.
    document.documentElement.style.setProperty('--remote-codex-native-height', `${window.innerHeight}px`);
    if (document.head && !document.getElementById('remote-codex-native-viewport')) {
      const style = document.createElement('style');
      style.id = 'remote-codex-native-viewport';
      style.textContent = 'html .thread-ui-shell.thread-ui-viewport-constrained { height: var(--remote-codex-native-height); max-height: var(--remote-codex-native-height); }';
      document.head.append(style);
    }
  };
  const report = () => { viewport(); send('state', {
    path: location.pathname + location.search + location.hash,
    theme: localStorage.getItem('remote-codex-theme-mode') || 'system',
  }); };
  for (const name of ['pushState', 'replaceState']) {
    const original = history[name];
    history[name] = function (...args) {
      const result = original.apply(this, args);
      report();
      return result;
    };
  }
  addEventListener('popstate', report);
  addEventListener('pageshow', report);
  addEventListener('DOMContentLoaded', report);
  addEventListener('resize', viewport);
  // Fetch remains untouched: credentials, E2EE and real Service Workers belong
  // to the website. Poll state only to synchronize native cookies/theme on login.
  setInterval(report, 2000);
  const pending = new Map();
  let nextId = 0;
  window.remoteCodexNative = {
    platform: window.webkit?.messageHandlers?.remoteCodex ? 'ios' : 'android',
    changeRelay: () => send('changeRelay'),
    notificationSettings: () => send('notificationSettings'),
    resolve: (id, error) => {
      const task = pending.get(id);
      if (!task) return;
      pending.delete(id);
      error ? task.reject(new Error(error)) : task.resolve();
    },
  };
  const share = data => new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    send('share', { id, title: data.title || '', text: data.text || '', url: data.url || '' });
  });
  if (!navigator.share) {
    navigator.share = share;
    navigator.canShare = data => !data.files;
  }
  document.addEventListener('click', async event => {
    const link = event.target.closest?.('a[download]');
    if (!link || !/^(blob:|data:)/.test(link.href)) return;
    event.preventDefault();
    try {
      const blob = await (await fetch(link.href)).blob();
      if (blob.size > 32 * 1024 * 1024) throw new Error('Download exceeds the 32 MB mobile export limit.');
      const reader = new FileReader();
      reader.onload = () => send('download', {
        name: link.download || 'download', mime: blob.type || 'application/octet-stream', data: reader.result,
      });
      reader.readAsDataURL(blob);
    } catch (error) { send('error', { message: error.message }); }
  }, true);
  report();
})();
