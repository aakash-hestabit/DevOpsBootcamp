from fastapi import FastAPI
import os
import time

app = FastAPI()
start_time = time.time()

@app.get("/")
def root():
    return {"message": "Hello from FastAPI"}

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "uptime_seconds": round(time.time() - start_time, 2)
    }