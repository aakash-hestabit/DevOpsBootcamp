# K8s Frontend

## Features

- Real-time health status monitoring
- Backend connectivity check
- Database connection status
- Automatic polling every 10 seconds
- Dark theme with blue accents


The frontend runs on `http://localhost:3000`

### Environment Variables

```
REACT_APP_API_URL=http://localhost:8000
PORT=3000
```


## API Endpoints Used

- `GET /health` - Backend health status
- `GET /ready` - Database connection status
