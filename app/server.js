import express from 'express';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const { version } = JSON.parse(readFileSync(new URL('./package.json', import.meta.url)));

const app = express();
const port = Number(process.env.PORT ?? 3000);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535');
}

app.disable('x-powered-by');

app.use((_request, response, next) => {
  response.set('X-Content-Type-Options', 'nosniff');
  response.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'");
  next();
});

app.get('/api/info', (_request, response) => {
  response.set('Cache-Control', 'no-store');
  response.json({ service: 'terraform-cloud-platform-demo', version, revision: process.env.APP_REVISION ?? 'local', region: process.env.DEPLOY_REGION ?? 'local' });
});

app.get('/health', (_request, response) => {
  response.set('Cache-Control', 'no-store');
  response.json({ status: 'healthy' });
});

app.use(express.static(fileURLToPath(new URL('./public', import.meta.url)), { maxAge: 0 }));

const server = app.listen(port, '0.0.0.0', (error) => {
  if (error) {
    console.error('Failed to start HTTP server:', error.message);
    process.exit(1);
  }
  console.log(`Application listening on port ${port}`);
});

function shutdown(signal) {
  console.log(`${signal} received; closing HTTP server`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 5000).unref();
}

process.once('SIGTERM', () => shutdown('SIGTERM'));
process.once('SIGINT', () => shutdown('SIGINT'));
