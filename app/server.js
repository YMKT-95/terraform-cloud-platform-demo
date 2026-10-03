import express from 'express';

const app = express();
const port = Number(process.env.PORT ?? 3000);

if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535');
}

app.disable('x-powered-by');

app.get('/', (_request, response) => {
  response.json({ service: 'terraform-cloud-platform-demo', version: '0.1.0' });
});

app.get('/health', (_request, response) => {
  response.json({ status: 'healthy' });
});

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
