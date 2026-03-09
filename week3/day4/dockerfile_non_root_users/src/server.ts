import express, { Request, Response } from "express";

const app = express();
const PORT = 3000;

app.get("/", (_req: Request, res: Response) => {
  res.json({
    message: "Hello from a non-root container!",
    user: process.env.USER ?? "nodejs",
    node_env: process.env.NODE_ENV ?? "development",
  });
});

app.get("/health", (_req: Request, res: Response) => {
  res.status(200).json({ status: "ok", timestamp: new Date().toISOString() });
});

app.get("/whoami", (_req: Request, res: Response) => {
  res.json({
    pid: process.pid,
    uid: process.getuid ? process.getuid() : "n/a",
    gid: process.getgid ? process.getgid() : "n/a",
    node_version: process.version,
  });
});

app.listen(PORT, () => {
  console.log(`[server] listening on port ${PORT}`);
  console.log(`[server] running as uid=${process.getuid ? process.getuid() : "unknown"}`);
});
