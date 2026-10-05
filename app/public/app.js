const get = (id) => document.getElementById(id);
get('health-url').textContent = `${location.origin}/health`;
async function check() {
  get('refresh').disabled = true;
  get('status').textContent = 'Checking…';
  get('status').className = 'status checking';
  const started = performance.now();
  try {
    const response = await fetch('/health', { cache: 'no-store', signal: AbortSignal.timeout(8000) });
    const body = await response.json();
    if (!response.ok || body.status !== 'healthy') throw new Error('Unexpected health response');
    get('latency').textContent = `${Math.round(performance.now() - started)} ms`;
    get('health-body').textContent = JSON.stringify(body, null, 2);
    get('health-detail').textContent = `# HTTP ${response.status} · measured from your browser`;
    get('status').textContent = 'Healthy';
    get('status').className = 'status healthy';
  } catch {
    get('status').textContent = 'Unavailable';
    get('status').className = 'status error';
    get('latency').textContent = '—';
    get('health-body').textContent = 'Health check could not be completed.';
    get('health-detail').textContent = '# Check your connection or try again.';
  } finally {
    get('checked').textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    get('refresh').disabled = false;
  }
}
async function release() {
  try {
    const response = await fetch('/api/info', { cache: 'no-store', signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('Release info unavailable');
    const info = await response.json();
    get('version').textContent = `v${info.version}`;
    get('region').textContent = info.region === 'local' ? 'Local preview' : `${info.region} · AWS EC2`;
    if (/^[0-9a-f]{40}$/.test(info.revision)) {
      get('revision').textContent = info.revision.slice(0, 7);
      get('revision').href = `https://github.com/YMKT-95/terraform-cloud-platform-demo/commit/${info.revision}`;
    } else get('revision').textContent = 'local';
  } catch { get('region').textContent = 'Release metadata unavailable'; }
}
get('refresh').addEventListener('click', check);
check();
release();
