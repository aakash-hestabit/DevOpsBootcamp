# Basic TypeScript Node.js App

A very simple Node.js application built with TypeScript and Express.

## Features

- **Three simple routes:**
  - `GET /` - Welcome message with available routes
  - `GET /hello` - Hello message with timestamp
  - `GET /health` - Health check endpoint with status and uptime

## Installation

```bash
npm install
```

## Running the App

### Development Mode (with ts-node)
```bash
npm run dev
```

### Build for Production
```bash
npm run build
```

### Run Production Build
```bash
npm start
```

## Testing the Routes

Once the server is running:

```bash
# Hello route
curl http://localhost:3000/hello

# Health check
curl http://localhost:3000/health

# Root route
curl http://localhost:3000/
```

## Project Structure

```
basic_ts_app/
├── src/
│   └── index.ts          # Main application file
├── dist/                 # Compiled JavaScript (generated after build)
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
└── README.md             # This file
```

## Requirements

- Node.js v14 or higher
- npm or yarn

## Technologies

- **Express** - Web framework
- **TypeScript** - Type-safe JavaScript
