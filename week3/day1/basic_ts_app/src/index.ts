import express, { Express, Request, Response } from 'express';

const app: Express = express();
const PORT: number = 3000;

// Health Check Route
app.get('/health', (req: Request, res: Response): void => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Hello Route
app.get('/hello', (req: Request, res: Response): void => {
  res.json({
    message: 'Hello from TypeScript Node.js App!',
    timestamp: new Date().toISOString()
  });
});

// Root Route
app.get('/', (req: Request, res: Response): void => {
  res.json({
    message: 'Welcome to TypeScript App',
    routes: {
      health: '/health',
      hello: '/hello'
    }
  });
});

app.listen(PORT, (): void => {
  console.log(`Server is running at http://localhost:${PORT}`);
  console.log('Available routes:');
  console.log('  GET / - Welcome message');
  console.log('  GET /hello - Hello message');
  console.log('  GET /health - Health check');
});
